import { generateKeyPairSync, verify } from "node:crypto";
import { beforeEach, describe, expect, it } from "vitest";
import {
  APNS_PRODUCTION_HOST,
  APNS_SANDBOX_HOST,
  APNS_TOKEN_RENEW_MS,
  apnsConfigFromEnv,
  apnsJwt,
  pkcs8BytesFromP8,
  resetApnsTokenCache,
  sendApnsPush,
} from "../src/apns";
import type { ApnsConfig, ApnsDevice } from "../src/apns";
import { makePushPayload, sendMakeEvent } from "../src/push";
import { makeMigratedD1 } from "../test/helpers/migrated-d1";

// The APNs sender for Make pushes (founder, 2026-10-24; docs/briefs/make-contract.md section 4):
// an ES256 JWT from the .p8 key, cached and renewed after 45 minutes; one POST per device with the
// Apple headers; 410 and BadDeviceToken disable a device (after trying the other host once),
// ExpiredProviderToken gets a new token and one retry. fetch is a stand-in: no real send here.

const KEY_PAIR = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
const KEY_P8 = KEY_PAIR.privateKey.export({ type: "pkcs8", format: "pem" }).toString();
const CONFIG: ApnsConfig = { keyP8: KEY_P8, keyId: "KEY1234567", teamId: "ZQ2JPFYL98" };
const TOKEN = "a".repeat(64);
const NOW_MS = Date.parse("2026-10-24T18:00:00.000Z");

type FetchCall = { url: string; init: RequestInit };
type Reply = { status: number; reason?: string };

// Answers each call from the list in order (the last one repeats) and records every call.
function makeFakeFetch(replies: Reply[]) {
  const calls: FetchCall[] = [];
  async function fakeFetch(url: string, init: RequestInit): Promise<Response> {
    calls.push({ url, init });
    const reply = replies[Math.min(calls.length - 1, replies.length - 1)];
    if (reply.status === 200) {
      return new Response(null, { status: 200 });
    }
    return new Response(JSON.stringify({ reason: reply.reason ?? "" }), { status: reply.status });
  }
  return { fakeFetch, calls };
}

function headerOf(call: FetchCall, name: string): string | undefined {
  const headers = call.init.headers as Record<string, string>;
  return headers[name];
}

function decodeSegment(segment: string): Record<string, unknown> {
  const json = Buffer.from(segment, "base64url").toString("utf8");
  return JSON.parse(json) as Record<string, unknown>;
}

function device(env: "sandbox" | "production"): ApnsDevice {
  return { token: TOKEN, env, bundleId: "com.bhuvanrj.midas.test" };
}

beforeEach(() => {
  resetApnsTokenCache();
});

describe("APNs token", () => {
  it("is an ES256 JWT with kid, iss and iat, signed by the .p8 key", async () => {
    const jwt = await apnsJwt(CONFIG, NOW_MS);
    const [headerPart, claimsPart, signaturePart] = jwt.split(".");
    expect(decodeSegment(headerPart)).toEqual({ alg: "ES256", kid: "KEY1234567" });
    expect(decodeSegment(claimsPart)).toEqual({ iss: "ZQ2JPFYL98", iat: Math.floor(NOW_MS / 1000) });
    const signature = Buffer.from(signaturePart, "base64url");
    expect(signature.length).toBe(64);
    const signedInput = Buffer.from(`${headerPart}.${claimsPart}`);
    const isValid = verify("sha256", signedInput, { key: KEY_PAIR.publicKey, dsaEncoding: "ieee-p1363" }, signature);
    expect(isValid).toBe(true);
  });

  it("is reused for 45 minutes and renewed after", async () => {
    const first = await apnsJwt(CONFIG, NOW_MS);
    const stillCached = await apnsJwt(CONFIG, NOW_MS + APNS_TOKEN_RENEW_MS - 1000);
    const renewed = await apnsJwt(CONFIG, NOW_MS + APNS_TOKEN_RENEW_MS + 1000);
    expect(stillCached).toBe(first);
    expect(renewed).not.toBe(first);
    expect(decodeSegment(renewed.split(".")[1]).iat).toBe(Math.floor((NOW_MS + APNS_TOKEN_RENEW_MS + 1000) / 1000));
    expect(APNS_TOKEN_RENEW_MS).toBe(45 * 60 * 1000);
  });

  it("reads a .p8 pasted with literal \\n in place of line breaks", () => {
    const pastedOnOneLine = KEY_P8.replaceAll("\n", "\\n");
    expect(pkcs8BytesFromP8(pastedOnOneLine)).toEqual(pkcs8BytesFromP8(KEY_P8));
  });

  it("needs all three secrets", () => {
    expect(apnsConfigFromEnv({ APNS_KEY_P8: KEY_P8, APNS_KEY_ID: "K", APNS_TEAM_ID: "T" })).toEqual({ keyP8: KEY_P8, keyId: "K", teamId: "T" });
    expect(apnsConfigFromEnv({ APNS_KEY_P8: KEY_P8, APNS_KEY_ID: "K" })).toBeNull();
    expect(apnsConfigFromEnv({})).toBeNull();
  });
});

