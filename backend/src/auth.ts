import { Hono } from "hono";
import type { Context, Next } from "hono";
import {
  generateAuthenticationOptions,
  generateRegistrationOptions,
  verifyAuthenticationResponse,
  verifyRegistrationResponse,
} from "@simplewebauthn/server";
import type {
  AuthenticationResponseJSON,
  AuthenticatorTransport,
  RegistrationResponseJSON,
} from "@simplewebauthn/server";
import { isoBase64URL } from "@simplewebauthn/server/helpers";

// Passkeys are bound to this domain. Changing it invalidates every passkey already created.
export const RELYING_PARTY_ID = "midas-api.midas-backend.workers.dev";
export const RELYING_PARTY_NAME = "Midas";
// iOS puts "https://<rp id>" in clientDataJSON for passkeys created by the app.
export const EXPECTED_ORIGIN = `https://${RELYING_PARTY_ID}`;
// Team ID plus bundle ID; the apple-app-site-association file lets this app use the domain.
export const APPLE_APP_ID = "ZQ2JPFYL98.com.bhuvanrj.midas";

export const CHALLENGE_LIFETIME_MS = 5 * 60 * 1000;
export const SESSION_LIFETIME_MS = 90 * 24 * 60 * 60 * 1000;
export const MAX_NAME_LENGTH = 50;

type AuthBindings = {
  DB: D1Database;
};

type AuthVariables = {
  userId: string;
};

type AuthEnv = { Bindings: AuthBindings; Variables: AuthVariables };
type AuthContext = Context<AuthEnv>;

type ChallengeRow = {
  id: string;
  challenge: string;
  purpose: "register" | "login";
  user_id: string | null;
  user_name: string | null;
  expires_at: number;
};

type PasskeyRow = {
  credential_id: string;
  user_id: string;
  public_key: string;
  counter: number;
  transports: string | null;
};

type UserRow = {
  id: string;
  name: string;
};

// Prepares and binds in one named step.
function boundStatement(db: D1Database, sql: string, ...params: unknown[]): D1PreparedStatement {
  const prepared = db.prepare(sql);
  return prepared.bind(...params);
}

function randomId(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  return isoBase64URL.fromBuffer(bytes);
}

function newSessionToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return isoBase64URL.fromBuffer(bytes);
}

async function hashToken(token: string): Promise<string> {
  const tokenBytes = new TextEncoder().encode(token);
  const digest = await crypto.subtle.digest("SHA-256", tokenBytes);
  const digestBytes = new Uint8Array(digest);
  const hexPairs = Array.from(digestBytes, byteToHex);
  return hexPairs.join("");
}

function byteToHex(byte: number): string {
  return byte.toString(16).padStart(2, "0");
}

function cleanName(rawName: unknown): string | null {
  if (typeof rawName !== "string") {
    return null;
  }
  const trimmedName = rawName.trim();
  if (trimmedName.length === 0 || trimmedName.length > MAX_NAME_LENGTH) {
    return null;
  }
  return trimmedName;
}

