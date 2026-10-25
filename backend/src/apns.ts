// APNs sender for Make pushes (founder, 2026-10-24; docs/briefs/make-contract.md section 4).
// Token-based auth: a JWT (ES256) signed with the founder's .p8 key, header {alg, kid}, claims
// {iss: team id, iat}. Apple accepts one token for up to an hour and refuses a new one more often
// than every 20 minutes, so a token is cached per key and renewed after 45 minutes.
// Secrets (the founder sets them): APNS_KEY_P8 (the .p8 file's text), APNS_KEY_ID, APNS_TEAM_ID.
//
// fetch is passed in so tests run without Apple. Risk, not yet tried: APNs speaks HTTP/2 only;
// whether a Worker's fetch reaches it has to be proven with one real send from staging. If it
// cannot, the unsent make_events rows are sent by the Mac mini instead.

export const APNS_PRODUCTION_HOST = "https://api.push.apple.com";
export const APNS_SANDBOX_HOST = "https://api.sandbox.push.apple.com";
export const APNS_TOKEN_RENEW_MS = 45 * 60 * 1000;

export type ApnsEnvironment = "sandbox" | "production";
export type FetchLike = (input: string, init: RequestInit) => Promise<Response>;

export type ApnsConfig = {
  keyP8: string;
  keyId: string;
  teamId: string;
};

export type ApnsDevice = {
  token: string;
  env: ApnsEnvironment;
  bundleId: string;
};

export type ApnsPayload = Record<string, unknown>;

// What one send came to. "disable": the token is dead (410, or BadDeviceToken on both hosts).
// "moved": the token works on the other host; the device's env should be set to it.
export type ApnsOutcome =
  | { kind: "sent"; env: ApnsEnvironment }
  | { kind: "moved"; env: ApnsEnvironment }
  | { kind: "disable"; reason: string }
  | { kind: "failed"; reason: string };

type CachedToken = { jwt: string; issuedAtMs: number };

// One isolate keeps one token per key, so every push in it reuses the same JWT.
const tokenCache = new Map<string, CachedToken>();

export function resetApnsTokenCache(): void {
  tokenCache.clear();
}

export function apnsHost(env: ApnsEnvironment): string {
  return env === "sandbox" ? APNS_SANDBOX_HOST : APNS_PRODUCTION_HOST;
}

function otherEnvironment(env: ApnsEnvironment): ApnsEnvironment {
  return env === "sandbox" ? "production" : "sandbox";
}

// The config from the Worker's secrets, or null when any of the three is missing.
export function apnsConfigFromEnv(env: { APNS_KEY_P8?: string; APNS_KEY_ID?: string; APNS_TEAM_ID?: string }): ApnsConfig | null {
  const keyP8 = env.APNS_KEY_P8;
  const keyId = env.APNS_KEY_ID;
  const teamId = env.APNS_TEAM_ID;
  if (!keyP8 || !keyId || !teamId) {
    return null;
  }
  return { keyP8, keyId, teamId };
}

/* ---------- JWT ---------- */

function base64UrlFromBytes(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  const base64 = btoa(binary);
  const urlSafe = base64.replaceAll("+", "-").replaceAll("/", "_");
  return urlSafe.replace(/=+$/, "");
}

function base64UrlFromJson(value: unknown): string {
  const jsonText = JSON.stringify(value);
  const jsonBytes = new TextEncoder().encode(jsonText);
  return base64UrlFromBytes(jsonBytes);
}

// The DER bytes inside a .p8 file. A secret pasted with literal "\n" in place of line breaks
// works too.
export function pkcs8BytesFromP8(keyP8: string): Uint8Array {
  const withLineBreaks = keyP8.replaceAll("\\n", "\n");
  const withoutArmour = withLineBreaks.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "");
  const base64 = withoutArmour.replace(/\s+/g, "");
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

// A new signed token. WebCrypto's ECDSA signature is already r||s (64 bytes), the form JWS wants.
export async function signApnsJwt(config: ApnsConfig, issuedAtSeconds: number): Promise<string> {
  const header = { alg: "ES256", kid: config.keyId };
  const claims = { iss: config.teamId, iat: issuedAtSeconds };
  const signingInput = `${base64UrlFromJson(header)}.${base64UrlFromJson(claims)}`;
  const keyBytes = pkcs8BytesFromP8(config.keyP8);
  const algorithm = { name: "ECDSA", namedCurve: "P-256" };
  const privateKey = await crypto.subtle.importKey("pkcs8", keyBytes, algorithm, false, ["sign"]);
  const inputBytes = new TextEncoder().encode(signingInput);
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, privateKey, inputBytes);
  const signatureText = base64UrlFromBytes(new Uint8Array(signature));
  return `${signingInput}.${signatureText}`;
}

