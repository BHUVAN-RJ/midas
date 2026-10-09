import { describe, expect, it } from "vitest";
import app from "../src/index";
import { APPLE_APP_ID, EXPECTED_ORIGIN, RELYING_PARTY_ID } from "../src/auth";
import { makeSqliteD1 } from "./helpers/sqlite-d1";
import { makeSoftAuthenticator, makeStrayPrivateKey, SOFT_AUTHENTICATOR_FLAGS } from "./helpers/soft-authenticator";

type OptionsReply = { challengeId: string; options: { challenge: string; user: { id: string; name: string }; rp?: { id: string }; rpId?: string } };
type SessionReply = { token: string; user: { id: string; name: string } };

function makeEnv() {
  return { DB: makeSqliteD1(), BUNDLES: {} };
}

type TestEnv = ReturnType<typeof makeEnv>;

async function postJson(env: TestEnv, path: string, body: unknown) {
  const requestInit = {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  };
  return app.request(path, requestInit, env);
}

async function requestRegisterOptions(env: TestEnv, name: string): Promise<OptionsReply> {
  const response = await postJson(env, "/auth/register/options", { name });
  return (await response.json()) as OptionsReply;
}

async function getMe(env: TestEnv, token: string | null) {
  const headers: Record<string, string> = token === null ? {} : { Authorization: `Bearer ${token}` };
  return app.request("/auth/me", { headers }, env);
}

function newAuthenticator() {
  return makeSoftAuthenticator({ rpId: RELYING_PARTY_ID, origin: EXPECTED_ORIGIN });
}

type SoftAuthenticator = Awaited<ReturnType<typeof newAuthenticator>>;

async function registerUser(env: TestEnv, authenticator: SoftAuthenticator, name: string) {
  const optionsResponse = await postJson(env, "/auth/register/options", { name });
  const optionsReply = (await optionsResponse.json()) as OptionsReply;
  const credential = await authenticator.register(optionsReply.options);
  const verifyResponse = await postJson(env, "/auth/register/verify", { challengeId: optionsReply.challengeId, credential });
  return { optionsReply, credential, verifyResponse };
}

async function signIn(env: TestEnv, authenticator: SoftAuthenticator, assertOverrides = {}) {
  const optionsResponse = await postJson(env, "/auth/login/options", {});
  const optionsReply = (await optionsResponse.json()) as OptionsReply;
  const credential = await authenticator.assert(optionsReply.options, assertOverrides);
  return postJson(env, "/auth/login/verify", { challengeId: optionsReply.challengeId, credential });
}

describe("POST /auth/register", () => {
  it("creates a user from a name and a passkey and returns a working session", async () => {
    const env = makeEnv();
    const authenticator = await newAuthenticator();
    const { optionsReply, verifyResponse } = await registerUser(env, authenticator, "  Priya  ");

    expect(optionsReply.options.rp?.id).toBe(RELYING_PARTY_ID);
    expect(optionsReply.options.user.name).toBe("Priya");
    expect(verifyResponse.status).toBe(200);
    const session = (await verifyResponse.json()) as SessionReply;
    expect(session.user.name).toBe("Priya");

    const meResponse = await getMe(env, session.token);
    expect(meResponse.status).toBe(200);
    const meBody = (await meResponse.json()) as { user: { id: string; name: string } };
    expect(meBody.user).toEqual(session.user);

    const passkeys = env.DB.query("SELECT user_id FROM passkeys");
    expect(passkeys).toEqual([{ user_id: session.user.id }]);
  });

  it("stores only a hash of the session token", async () => {
    const env = makeEnv();
    const authenticator = await newAuthenticator();
    const { verifyResponse } = await registerUser(env, authenticator, "Sam");
    const session = (await verifyResponse.json()) as SessionReply;

    const sessionRows = env.DB.query("SELECT token_hash FROM sessions");
    expect(sessionRows).toHaveLength(1);
    expect(sessionRows[0].token_hash).not.toBe(session.token);
    expect(String(sessionRows[0].token_hash)).toMatch(/^[0-9a-f]{64}$/);
  });

  it("rejects an empty or too long name", async () => {
    const env = makeEnv();
    const emptyName = await postJson(env, "/auth/register/options", { name: "   " });
    const longName = await postJson(env, "/auth/register/options", { name: "x".repeat(51) });
    const missingName = await postJson(env, "/auth/register/options", {});
    expect(emptyName.status).toBe(400);
    expect(longName.status).toBe(400);
    expect(missingName.status).toBe(400);
    expect(env.DB.query("SELECT id FROM auth_challenges")).toHaveLength(0);
  });

  it("rejects a passkey made for a different challenge and creates no user", async () => {
    const env = makeEnv();
    const authenticator = await newAuthenticator();
    const firstOptions = await requestRegisterOptions(env, "A");
    const secondOptions = await requestRegisterOptions(env, "B");
    const credentialForSecond = await authenticator.register(secondOptions.options);

    const response = await postJson(env, "/auth/register/verify", { challengeId: firstOptions.challengeId, credential: credentialForSecond });
    expect(response.status).toBe(400);
    expect(env.DB.query("SELECT id FROM users")).toHaveLength(0);
  });

  it("rejects a passkey from another origin", async () => {
    const env = makeEnv();
    const authenticator = await newAuthenticator();
    const optionsReply = await requestRegisterOptions(env, "A");
    const credential = await authenticator.register(optionsReply.options, { origin: "https://evil.example" });

    const response = await postJson(env, "/auth/register/verify", { challengeId: optionsReply.challengeId, credential });
    expect(response.status).toBe(400);
    expect(env.DB.query("SELECT id FROM users")).toHaveLength(0);
  });

  it("rejects a passkey created without user verification", async () => {
    const env = makeEnv();
    const authenticator = await newAuthenticator();
    const optionsReply = await requestRegisterOptions(env, "A");
    const presenceOnly = SOFT_AUTHENTICATOR_FLAGS.userPresent | SOFT_AUTHENTICATOR_FLAGS.attestedData;
    const credential = await authenticator.register(optionsReply.options, { flags: presenceOnly });

    const response = await postJson(env, "/auth/register/verify", { challengeId: optionsReply.challengeId, credential });
    expect(response.status).toBe(400);
  });

  it("accepts a challenge only once", async () => {
    const env = makeEnv();
    const authenticator = await newAuthenticator();
    const { optionsReply, credential, verifyResponse } = await registerUser(env, authenticator, "A");
    expect(verifyResponse.status).toBe(200);

    const replay = await postJson(env, "/auth/register/verify", { challengeId: optionsReply.challengeId, credential });
    expect(replay.status).toBe(400);
    expect(env.DB.query("SELECT id FROM users")).toHaveLength(1);
  });

  it("rejects an expired challenge", async () => {
    const env = makeEnv();
    const authenticator = await newAuthenticator();
    const optionsReply = await requestRegisterOptions(env, "A");
    env.DB.query("UPDATE auth_challenges SET expires_at = ?", Date.now() - 1);
    const credential = await authenticator.register(optionsReply.options);

    const response = await postJson(env, "/auth/register/verify", { challengeId: optionsReply.challengeId, credential });
    expect(response.status).toBe(400);
  });
});

