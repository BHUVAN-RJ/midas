import { Hono } from "hono";
import type { Context } from "hono";
import { requireSession } from "./auth";
import { apnsConfigFromEnv, sendApnsPush } from "./apns";
import type { ApnsDevice, ApnsEnvironment, ApnsOutcome, FetchLike } from "./apns";

// Push for Make (founder, 2026-10-24; docs/briefs/make-contract.md section 4).
// POST /push/register: the shell sends its APNs device token on every launch.
// sendMakeEvents: sends the make_events rows a write just inserted, to every live device of the
// row's user. Each outcome is written back: result always, sent_at once the send has a final
// outcome (delivered, or nothing left to deliver to). A row whose send failed for a reason that
// may pass (APNs down, secrets missing, HTTP/2 not reachable) keeps sent_at NULL for a fallback
// sender to pick up.

export type PushBindings = {
  DB: D1Database;
  RP_ID?: string;
  APNS_KEY_P8?: string;
  APNS_KEY_ID?: string;
  APNS_TEAM_ID?: string;
  // Tests only: stands in for fetch to APNs. Never set in wrangler.jsonc.
  PUSH_FETCH?: unknown;
};

type PushVariables = {
  userId: string;
};

type PushEnv = { Bindings: PushBindings; Variables: PushVariables };
type PushContext = Context<PushEnv>;

// APNs device tokens are hex (32 bytes today; Apple says not to assume the length).
const DEVICE_TOKEN_PATTERN = /^[0-9a-fA-F]{32,200}$/;
const PUSH_ENVIRONMENTS = new Set(["sandbox", "production"]);
export const PUSH_BUNDLE_IDS = new Set(["com.bhuvanrj.midas", "com.bhuvanrj.midas.test"]);

type MakeEventRow = {
  id: string;
  audience: string;
  user_id: string;
  about_user_id: string;
  request_id: string;
  kind: string;
  title: string;
  body: string;
};

type DeviceRow = {
  token: string;
  env: ApnsEnvironment;
  bundle_id: string;
};

function boundStatement(db: D1Database, sql: string, ...params: unknown[]): D1PreparedStatement {
  const prepared = db.prepare(sql);
  return prepared.bind(...params);
}

async function readJsonBody(c: PushContext): Promise<Record<string, unknown>> {
  try {
    const body = await c.req.json();
    if (typeof body === "object" && body !== null) {
      return body as Record<string, unknown>;
    }
    return {};
  } catch {
    return {};
  }
}

// POST /push/register {token, env, bundleId} -> {ok:true}. A token seen before moves to this user
// and is live again (a phone signed in as someone else, or a token APNs gave back).
async function handleRegister(c: PushContext) {
  const body = await readJsonBody(c);
  const token = body.token;
  if (typeof token !== "string" || !DEVICE_TOKEN_PATTERN.test(token)) {
    return c.json({ error: "token must be the device token in hex" }, 400);
  }
  if (typeof body.env !== "string" || !PUSH_ENVIRONMENTS.has(body.env)) {
    return c.json({ error: "env must be sandbox or production" }, 400);
  }
  if (typeof body.bundleId !== "string" || !PUSH_BUNDLE_IDS.has(body.bundleId)) {
    return c.json({ error: "unknown bundleId" }, 400);
  }
  const nowIso = new Date().toISOString();
  const upsert = boundStatement(
    c.env.DB,
    `INSERT INTO push_devices (token, user_id, env, bundle_id, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?)
     ON CONFLICT(token) DO UPDATE SET user_id = excluded.user_id, env = excluded.env,
       bundle_id = excluded.bundle_id, updated_at = excluded.updated_at, disabled_at = NULL, disabled_reason = NULL`,
    token.toLowerCase(),
    c.get("userId"),
    body.env,
    body.bundleId,
    nowIso,
    nowIso,
  );
  await upsert.run();
  return c.json({ ok: true });
}

/* ---------- Sending events ---------- */

function workerFetch(input: string, init: RequestInit): Promise<Response> {
  return fetch(input, init);
}

// The fetch used to reach APNs: the test stand-in when one is bound, else the Worker's own.
export function pushFetchFromEnv(env: { PUSH_FETCH?: unknown }): FetchLike {
  if (typeof env.PUSH_FETCH === "function") {
    return env.PUSH_FETCH as FetchLike;
  }
  return workerFetch;
}

// The payload the shell reads: aps for the banner, make for where a tap goes.
export function makePushPayload(event: MakeEventRow): Record<string, unknown> {
  const makeInfo: Record<string, string> = {
    kind: event.kind,
    requestId: event.request_id,
    userId: event.about_user_id,
  };
  // A card event's id is "card:<cardId>".
  if (event.kind === "card") {
    makeInfo.cardId = event.id.slice("card:".length);
  }
  return {
    aps: {
      alert: { title: event.title, body: event.body },
      sound: "default",
      "thread-id": `${event.about_user_id}:${event.request_id}`,
    },
    make: makeInfo,
  };
}

