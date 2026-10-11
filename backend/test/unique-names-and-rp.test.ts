import { describe, expect, it } from "vitest";
import app from "../src/index";
import { EXPECTED_ORIGIN, RELYING_PARTY_ID } from "../src/auth";
import { makeMigratedD1 } from "./helpers/migrated-d1";
import { makeSoftAuthenticator } from "./helpers/soft-authenticator";

// Two people cannot have the same name (2026-10-10), and the staging Worker binds passkeys to
// its own domain through RP_ID.

type OptionsReply = { challengeId: string; options: { challenge: string; rp?: { id: string }; rpId?: string } };

const STAGING_RP_ID = "midas-api-staging.midas-backend.workers.dev";

function makeEnv(rpId?: string) {
  return { DB: makeMigratedD1(), BUNDLES: {}, RP_ID: rpId };
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

async function registrationOptions(env: TestEnv, name: string): Promise<OptionsReply> {
  const response = await postJson(env, "/auth/register/options", { name });
  return (await response.json()) as OptionsReply;
}

async function completeRegistration(env: TestEnv, optionsReply: OptionsReply, rpId: string) {
  const authenticator = await makeSoftAuthenticator({ rpId, origin: `https://${rpId}` });
  const credential = await authenticator.register(optionsReply.options as never);
  return postJson(env, "/auth/register/verify", { challengeId: optionsReply.challengeId, credential });
}

describe("unique names", () => {
  it("refuses a name that is already taken, in any case, before a passkey is made", async () => {
    const env = makeEnv();
    const firstOptions = await registrationOptions(env, "Priya");
    const firstVerify = await completeRegistration(env, firstOptions, RELYING_PARTY_ID);
    expect(firstVerify.status).toBe(200);

    const sameName = await postJson(env, "/auth/register/options", { name: "Priya" });
    const otherCase = await postJson(env, "/auth/register/options", { name: "  pRIYA " });
    expect(sameName.status).toBe(409);
    expect(otherCase.status).toBe(409);
    expect(await otherCase.json()).toEqual({ error: "that name is taken" });

    const differentName = await postJson(env, "/auth/register/options", { name: "Sam" });
    expect(differentName.status).toBe(200);
  });

  it("refuses the second of two sign-ups that raced past the name check", async () => {
    const env = makeEnv();
    const firstOptions = await registrationOptions(env, "Alex");
    const secondOptions = await registrationOptions(env, "alex");

    const firstVerify = await completeRegistration(env, firstOptions, RELYING_PARTY_ID);
    const secondVerify = await completeRegistration(env, secondOptions, RELYING_PARTY_ID);
    expect(firstVerify.status).toBe(200);
    expect(secondVerify.status).toBe(409);

    // The losing sign-up left no half-made account behind.
    expect(env.DB.query("SELECT name FROM users")).toEqual([{ name: "Alex" }]);
    expect(env.DB.query("SELECT credential_id FROM passkeys")).toHaveLength(1);
    expect(env.DB.query("SELECT token_hash FROM sessions")).toHaveLength(1);
  });

  it("is enforced by the database itself, not only by the route", () => {
    const db = makeMigratedD1();
    db.execute("INSERT INTO users (id, name, created_at) VALUES ('u1', 'Noor', 'now')");
    function insertSameNameOtherCase() {
      db.execute("INSERT INTO users (id, name, created_at) VALUES ('u2', 'NOOR', 'now')");
    }
    expect(insertSameNameOtherCase).toThrow(/UNIQUE/);
  });
});

describe("RP_ID", () => {
  it("defaults to the live domain when the Worker sets none", async () => {
    const env = makeEnv();
    const optionsReply = await registrationOptions(env, "Live User");
    expect(optionsReply.options.rp?.id).toBe(RELYING_PARTY_ID);
    expect(EXPECTED_ORIGIN).toBe(`https://${RELYING_PARTY_ID}`);
  });

  it("binds passkeys to the staging domain on the staging Worker", async () => {
    const env = makeEnv(STAGING_RP_ID);
    const optionsReply = await registrationOptions(env, "Staging User");
    expect(optionsReply.options.rp?.id).toBe(STAGING_RP_ID);

    const verifyResponse = await completeRegistration(env, optionsReply, STAGING_RP_ID);
    expect(verifyResponse.status).toBe(200);
  });

  it("rejects on staging a passkey made for the live domain", async () => {
    const env = makeEnv(STAGING_RP_ID);
    const optionsReply = await registrationOptions(env, "Wrong Domain");
    const verifyResponse = await completeRegistration(env, optionsReply, RELYING_PARTY_ID);
    expect(verifyResponse.status).toBe(400);
    expect(env.DB.query("SELECT id FROM users")).toHaveLength(0);
  });
});