// The cached token for this key, or a new one when there is none, it is 45 minutes old, or
// forceNew (APNs said ExpiredProviderToken).
export async function apnsJwt(config: ApnsConfig, nowMs: number, forceNew = false): Promise<string> {
  const cacheKey = `${config.teamId}:${config.keyId}`;
  const cached = tokenCache.get(cacheKey);
  const isFresh = cached !== undefined && nowMs - cached.issuedAtMs < APNS_TOKEN_RENEW_MS;
  if (cached !== undefined && isFresh && !forceNew) {
    return cached.jwt;
  }
  const issuedAtSeconds = Math.floor(nowMs / 1000);
  const jwt = await signApnsJwt(config, issuedAtSeconds);
  tokenCache.set(cacheKey, { jwt, issuedAtMs: nowMs });
  return jwt;
}

/* ---------- Sending ---------- */

type ApnsReply = { status: number; reason: string };

async function replyReason(response: Response): Promise<string> {
  try {
    const body = (await response.json()) as { reason?: unknown };
    return typeof body.reason === "string" ? body.reason : "";
  } catch {
    return "";
  }
}

async function postOnce(fetchImpl: FetchLike, env: ApnsEnvironment, device: ApnsDevice, payloadText: string, jwt: string): Promise<ApnsReply> {
  const url = `${apnsHost(env)}/3/device/${device.token}`;
  const requestInit = {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": device.bundleId,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: payloadText,
  };
  const response = await fetchImpl(url, requestInit);
  if (response.status === 200) {
    return { status: 200, reason: "" };
  }
  const reason = await replyReason(response);
  return { status: response.status, reason };
}

// One post, with one retry on a fresh token when APNs says the token expired.
async function postWithFreshTokenRetry(fetchImpl: FetchLike, config: ApnsConfig, env: ApnsEnvironment, device: ApnsDevice, payloadText: string, nowMs: number): Promise<ApnsReply> {
  const jwt = await apnsJwt(config, nowMs);
  const reply = await postOnce(fetchImpl, env, device, payloadText, jwt);
  const tokenExpired = reply.status === 403 && reply.reason === "ExpiredProviderToken";
  if (!tokenExpired) {
    return reply;
  }
  const freshJwt = await apnsJwt(config, nowMs, true);
  return postOnce(fetchImpl, env, device, payloadText, freshJwt);
}

function describeReply(reply: ApnsReply): string {
  return reply.reason.length > 0 ? `${reply.status} ${reply.reason}` : String(reply.status);
}

// Sends one push to one device. Never throws: a network error is a "failed" outcome.
// 410: the token is gone, disable it. 400 BadDeviceToken: the token may belong to the other host
// (a build signed for the other APNs environment); try that host once, and if it works the
// device's env is fixed, else disable.
export async function sendApnsPush(fetchImpl: FetchLike, config: ApnsConfig, device: ApnsDevice, payload: ApnsPayload, nowMs: number): Promise<ApnsOutcome> {
  const payloadText = JSON.stringify(payload);
  try {
    const reply = await postWithFreshTokenRetry(fetchImpl, config, device.env, device, payloadText, nowMs);
    if (reply.status === 200) {
      return { kind: "sent", env: device.env };
    }
    if (reply.status === 410) {
      return { kind: "disable", reason: describeReply(reply) };
    }
    const isBadToken = reply.status === 400 && reply.reason === "BadDeviceToken";
    if (!isBadToken) {
      return { kind: "failed", reason: describeReply(reply) };
    }
    const otherEnv = otherEnvironment(device.env);
    const otherReply = await postWithFreshTokenRetry(fetchImpl, config, otherEnv, device, payloadText, nowMs);
    if (otherReply.status === 200) {
      return { kind: "moved", env: otherEnv };
    }
    const otherIsDead = otherReply.status === 410 || (otherReply.status === 400 && otherReply.reason === "BadDeviceToken");
    if (otherIsDead) {
      return { kind: "disable", reason: describeReply(reply) };
    }
    return { kind: "failed", reason: describeReply(otherReply) };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return { kind: "failed", reason: `error ${message}` };
  }
}