type SendTally = { sent: number; disabled: string[]; failed: string[] };

async function recordDeviceOutcome(db: D1Database, device: DeviceRow, outcome: ApnsOutcome, nowIso: string, tally: SendTally): Promise<void> {
  if (outcome.kind === "sent") {
    tally.sent += 1;
    return;
  }
  if (outcome.kind === "moved") {
    tally.sent += 1;
    const moveDevice = boundStatement(db, "UPDATE push_devices SET env = ?, updated_at = ? WHERE token = ?", outcome.env, nowIso, device.token);
    await moveDevice.run();
    return;
  }
  if (outcome.kind === "disable") {
    tally.disabled.push(outcome.reason);
    const disableDevice = boundStatement(db, "UPDATE push_devices SET disabled_at = ?, disabled_reason = ?, updated_at = ? WHERE token = ?", nowIso, outcome.reason, nowIso, device.token);
    await disableDevice.run();
    return;
  }
  tally.failed.push(outcome.reason);
}

function describeTally(tally: SendTally, deviceCount: number): string {
  const parts = [`sent ${tally.sent} of ${deviceCount}`];
  if (tally.disabled.length > 0) {
    parts.push(`disabled ${tally.disabled.length} (${tally.disabled.join(", ")})`);
  }
  if (tally.failed.length > 0) {
    parts.push(`failed ${tally.failed.length} (${tally.failed.join(", ")})`);
  }
  return parts.join("; ");
}

async function writeEventResult(db: D1Database, eventId: string, result: string, sentAt: string | null): Promise<void> {
  const update = boundStatement(db, "UPDATE make_events SET result = ?, sent_at = ? WHERE id = ?", result, sentAt, eventId);
  await update.run();
}

// Sends one event to every live device of its user and writes the outcome to its row.
export async function sendMakeEvent(db: D1Database, env: PushBindings, eventId: string, fetchImpl: FetchLike, nowMs: number): Promise<void> {
  const eventStatement = boundStatement(db, "SELECT id, audience, user_id, about_user_id, request_id, kind, title, body FROM make_events WHERE id = ?", eventId);
  const event = await eventStatement.first<MakeEventRow>();
  if (event === null) {
    return;
  }
  const nowIso = new Date(nowMs).toISOString();
  const config = apnsConfigFromEnv(env);
  if (config === null) {
    await writeEventResult(db, eventId, "apns not set up", null);
    return;
  }
  const devicesStatement = boundStatement(db, "SELECT token, env, bundle_id FROM push_devices WHERE user_id = ? AND disabled_at IS NULL ORDER BY token", event.user_id);
  const devicesResult = await devicesStatement.all<DeviceRow>();
  const devices = devicesResult.results;
  if (devices.length === 0) {
    await writeEventResult(db, eventId, "no devices", nowIso);
    return;
  }
  const payload = makePushPayload(event);
  const tally: SendTally = { sent: 0, disabled: [], failed: [] };
  for (const device of devices) {
    const apnsDevice: ApnsDevice = { token: device.token, env: device.env, bundleId: device.bundle_id };
    const outcome = await sendApnsPush(fetchImpl, config, apnsDevice, payload, nowMs);
    await recordDeviceOutcome(db, device, outcome, nowIso, tally);
  }
  // Final when something was delivered, or when no device failed for a reason that may pass.
  const isFinal = tally.sent > 0 || tally.failed.length === 0;
  const sentAt = isFinal ? nowIso : null;
  await writeEventResult(db, eventId, describeTally(tally, devices.length), sentAt);
}

// Sends each event in turn. One event failing never stops the others.
export async function sendMakeEvents(db: D1Database, env: PushBindings, eventIds: string[], fetchImpl: FetchLike): Promise<void> {
  for (const eventId of eventIds) {
    try {
      await sendMakeEvent(db, env, eventId, fetchImpl, Date.now());
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      console.error(`make push ${eventId} failed: ${message}`);
    }
  }
}

// Runs the pushes after the response, in waitUntil. Without an execution context (a test that
// passes none) the pushes run before the response instead.
export async function sendMakeEventsAfterResponse(c: Context, eventIds: string[]): Promise<void> {
  if (eventIds.length === 0) {
    return;
  }
  const env = c.env as PushBindings;
  const fetchImpl = pushFetchFromEnv(env);
  const sending = sendMakeEvents(env.DB, env, eventIds, fetchImpl);
  let executionContext: { waitUntil(promise: Promise<unknown>): void } | null = null;
  try {
    executionContext = c.executionCtx;
  } catch {
    executionContext = null;
  }
  if (executionContext === null) {
    await sending;
    return;
  }
  executionContext.waitUntil(sending);
}

export const pushRoutes = new Hono<PushEnv>();
pushRoutes.use("*", requireSession);
pushRoutes.post("/register", handleRegister);