async function readJsonBody(c: AuthContext): Promise<Record<string, unknown>> {
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

async function storeChallenge(
  db: D1Database,
  challenge: string,
  purpose: ChallengeRow["purpose"],
  userId: string | null,
  userName: string | null,
): Promise<string> {
  const challengeId = randomId();
  const expiresAt = Date.now() + CHALLENGE_LIFETIME_MS;
  const insert = boundStatement(db, "INSERT INTO auth_challenges (id, challenge, purpose, user_id, user_name, expires_at) VALUES (?, ?, ?, ?, ?, ?)", challengeId, challenge, purpose, userId, userName, expiresAt);
  await insert.run();
  return challengeId;
}

// Deletes the challenge as it is read, so a challenge can be verified at most once, even if it
// turns out to be expired or for the other purpose.
async function takeChallenge(
  db: D1Database,
  challengeId: unknown,
  purpose: ChallengeRow["purpose"],
): Promise<ChallengeRow | null> {
  if (typeof challengeId !== "string") {
    return null;
  }
  const deleteStatement = boundStatement(db, "DELETE FROM auth_challenges WHERE id = ? RETURNING *", challengeId);
  const row = await deleteStatement.first<ChallengeRow>();
  if (row === null) {
    return null;
  }
  if (row.purpose !== purpose || row.expires_at < Date.now()) {
    return null;
  }
  return row;
}

function sessionInsert(db: D1Database, tokenHash: string, userId: string, nowIso: string) {
  const expiresAt = Date.now() + SESSION_LIFETIME_MS;
  return boundStatement(db, "INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, ?, ?)", tokenHash, userId, nowIso, expiresAt);
}

async function handleRegisterOptions(c: AuthContext) {
  const body = await readJsonBody(c);
  const name = cleanName(body.name);
  if (name === null) {
    return c.json({ error: `name must be 1 to ${MAX_NAME_LENGTH} characters` }, 400);
  }

  // The user id is chosen now because the passkey stores it as its user handle.
  const userId = randomId();
  const options = await generateRegistrationOptions({
    rpName: RELYING_PARTY_NAME,
    rpID: RELYING_PARTY_ID,
    userID: isoBase64URL.toBuffer(userId),
    userName: name,
    userDisplayName: name,
    attestationType: "none",
    authenticatorSelection: {
      residentKey: "required",
      userVerification: "required",
    },
  });

  const challengeId = await storeChallenge(c.env.DB, options.challenge, "register", userId, name);
  return c.json({ challengeId, options });
}

async function handleRegisterVerify(c: AuthContext) {
  const body = await readJsonBody(c);
  const challengeRow = await takeChallenge(c.env.DB, body.challengeId, "register");
  if (challengeRow === null || challengeRow.user_id === null || challengeRow.user_name === null) {
    return c.json({ error: "unknown or expired challenge" }, 400);
  }

  let verification;
  try {
    verification = await verifyRegistrationResponse({
      response: body.credential as RegistrationResponseJSON,
      expectedChallenge: challengeRow.challenge,
      expectedOrigin: EXPECTED_ORIGIN,
      expectedRPID: RELYING_PARTY_ID,
      requireUserVerification: true,
    });
  } catch {
    return c.json({ error: "passkey could not be verified" }, 400);
  }
  if (!verification.verified) {
    return c.json({ error: "passkey could not be verified" }, 400);
  }

  const credential = verification.registrationInfo.credential;
  const publicKey = isoBase64URL.fromBuffer(credential.publicKey);
  const transports = credential.transports ? JSON.stringify(credential.transports) : null;
  const userId = challengeRow.user_id;
  const userName = challengeRow.user_name;
  const nowIso = new Date().toISOString();
  const token = newSessionToken();
  const tokenHash = await hashToken(token);

  const insertUser = boundStatement(c.env.DB, "INSERT INTO users (id, name, created_at) VALUES (?, ?, ?)", userId, userName, nowIso);
  const insertPasskey = boundStatement(c.env.DB, "INSERT INTO passkeys (credential_id, user_id, public_key, counter, transports, created_at) VALUES (?, ?, ?, ?, ?, ?)", credential.id, userId, publicKey, credential.counter, transports, nowIso);
  const insertSession = sessionInsert(c.env.DB, tokenHash, userId, nowIso);
  // One batch is one transaction: a user never exists without its passkey.
  await c.env.DB.batch([insertUser, insertPasskey, insertSession]);

  return c.json({ token, user: { id: userId, name: userName } });
}

async function handleLoginOptions(c: AuthContext) {
  // No allowCredentials: the phone offers whichever Midas passkey it holds.
  const options = await generateAuthenticationOptions({
    rpID: RELYING_PARTY_ID,
    userVerification: "required",
  });
  const challengeId = await storeChallenge(c.env.DB, options.challenge, "login", null, null);
  return c.json({ challengeId, options });
}

async function handleLoginVerify(c: AuthContext) {
  const body = await readJsonBody(c);
  const challengeRow = await takeChallenge(c.env.DB, body.challengeId, "login");
  if (challengeRow === null) {
    return c.json({ error: "unknown or expired challenge" }, 400);
  }

  const response = body.credential as AuthenticationResponseJSON | undefined;
  const credentialId = typeof response?.id === "string" ? response.id : "";
  const passkeyStatement = boundStatement(c.env.DB, "SELECT credential_id, user_id, public_key, counter, transports FROM passkeys WHERE credential_id = ?", credentialId);
  const passkey = await passkeyStatement.first<PasskeyRow>();
  if (passkey === null) {
    return c.json({ error: "unknown passkey" }, 401);
  }

  const storedTransports = passkey.transports
    ? (JSON.parse(passkey.transports) as AuthenticatorTransport[])
    : undefined;
  let verification;
  try {
    verification = await verifyAuthenticationResponse({
      response: response as AuthenticationResponseJSON,
      expectedChallenge: challengeRow.challenge,
      expectedOrigin: EXPECTED_ORIGIN,
      expectedRPID: RELYING_PARTY_ID,
      requireUserVerification: true,
      credential: {
        id: passkey.credential_id,
        publicKey: isoBase64URL.toBuffer(passkey.public_key),
        counter: passkey.counter,
        transports: storedTransports,
      },
    });
  } catch {
    return c.json({ error: "passkey could not be verified" }, 401);
  }
  if (!verification.verified) {
    return c.json({ error: "passkey could not be verified" }, 401);
  }

  const userStatement = boundStatement(c.env.DB, "SELECT id, name FROM users WHERE id = ?", passkey.user_id);
  const user = await userStatement.first<UserRow>();
  if (user === null) {
    return c.json({ error: "unknown passkey" }, 401);
  }

  const nowIso = new Date().toISOString();
  const token = newSessionToken();
  const tokenHash = await hashToken(token);
  const updateCounter = boundStatement(c.env.DB, "UPDATE passkeys SET counter = ? WHERE credential_id = ?", verification.authenticationInfo.newCounter, passkey.credential_id);
  const insertSession = sessionInsert(c.env.DB, tokenHash, user.id, nowIso);
  await c.env.DB.batch([updateCounter, insertSession]);

  return c.json({ token, user: { id: user.id, name: user.name } });
}

// Rejects any request without a live session; on success the user id is in c.get("userId").
export async function requireSession(c: AuthContext, next: Next) {
  const authorization = c.req.header("Authorization") ?? "";
  const bearerPrefix = "Bearer ";
  if (!authorization.startsWith(bearerPrefix)) {
    return c.json({ error: "sign in required" }, 401);
  }
  const token = authorization.slice(bearerPrefix.length);
  const tokenHash = await hashToken(token);
  const sessionStatement = boundStatement(c.env.DB, "SELECT user_id FROM sessions WHERE token_hash = ? AND expires_at > ?", tokenHash, Date.now());
  const session = await sessionStatement.first<{ user_id: string }>();
  if (session === null) {
    return c.json({ error: "sign in required" }, 401);
  }
  c.set("userId", session.user_id);
  await next();
}

async function handleMe(c: AuthContext) {
  const userStatement = boundStatement(c.env.DB, "SELECT id, name FROM users WHERE id = ?", c.get("userId"));
  const user = await userStatement.first<UserRow>();
  if (user === null) {
    return c.json({ error: "sign in required" }, 401);
  }
  return c.json({ user: { id: user.id, name: user.name } });
}

// Served at /.well-known/apple-app-site-association so iOS lets the shell use passkeys for
// RELYING_PARTY_ID. Must be JSON with no redirect.
export function handleAppleAppSiteAssociation(c: Context) {
  return c.json({ webcredentials: { apps: [APPLE_APP_ID] } });
}

export const authRoutes = new Hono<AuthEnv>();
authRoutes.post("/register/options", handleRegisterOptions);
authRoutes.post("/register/verify", handleRegisterVerify);
authRoutes.post("/login/options", handleLoginOptions);
authRoutes.post("/login/verify", handleLoginVerify);
authRoutes.get("/me", requireSession, handleMe);
