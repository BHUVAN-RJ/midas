import { describe, expect, it } from "vitest";
import app from "../src/index";

// Minimal stand-ins for the R2 and D1 bindings: only the calls the routes make.
function makeFakeBucket(objectsByKey: Record<string, string>) {
  async function getObject(key: string) {
    if (!(key in objectsByKey)) {
      return null;
    }
    const objectText = objectsByKey[key];
    return {
      body: new Response(objectText).body,
      json: async () => JSON.parse(objectText),
    };
  }
  async function listObjects() {
    return { objects: [] };
  }
  return { get: getObject, list: listObjects };
}

function makeFakeDatabase() {
  function prepareStatement() {
    return { first: async () => ({ 1: 1 }) };
  }
  return { prepare: prepareStatement };
}

const REMINDERS_HTML = "<!doctype html><title>Reminders</title><script>document.title='ok'</script>";

function makeEnv() {
  const bucket = makeFakeBucket({
    "sidekicks/reminders/current.json": JSON.stringify({
      version: "v1",
      scriptHashes: ["sha256-AAA=", "sha256-BBB="],
    }),
    "sidekicks/reminders/v1/index.html": REMINDERS_HTML,
    "sidekicks/broken/current.json": JSON.stringify({ version: "v9", scriptHashes: [] }),
  });
  return { BUNDLES: bucket, DB: makeFakeDatabase() };
}

describe("GET /sidekicks/:id/bundle", () => {
  it("serves the current version's html with its script hashes", async () => {
    const response = await app.request("/sidekicks/reminders/bundle", {}, makeEnv());
    expect(response.status).toBe(200);
    expect(response.headers.get("Content-Type")).toBe("text/html; charset=utf-8");
    expect(response.headers.get("X-Midas-Bundle-Version")).toBe("v1");
    expect(response.headers.get("X-Midas-Script-Hashes")).toBe("sha256-AAA= sha256-BBB=");
    expect(await response.text()).toBe(REMINDERS_HTML);
  });

  it("returns 404 for a sidekick that was never deployed", async () => {
    const response = await app.request("/sidekicks/nope/bundle", {}, makeEnv());
    expect(response.status).toBe(404);
  });

  it("rejects ids that could escape the sidekick prefix", async () => {
    const response = await app.request("/sidekicks/..%2Fsecrets/bundle", {}, makeEnv());
    expect(response.status).toBe(400);
  });

  it("returns 500 when the pointer names a version that is not stored", async () => {
    const response = await app.request("/sidekicks/broken/bundle", {}, makeEnv());
    expect(response.status).toBe(500);
  });
});

describe("CORS", () => {
  it("allows a sidekick:// origin", async () => {
    const requestInit = { headers: { Origin: "sidekick://reminders" } };
    const response = await app.request("/health", requestInit, makeEnv());
    expect(response.status).toBe(200);
    expect(response.headers.get("Access-Control-Allow-Origin")).toBe("sidekick://reminders");
  });

  it("gives no CORS header to any other origin", async () => {
    const requestInit = { headers: { Origin: "https://evil.example" } };
    const response = await app.request("/health", requestInit, makeEnv());
    expect(response.headers.get("Access-Control-Allow-Origin")).toBeNull();
  });

  it("answers a preflight from a sidekick origin and refuses others", async () => {
    const sidekickPreflight = { method: "OPTIONS", headers: { Origin: "sidekick://calendar" } };
    const allowed = await app.request("/health", sidekickPreflight, makeEnv());
    expect(allowed.status).toBe(204);
    expect(allowed.headers.get("Access-Control-Allow-Origin")).toBe("sidekick://calendar");

    const otherPreflight = { method: "OPTIONS", headers: { Origin: "https://evil.example" } };
    const refused = await app.request("/health", otherPreflight, makeEnv());
    expect(refused.status).toBe(403);
  });
});

describe("GET /health", () => {
  it("still reports both bindings", async () => {
    const response = await app.request("/health", {}, makeEnv());
    const body = (await response.json()) as { ok: boolean; d1: string; r2: string };
    expect(response.status).toBe(200);
    expect(body.ok).toBe(true);
    expect(body.d1).toBe("ok");
    expect(body.r2).toBe("ok");
  });
});
