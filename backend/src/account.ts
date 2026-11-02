import { Hono } from "hono";
import type { Context } from "hono";
import { hashToken, requireSession } from "./auth";
import { isDeliveredAlert } from "./account-deletion";
import { makeFounderUserId } from "./make-sidekick";
import { pushFetchFromEnv, runAfterResponse, sendToUserDevices } from "./push";
import type { PushBindings } from "./push";

// Settings (founder, 2026-10-31; docs/briefs/build-22-2026-10-31.md, "Settings and delete").
// POST /account/sign-out        ends this phone's session; the next request with it is a 401.
// POST /account/delete-request  records that the person wants their account deleted, ends every
//                               session of theirs and pushes the founder. Nothing is deleted
//                               here: the founder carries out the deletion within 7 days (only
//                               the founder deletes data). 201 the first time, 200 after.
//                               Asked again while the founder's alert has not reached a phone,
//                               the alert is sent again (founder, 2026-11-02: never miss one).
// The deletion itself: account-deletion.ts, run by the founder.

type AccountBindings = PushBindings & {
  MAKE_FOUNDER_USER_ID?: string;
};

type AccountVariables = {
  userId: string;
};

type AccountEnv = { Bindings: AccountBindings; Variables: AccountVariables };
type AccountContext = Context<AccountEnv>;

// The founder's push when someone asks (founder-facing words).
export const ACCOUNT_DELETION_PUSH_TITLE = "Delete Account";

export function accountDeletionPushBody(userName: string): string {
  return `${userName} asked to delete their account.`;
}

function boundStatement(db: D1Database, sql: string, ...params: unknown[]): D1PreparedStatement {
  const prepared = db.prepare(sql);
  return prepared.bind(...params);
}

function bearerToken(c: AccountContext): string {
  const authorization = c.req.header("Authorization") ?? "";
  return authorization.slice("Bearer ".length);
}

async function handleSignOut(c: AccountContext) {
  const tokenHash = await hashToken(bearerToken(c));
  // Expired, not removed: the Worker never deletes a session row
  const expireSession = boundStatement(c.env.DB, "UPDATE sessions SET expires_at = ? WHERE token_hash = ?", Date.now(), tokenHash);
  await expireSession.run();
  return c.json({ signedOut: true });
}

function accountDeletionPayload(userId: string, userName: string): Record<string, unknown> {
  return {
    aps: {
      alert: { title: ACCOUNT_DELETION_PUSH_TITLE, body: accountDeletionPushBody(userName) },
      sound: "default",
    },
    founderAlert: { kind: "account-deletion", userId },
  };
}

// Pushes the founder and stores the outcome on the request row. A failure is logged, never thrown:
// the request is already recorded.
export async function alertFounder(env: AccountBindings, userId: string, userName: string): Promise<void> {
  const founderId = makeFounderUserId(env);
  let result = "no founder set";
  try {
    if (founderId !== null) {
      const payload = accountDeletionPayload(userId, userName);
      result = await sendToUserDevices(env.DB, env, founderId, payload, pushFetchFromEnv(env), Date.now());
    }
  } catch (error) {
    result = error instanceof Error ? error.message : String(error);
    console.error(`account deletion alert for ${userId} failed: ${result}`);
  }
  try {
    const storeResult = boundStatement(env.DB, "UPDATE account_deletion_requests SET alert_result = ? WHERE user_id = ?", result, userId);
    await storeResult.run();
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`account deletion alert result for ${userId} not stored: ${message}`);
  }
}

async function storedAlertResult(db: D1Database, userId: string): Promise<string | null> {
  const statement = boundStatement(db, "SELECT alert_result FROM account_deletion_requests WHERE user_id = ?", userId);
  const row = await statement.first<{ alert_result: string | null }>();
  return row?.alert_result ?? null;
}

async function handleDeleteRequest(c: AccountContext) {
  const userId = c.get("userId");
  const userStatement = boundStatement(c.env.DB, "SELECT name FROM users WHERE id = ?", userId);
  const user = await userStatement.first<{ name: string }>();
  if (user === null) {
    return c.json({ error: "sign in required" }, 401);
  }
  const nowIso = new Date().toISOString();
  const insertRequest = boundStatement(
    c.env.DB,
    "INSERT INTO account_deletion_requests (user_id, user_name, requested_at) VALUES (?, ?, ?) ON CONFLICT(user_id) DO NOTHING",
    userId,
    user.name,
    nowIso,
  );
  // Every phone of theirs is signed out with it
  const expireSessions = boundStatement(c.env.DB, "UPDATE sessions SET expires_at = ? WHERE user_id = ?", Date.now(), userId);
  const results = await c.env.DB.batch([insertRequest, expireSessions]);
  const isNewRequest = (results[0]?.meta?.changes ?? 0) > 0;
  // A repeat sends the alert again only when the first one reached no phone of the founder's
  const needsAlert = isNewRequest || !isDeliveredAlert(await storedAlertResult(c.env.DB, userId));
  if (needsAlert) {
    const alerting = alertFounder(c.env, userId, user.name);
    await runAfterResponse(c, alerting);
  }
  return c.json({ requested: true }, isNewRequest ? 201 : 200);
}

export const accountRoutes = new Hono<AccountEnv>();
accountRoutes.use("*", requireSession);
accountRoutes.post("/sign-out", handleSignOut);
accountRoutes.post("/delete-request", handleDeleteRequest);