describe("one APNs send", () => {
  it("posts to the device's host with Apple's headers and the payload", async () => {
    const { fakeFetch, calls } = makeFakeFetch([{ status: 200 }]);
    const outcome = await sendApnsPush(fakeFetch, CONFIG, device("sandbox"), { aps: { alert: { title: "T", body: "B" } } }, NOW_MS);
    expect(outcome).toEqual({ kind: "sent", env: "sandbox" });
    expect(calls).toHaveLength(1);
    expect(calls[0].url).toBe(`${APNS_SANDBOX_HOST}/3/device/${TOKEN}`);
    expect(calls[0].init.method).toBe("POST");
    expect(headerOf(calls[0], "authorization")).toMatch(/^bearer [\w-]+\.[\w-]+\.[\w-]+$/);
    expect(headerOf(calls[0], "apns-topic")).toBe("com.bhuvanrj.midas.test");
    expect(headerOf(calls[0], "apns-push-type")).toBe("alert");
    expect(headerOf(calls[0], "apns-priority")).toBe("10");
    expect(JSON.parse(String(calls[0].init.body))).toEqual({ aps: { alert: { title: "T", body: "B" } } });
  });

  it("uses the production host for a production device", async () => {
    const { fakeFetch, calls } = makeFakeFetch([{ status: 200 }]);
    await sendApnsPush(fakeFetch, CONFIG, device("production"), {}, NOW_MS);
    expect(calls[0].url).toBe(`${APNS_PRODUCTION_HOST}/3/device/${TOKEN}`);
    expect(APNS_PRODUCTION_HOST).toBe("https://api.push.apple.com");
    expect(APNS_SANDBOX_HOST).toBe("https://api.sandbox.push.apple.com");
  });

  it("410: the device is to be disabled", async () => {
    const { fakeFetch, calls } = makeFakeFetch([{ status: 410, reason: "Unregistered" }]);
    const outcome = await sendApnsPush(fakeFetch, CONFIG, device("production"), {}, NOW_MS);
    expect(outcome).toEqual({ kind: "disable", reason: "410 Unregistered" });
    expect(calls).toHaveLength(1);
  });

  it("BadDeviceToken: tries the other host once, and moves the device when that works", async () => {
    const { fakeFetch, calls } = makeFakeFetch([{ status: 400, reason: "BadDeviceToken" }, { status: 200 }]);
    const outcome = await sendApnsPush(fakeFetch, CONFIG, device("production"), {}, NOW_MS);
    expect(outcome).toEqual({ kind: "moved", env: "sandbox" });
    expect(calls).toHaveLength(2);
    expect(calls[0].url.startsWith(APNS_PRODUCTION_HOST)).toBe(true);
    expect(calls[1].url.startsWith(APNS_SANDBOX_HOST)).toBe(true);
  });

  it("BadDeviceToken on both hosts: the device is to be disabled", async () => {
    const { fakeFetch, calls } = makeFakeFetch([{ status: 400, reason: "BadDeviceToken" }]);
    const outcome = await sendApnsPush(fakeFetch, CONFIG, device("sandbox"), {}, NOW_MS);
    expect(outcome).toEqual({ kind: "disable", reason: "400 BadDeviceToken" });
    expect(calls).toHaveLength(2);
  });

  it("ExpiredProviderToken: a new token and one retry", async () => {
    const { fakeFetch, calls } = makeFakeFetch([{ status: 403, reason: "ExpiredProviderToken" }, { status: 200 }]);
    const outcome = await sendApnsPush(fakeFetch, CONFIG, device("sandbox"), {}, NOW_MS);
    expect(outcome).toEqual({ kind: "sent", env: "sandbox" });
    expect(calls).toHaveLength(2);
    expect(headerOf(calls[0], "authorization")).not.toBe(headerOf(calls[1], "authorization"));
  });

  it("ExpiredProviderToken twice: one retry only, then failed", async () => {
    const { fakeFetch, calls } = makeFakeFetch([{ status: 403, reason: "ExpiredProviderToken" }]);
    const outcome = await sendApnsPush(fakeFetch, CONFIG, device("sandbox"), {}, NOW_MS);
    expect(outcome).toEqual({ kind: "failed", reason: "403 ExpiredProviderToken" });
    expect(calls).toHaveLength(2);
  });

  it("any other reply or a network error is failed, never thrown", async () => {
    const { fakeFetch } = makeFakeFetch([{ status: 500, reason: "InternalServerError" }]);
    const serverError = await sendApnsPush(fakeFetch, CONFIG, device("sandbox"), {}, NOW_MS);
    expect(serverError).toEqual({ kind: "failed", reason: "500 InternalServerError" });
    async function brokenFetch(): Promise<Response> {
      throw new Error("HTTP/2 not available");
    }
    const networkError = await sendApnsPush(brokenFetch, CONFIG, device("sandbox"), {}, NOW_MS);
    expect(networkError).toEqual({ kind: "failed", reason: "error HTTP/2 not available" });
  });
});