describe("POST /auth/login", () => {
  it("signs an existing user back in with the same passkey", async () => {
    const env = makeEnv();
    const authenticator = await newAuthenticator();
    const { verifyResponse } = await registerUser(env, authenticator, "Priya");
    const registered = (await verifyResponse.json()) as SessionReply;

    const loginResponse = await signIn(env, authenticator, { signCount: 3 });
    expect(loginResponse.status).toBe(200);
    const session = (await loginResponse.json()) as SessionReply;
    expect(session.user).toEqual(registered.user);
    expect(session.token).not.toBe(registered.token);

    const meResponse = await getMe(env, session.token);
    expect(meResponse.status).toBe(200);
    expect(env.DB.query("SELECT counter FROM passkeys")).toEqual([{ counter: 3 }]);
  });

  it("offers any passkey: login options name no credentials", async () => {
    const env = makeEnv();
    const response = await postJson(env, "/auth/login/options", {});
    const reply = (await response.json()) as { options: { rpId: string; allowCredentials?: unknown[] } };
    expect(reply.options.rpId).toBe(RELYING_PARTY_ID);
    expect(reply.options.allowCredentials ?? []).toHaveLength(0);
  });

  it("rejects a passkey the server has never seen", async () => {
    const env = makeEnv();
    const strangerAuthenticator = await newAuthenticator();
    const response = await signIn(env, strangerAuthenticator);
    expect(response.status).toBe(401);
  });

  it("rejects an assertion signed by the wrong key", async () => {
    const env = makeEnv();
    const authenticator = await newAuthenticator();
    await registerUser(env, authenticator, "Priya");
    const strayKey = await makeStrayPrivateKey();

    const response = await signIn(env, authenticator, { signingKey: strayKey });
    expect(response.status).toBe(401);
    expect(env.DB.query("SELECT token_hash FROM sessions")).toHaveLength(1);
  });

  it("does not accept a registration challenge for login", async () => {
    const env = makeEnv();
    const authenticator = await newAuthenticator();
    await registerUser(env, authenticator, "Priya");
    const registerOptions = await requestRegisterOptions(env, "X");
    const credential = await authenticator.assert(registerOptions.options);

    const response = await postJson(env, "/auth/login/verify", { challengeId: registerOptions.challengeId, credential });
    expect(response.status).toBe(400);
  });
});

describe("GET /auth/me", () => {
  it("rejects a request with no session, a made-up token, or an expired session", async () => {
    const env = makeEnv();
    const authenticator = await newAuthenticator();
    const { verifyResponse } = await registerUser(env, authenticator, "Priya");
    const session = (await verifyResponse.json()) as SessionReply;

    expect((await getMe(env, null)).status).toBe(401);
    expect((await getMe(env, "not-a-real-token")).status).toBe(401);
    expect((await getMe(env, session.token)).status).toBe(200);

    env.DB.query("UPDATE sessions SET expires_at = ?", Date.now() - 1);
    expect((await getMe(env, session.token)).status).toBe(401);
  });
});

describe("GET /.well-known/apple-app-site-association", () => {
  it("lets the Midas app use passkeys for this domain", async () => {
    const response = await app.request("/.well-known/apple-app-site-association", {}, makeEnv());
    expect(response.status).toBe(200);
    expect(response.headers.get("Content-Type")).toMatch(/^application\/json/);
    const body = (await response.json()) as { webcredentials: { apps: string[] } };
    expect(body.webcredentials.apps).toEqual([APPLE_APP_ID]);
    expect(APPLE_APP_ID).toBe("YJ76245TM4.com.bhuvanrj.midas");
  });
});
