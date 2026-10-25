import { Hono } from "hono";
import type { Context } from "hono";
import { requireSession } from "./auth";
import { SIDEKICK_ID_PATTERN } from "./sidekicks";

// Repair asked for where it is not available (founder, 2026-10-24; docs/briefs/make-contract.md
// section 6). The three-finger swipe on Make, Inbox or jess shows "Repair not available for this
// Sidekick." and the shell logs it here, fire and forget, so the founder can see how often people
// try. POST /repairs/blocked {sidekickId, clientId, appVersion?, appBuild?}: 201 {logged:true}
// when stored now, 200 when this user's clientId was stored before.

type BlockedBindings = {
  DB: D1Database;
  RP_ID?: string;
};

type BlockedVariables = {
  userId: string;
};

type BlockedEnv = { Bindings: BlockedBindings; Variables: BlockedVariables };
type BlockedContext = Context<BlockedEnv>;

const CLIENT_ID_PATTERN = /^[A-Za-z0-9_-]{8,64}$/;
const MAX_APP_FIELD_LENGTH = 40;

function boundStatement(db: D1Database, sql: string, ...params: unknown[]): D1PreparedStatement {
  const prepared = db.prepare(sql);
  return prepared.bind(...params);
}

async function readJsonBody(c: BlockedContext): Promise<Record<string, unknown>> {
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

// An optional short text field: null when absent, the text when it fits, undefined when it does not.
function optionalAppField(value: unknown): string | null | undefined {
  if (value === undefined || value === null) {
    return null;
  }
  if (typeof value !== "string" || value.length > MAX_APP_FIELD_LENGTH) {
    return undefined;
  }
  return value;
}

async function handleBlocked(c: BlockedContext) {
  const body = await readJsonBody(c);
  if (typeof body.sidekickId !== "string" || !SIDEKICK_ID_PATTERN.test(body.sidekickId)) {
    return c.json({ error: "bad sidekickId" }, 400);
  }
  if (typeof body.clientId !== "string" || !CLIENT_ID_PATTERN.test(body.clientId)) {
    return c.json({ error: "clientId must be 8 to 64 letters, digits, - or _" }, 400);
  }
  const appVersion = optionalAppField(body.appVersion);
  const appBuild = optionalAppField(body.appBuild);
  if (appVersion === undefined || appBuild === undefined) {
    return c.json({ error: `appVersion and appBuild are at most ${MAX_APP_FIELD_LENGTH} characters` }, 400);
  }
  const insert = boundStatement(
    c.env.DB,
    `INSERT INTO repair_blocked (id, user_id, sidekick_id, client_id, app_version, app_build, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT(user_id, client_id) DO NOTHING`,
    crypto.randomUUID(),
    c.get("userId"),
    body.sidekickId,
    body.clientId,
    appVersion,
    appBuild,
    new Date().toISOString(),
  );
  const result = await insert.run();
  const storedNow = (result.meta?.changes ?? 0) > 0;
  return c.json({ logged: true }, storedNow ? 201 : 200);
}

export const repairBlockedRoutes = new Hono<BlockedEnv>();
repairBlockedRoutes.post("/blocked", requireSession, handleBlocked);