/* ---------- One make_events row to every device of its user ---------- */

type Db = ReturnType<typeof makeMigratedD1>;

const SECRETS = { APNS_KEY_P8: KEY_P8, APNS_KEY_ID: "KEY1234567", APNS_TEAM_ID: "ZQ2JPFYL98" };

function seedEvent(db: Db, kind: string, eventId: string) {
  db.execute("INSERT INTO users (id, name, created_at) VALUES ('u-priya', 'Priya', 'then')");
  db.execute(
    "INSERT INTO make_events (id, audience, user_id, about_user_id, request_id, kind, title, body, created_at) VALUES (?, 'person', 'u-priya', 'u-priya', 'req00001', ?, 'Bhuvan', 'Which one?', 'then')",
    eventId,
    kind,
  );
}

function addDevice(db: Db, token: string, env: string, disabledAt: string | null = null) {
  db.execute(
    "INSERT INTO push_devices (token, user_id, env, bundle_id, created_at, updated_at, disabled_at) VALUES (?, 'u-priya', ?, 'com.bhuvanrj.midas.test', 'then', 'then', ?)",
    token,
    env,
    disabledAt,
  );
}

function eventRow(db: Db, eventId: string) {
  return db.query("SELECT sent_at, result FROM make_events WHERE id = ?", eventId)[0];
}

function deviceRow(db: Db, token: string) {
  return db.query("SELECT env, disabled_at, disabled_reason FROM push_devices WHERE token = ?", token)[0];
}

describe("sending one Make event", () => {
  it("sends the payload to every live device and marks the row sent", async () => {
    const db = makeMigratedD1();
    seedEvent(db, "card", "card:card0001");
    addDevice(db, "b".repeat(64), "sandbox");
    addDevice(db, "c".repeat(64), "production");
    addDevice(db, "d".repeat(64), "production", "earlier");
    const { fakeFetch, calls } = makeFakeFetch([{ status: 200 }]);
    await sendMakeEvent(db as unknown as D1Database, SECRETS, "card:card0001", fakeFetch, NOW_MS);
    expect(calls).toHaveLength(2);
    const payload = JSON.parse(String(calls[0].init.body));
    expect(payload).toEqual({
      aps: { alert: { title: "Bhuvan", body: "Which one?" }, sound: "default", "thread-id": "u-priya:req00001" },
      make: { kind: "card", requestId: "req00001", userId: "u-priya", cardId: "card0001" },
    });
    expect(eventRow(db, "card:card0001")).toEqual({ sent_at: new Date(NOW_MS).toISOString(), result: "sent 2 of 2" });
  });

  it("the payload has no cardId for other kinds", () => {
    const payload = makePushPayload({ id: "built:u-priya:req00001", audience: "person", user_id: "u-priya", about_user_id: "u-priya", request_id: "req00001", kind: "built", title: "Bhuvan", body: "Lamp: Built" });
    expect(payload.make).toEqual({ kind: "built", requestId: "req00001", userId: "u-priya" });
  });

  it("disables a device APNs says is gone, and fixes the env of one on the other host", async () => {
    const db = makeMigratedD1();
    seedEvent(db, "built", "built:u-priya:req00001");
    const goneToken = "b".repeat(64);
    const movedToken = "c".repeat(64);
    addDevice(db, goneToken, "production");
    addDevice(db, movedToken, "production");
    // goneToken sorts first: 410; movedToken: BadDeviceToken on production, 200 on sandbox
    const { fakeFetch } = makeFakeFetch([{ status: 410, reason: "Unregistered" }, { status: 400, reason: "BadDeviceToken" }, { status: 200 }]);
    await sendMakeEvent(db as unknown as D1Database, SECRETS, "built:u-priya:req00001", fakeFetch, NOW_MS);
    expect(deviceRow(db, goneToken)).toEqual({ env: "production", disabled_at: new Date(NOW_MS).toISOString(), disabled_reason: "410 Unregistered" });
    expect(deviceRow(db, movedToken)).toEqual({ env: "sandbox", disabled_at: null, disabled_reason: null });
    expect(eventRow(db, "built:u-priya:req00001")).toEqual({ sent_at: new Date(NOW_MS).toISOString(), result: "sent 1 of 2; disabled 1 (410 Unregistered)" });
  });

  it("leaves sent_at empty when every send failed for a reason that may pass", async () => {
    const db = makeMigratedD1();
    seedEvent(db, "card", "card:card0001");
    addDevice(db, "b".repeat(64), "sandbox");
    const { fakeFetch } = makeFakeFetch([{ status: 503, reason: "ServiceUnavailable" }]);
    await sendMakeEvent(db as unknown as D1Database, SECRETS, "card:card0001", fakeFetch, NOW_MS);
    expect(eventRow(db, "card:card0001")).toEqual({ sent_at: null, result: "sent 0 of 1; failed 1 (503 ServiceUnavailable)" });
  });

  it("without secrets sends nothing and leaves the row for a fallback sender", async () => {
    const db = makeMigratedD1();
    seedEvent(db, "card", "card:card0001");
    addDevice(db, "b".repeat(64), "sandbox");
    const { fakeFetch, calls } = makeFakeFetch([{ status: 200 }]);
    await sendMakeEvent(db as unknown as D1Database, {}, "card:card0001", fakeFetch, NOW_MS);
    expect(calls).toHaveLength(0);
    expect(eventRow(db, "card:card0001")).toEqual({ sent_at: null, result: "apns not set up" });
  });

  it("with no live device there is nothing to send: the row is final", async () => {
    const db = makeMigratedD1();
    seedEvent(db, "card", "card:card0001");
    addDevice(db, "b".repeat(64), "sandbox", "earlier");
    const { fakeFetch, calls } = makeFakeFetch([{ status: 200 }]);
    await sendMakeEvent(db as unknown as D1Database, SECRETS, "card:card0001", fakeFetch, NOW_MS);
    expect(calls).toHaveLength(0);
    expect(eventRow(db, "card:card0001")).toEqual({ sent_at: new Date(NOW_MS).toISOString(), result: "no devices" });
  });
});
