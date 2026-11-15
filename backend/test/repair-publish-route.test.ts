import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import app from "../src/index";
import { MAX_WAIT_SECONDS, bundleContentHash, waitSecondsFrom } from "../src/repair-publish";
import { bundleContentHash as scriptContentHash, inlineScriptHashes } from "../scripts/bundle-tools.mjs";
import { makeFakeR2 } from "./helpers/fake-r2";
import { makeMigratedD1 } from "./helpers/migrated-d1";

// Publish first (founder, 2026-11-13; docs/briefs/repair-lanes.md W7): the runner uploads a new
// version through the Worker while the fast checks run, flips the person's pointer when they
// pass, and rolls it back when a slow check fails after publishing. Plus the long poll that
// replaces the runner's 30 s poll.

const RUNNER_TOKEN = "runner-secret-for-publish-tests";
const USER_ID = "amogh";
const SIDEKICK_ID = "todo";
const OLD_VERSION = "20261101T000000000Z-aaaaaaaa";
const NEW_VERSION = "20261113T120000000Z-bbbbbbbb";
const LATER_VERSION = "20261113T130000000Z-cccccccc";
const OWN_PREFIX = `sidekicks/${SIDEKICK_ID}/users/${USER_ID}`;
const HTML = "<!doctype html><title>To-Do ✓</title><script>document.title = 'déjà';</script>";
const MANIFEST = JSON.stringify({ id: SIDEKICK_ID, name: "To-Do", note: "café ☕" });
const TOOLS = "const tools = { verbs: ['add'] }; // ✓";

function makeEnv() {
  const oldPointer = { version: OLD_VERSION, scriptHashes: [], contentHash: "0".repeat(64), baseVersion: "20261020T000000000Z-dddddddd", tools: "tools.js" };
  const basePointer = { version: "20261110T000000000Z-eeeeeeee", scriptHashes: [] };
  return {
    DB: makeMigratedD1(),
    BUNDLES: makeFakeR2({
      [`${OWN_PREFIX}/current.json`]: JSON.stringify(oldPointer),
      [`sidekicks/${SIDEKICK_ID}/current.json`]: JSON.stringify(basePointer),
    }),
    REPAIR_RUNNER_TOKEN: RUNNER_TOKEN,
  };
}

type TestEnv = ReturnType<typeof makeEnv>;

function sha256Hex(text: string): string {
  return createHash("sha256").update(text).digest("hex");
}

function addSignedInUser(env: TestEnv, userId: string): string {
  const token = `token-${userId}`;
  const farFuture = Date.now() + 60 * 60 * 1000;
  env.DB.execute("INSERT INTO users (id, name, created_at) VALUES (?, ?, 'now')", userId, userId);
  env.DB.execute("INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, 'now', ?)", sha256Hex(token), userId, farFuture);
  env.DB.execute("INSERT INTO assignments (user_id, sidekick_id, assigned_at) VALUES (?, ?, 'now')", userId, SIDEKICK_ID);
  return token;
}

function runnerHeaders(): Record<string, string> {
  return { Authorization: `Runner ${RUNNER_TOKEN}`, "Content-Type": "application/json" };
}

async function createReport(env: TestEnv, token: string): Promise<string> {
  const form = new FormData();
  form.set("sidekickId", SIDEKICK_ID);
  form.set("kind", "change");
  form.set("transcript", "make the add button bigger");
  form.set("bundleVersion", OLD_VERSION);
  const response = await app.request("/repairs", { method: "POST", headers: { Authorization: `Bearer ${token}` }, body: form }, env);
  expect(response.status).toBe(201);
  const reply = (await response.json()) as { id: string };
  return reply.id;
}

async function claimedReport(env: TestEnv): Promise<string> {
  const token = addSignedInUser(env, USER_ID);
  const reportId = await createReport(env, token);
  const claim = await app.request("/repairs/jobs/claim", { method: "POST", headers: runnerHeaders(), body: "{}" }, env);
  expect(claim.status).toBe(200);
  return reportId;
}

async function postJson(env: TestEnv, path: string, body: unknown, headers: Record<string, string> = runnerHeaders()) {
  return app.request(path, { method: "POST", headers, body: JSON.stringify(body) }, env);
}

function versionFiles() {
  return [
    { name: "index.html", body: HTML },
    { name: "manifest.json", body: MANIFEST },
    { name: "tools.js", body: TOOLS },
    { name: "tests/todo-logic.test.ts", body: "it('adds', () => {});" },
    { name: "tests/index.json", body: JSON.stringify({ files: ["todo-logic.test.ts"] }) },
  ];
}

function newPointer() {
  return { scriptHashes: inlineScriptHashes(HTML), contentHash: scriptContentHash(HTML, MANIFEST, TOOLS), tools: "tools.js" };
}

async function readPointer(env: TestEnv): Promise<Record<string, unknown> | null> {
  const stored = await env.BUNDLES.get(`${OWN_PREFIX}/current.json`);
  return stored === null ? null : ((await stored.json()) as Record<string, unknown>);
}

async function uploadAndFlip(env: TestEnv, reportId: string, version = NEW_VERSION) {
  const upload = await postJson(env, `/repairs/${reportId}/publish/files`, { version, files: versionFiles() });
  expect(upload.status).toBe(200);
  const flip = await postJson(env, `/repairs/${reportId}/publish/pointer`, { version, pointer: newPointer() });
  expect(flip.status).toBe(200);
  return (await flip.json()) as { version: string; previousVersion: string | null };
}

describe("content hash", () => {
  it("matches bundle-tools.mjs bundleContentHash on a real Sidekick copy, with and without tools.js", async () => {
    const folder = new URL("../../sidekicks/todo/", import.meta.url);
    const html = readFileSync(new URL("index.html", folder), "utf8");
    const manifestText = readFileSync(new URL("manifest.json", folder), "utf8");
    const toolsText = readFileSync(new URL("tools.js", folder), "utf8");
    expect(await bundleContentHash(html, manifestText, toolsText)).toBe(scriptContentHash(html, manifestText, toolsText));
    expect(await bundleContentHash(HTML, MANIFEST, null)).toBe(scriptContentHash(HTML, MANIFEST, null));
    expect(await bundleContentHash(HTML, MANIFEST, null)).not.toBe(scriptContentHash(HTML, MANIFEST, TOOLS));
  });
});

describe("POST /repairs/:id/publish/files", () => {
  it("stores the version's files beside the copy while the person keeps the old version", async () => {
    const env = makeEnv();
    const reportId = await claimedReport(env);
    const response = await postJson(env, `/repairs/${reportId}/publish/files`, { version: NEW_VERSION, files: versionFiles() });
    expect(response.status).toBe(200);
    const stored = await env.BUNDLES.get(`${OWN_PREFIX}/${NEW_VERSION}/index.html`);
    expect(await stored?.text()).toBe(HTML);
    expect(stored?.httpMetadata.contentType).toBe("text/html; charset=utf-8");
    const tests = await env.BUNDLES.get(`${OWN_PREFIX}/${NEW_VERSION}/tests/todo-logic.test.ts`);
    expect(tests?.httpMetadata.contentType).toBe("text/plain; charset=utf-8");
    expect((await readPointer(env))?.version).toBe(OLD_VERSION);
  });

  it("refuses names outside the version's files, a user session, and a report not claimed", async () => {
    const env = makeEnv();
    const reportId = await claimedReport(env);
    for (const badName of ["../current.json", "current.json", "version.json", "tests/../x", "other.js", "tests/"]) {
      const response = await postJson(env, `/repairs/${reportId}/publish/files`, { version: NEW_VERSION, files: [{ name: badName, body: "x" }] });
      expect(response.status, badName).toBe(400);
    }
    const badVersion = await postJson(env, `/repairs/${reportId}/publish/files`, { version: "../../x", files: versionFiles() });
    expect(badVersion.status).toBe(400);
    const asUser = await postJson(env, `/repairs/${reportId}/publish/files`, { version: NEW_VERSION, files: versionFiles() }, { Authorization: `Bearer token-${USER_ID}` });
    expect(asUser.status).toBe(401);
    env.DB.execute("UPDATE repair_reports SET status = 'queued' WHERE id = ?", reportId);
    const notClaimed = await postJson(env, `/repairs/${reportId}/publish/files`, { version: NEW_VERSION, files: versionFiles() });
    expect(notClaimed.status).toBe(409);
    const keys = env.BUNDLES.keys().filter(function isVersionKey(key: string) {
      return key.includes(NEW_VERSION);
    });
    expect(keys).toEqual([]);
  });

  it("never rewrites a version that was published", async () => {
    const env = makeEnv();
    const reportId = await claimedReport(env);
    await uploadAndFlip(env, reportId);
    const again = await postJson(env, `/repairs/${reportId}/publish/files`, { version: NEW_VERSION, files: [{ name: "index.html", body: "<p>other</p>" }] });
    expect(again.status).toBe(409);
    const stored = await env.BUNDLES.get(`${OWN_PREFIX}/${NEW_VERSION}/index.html`);
    expect(await stored?.text()).toBe(HTML);
  });
});

describe("POST /repairs/:id/publish/pointer", () => {
  it("flips the person's pointer to the checked files and keeps the pointer it replaced", async () => {
    const env = makeEnv();
    const reportId = await claimedReport(env);
    const flipped = await uploadAndFlip(env, reportId);
    expect(flipped).toEqual({ version: NEW_VERSION, previousVersion: OLD_VERSION });
    const pointer = await readPointer(env);
    expect(pointer).toEqual({ ...newPointer(), version: NEW_VERSION, baseVersion: "20261020T000000000Z-dddddddd" });
    const record = (await (await env.BUNDLES.get(`${OWN_PREFIX}/${NEW_VERSION}/version.json`))?.json()) as Record<string, any>;
    expect(record.reportId).toBe(reportId);
    expect(record.forUser).toBe(USER_ID);
    expect(record.previousPointer.version).toBe(OLD_VERSION);
    expect(record.testFiles).toEqual(["todo-logic.test.ts"]);
  });

  it("refuses files that do not hash to the pointer's contentHash, and leaves the person where they were", async () => {
    const env = makeEnv();
    const reportId = await claimedReport(env);
    const tampered = versionFiles();
    tampered[0] = { name: "index.html", body: `${HTML}<p>not what was checked</p>` };
    const upload = await postJson(env, `/repairs/${reportId}/publish/files`, { version: NEW_VERSION, files: tampered });
    expect(upload.status).toBe(200);
    const flip = await postJson(env, `/repairs/${reportId}/publish/pointer`, { version: NEW_VERSION, pointer: newPointer() });
    expect(flip.status).toBe(409);
    expect((await readPointer(env))?.version).toBe(OLD_VERSION);
  });

  it("refuses a version whose upload is missing a file", async () => {
    const env = makeEnv();
    const reportId = await claimedReport(env);
    const withoutTools = versionFiles().filter(function isNotTools(file) {
      return file.name !== "tools.js";
    });
    await postJson(env, `/repairs/${reportId}/publish/files`, { version: NEW_VERSION, files: withoutTools });
    const flip = await postJson(env, `/repairs/${reportId}/publish/pointer`, { version: NEW_VERSION, pointer: newPointer() });
    expect(flip.status).toBe(409);
    expect((await readPointer(env))?.version).toBe(OLD_VERSION);
  });
});

describe("POST /repairs/:id/publish/rollback", () => {
  it("puts the person back on the version they had", async () => {
    const env = makeEnv();
    const reportId = await claimedReport(env);
    await uploadAndFlip(env, reportId);
    const response = await postJson(env, `/repairs/${reportId}/publish/rollback`, { version: NEW_VERSION, reason: "view after a tap on add draws nothing" });
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ rolledBack: true, version: OLD_VERSION });
    expect((await readPointer(env))?.version).toBe(OLD_VERSION);
    const marker = await env.BUNDLES.get(`${OWN_PREFIX}/${NEW_VERSION}/rolled-back.json`);
    expect(((await marker?.json()) as Record<string, unknown>).reason).toBe("view after a tap on add draws nothing");
  });

  it("removes the pointer when the person had no copy of their own, so they get the base again", async () => {
    const env = makeEnv();
    await env.BUNDLES.delete(`${OWN_PREFIX}/current.json`);
    const reportId = await claimedReport(env);
    await uploadAndFlip(env, reportId);
    const response = await postJson(env, `/repairs/${reportId}/publish/rollback`, { version: NEW_VERSION, reason: "widget" });
    expect(response.status).toBe(200);
    expect(await readPointer(env)).toBeNull();
  });

  it("never undoes a later version, nor a version this report did not publish", async () => {
    const env = makeEnv();
    const reportId = await claimedReport(env);
    await uploadAndFlip(env, reportId);
    // A later publish moved the person on (same report used here for brevity)
    const laterFiles = versionFiles();
    await postJson(env, `/repairs/${reportId}/publish/files`, { version: LATER_VERSION, files: laterFiles });
    await postJson(env, `/repairs/${reportId}/publish/pointer`, { version: LATER_VERSION, pointer: newPointer() });
    const stale = await postJson(env, `/repairs/${reportId}/publish/rollback`, { version: NEW_VERSION, reason: "late" });
    expect(stale.status).toBe(409);
    expect((await readPointer(env))?.version).toBe(LATER_VERSION);
    const neverPublished = await postJson(env, `/repairs/${reportId}/publish/rollback`, { version: OLD_VERSION, reason: "x" });
    expect(neverPublished.status).toBe(409);
    expect((await readPointer(env))?.version).toBe(LATER_VERSION);
  });

  it("lets a live repair become failed only with rolledBack, and tells the founder and the person", async () => {
    const env = makeEnv();
    const reportId = await claimedReport(env);
    await uploadAndFlip(env, reportId);
    await postJson(env, `/repairs/${reportId}/status`, { status: "fix_ready" });
    const live = await postJson(env, `/repairs/${reportId}/status`, { status: "deployed_live", summary: "Bigger add button." });
    expect(live.status).toBe(200);
    const withoutFlag = await postJson(env, `/repairs/${reportId}/status`, { status: "failed", reason: "shield" });
    expect(withoutFlag.status).toBe(409);
    await postJson(env, `/repairs/${reportId}/publish/rollback`, { version: NEW_VERSION, reason: "shield" });
    const failed = await postJson(env, `/repairs/${reportId}/status`, { status: "failed", reason: "rolled back: shield widget-record", rolledBack: true });
    expect(failed.status).toBe(200);
    const rows = env.DB.query("SELECT status, fail_reason, result_kind FROM repair_reports WHERE id = ?", reportId);
    expect(rows[0]).toMatchObject({ status: "failed", fail_reason: "rolled back: shield widget-record", result_kind: "couldnt_fix" });
    const events = env.DB.query("SELECT audience, kind FROM repair_events WHERE report_id = ? AND kind = 'failed' ORDER BY audience", reportId);
    expect(events).toEqual([{ audience: "founder", kind: "failed" }, { audience: "user", kind: "failed" }]);
  });
});

describe("GET /repairs/jobs/wait", () => {
  it("answers ready at once when a job waits, and not ready after the wait when none does", async () => {
    const env = makeEnv();
    const empty = await app.request("/repairs/jobs/wait?seconds=0", { headers: runnerHeaders() }, env);
    expect(await empty.json()).toEqual({ ready: false });
    const token = addSignedInUser(env, USER_ID);
    await createReport(env, token);
    const startedAt = Date.now();
    const waiting = await app.request("/repairs/jobs/wait?seconds=5", { headers: runnerHeaders() }, env);
    expect(await waiting.json()).toEqual({ ready: true });
    expect(Date.now() - startedAt).toBeLessThan(500);
  });

  it("answers as soon as a report arrives during the wait", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, USER_ID);
    const startedAt = Date.now();
    const waitPromise = app.request("/repairs/jobs/wait?seconds=4", { headers: runnerHeaders() }, env);
    setTimeout(function sendReportLater() {
      void createReport(env, token);
    }, 300);
    const reply = await waitPromise;
    expect(await reply.json()).toEqual({ ready: true });
    expect(Date.now() - startedAt).toBeLessThan(2500);
  });

  it("takes the runner token only, and caps the wait", async () => {
    const env = makeEnv();
    addSignedInUser(env, USER_ID);
    const asUser = await app.request("/repairs/jobs/wait?seconds=0", { headers: { Authorization: `Bearer token-${USER_ID}` } }, env);
    expect(asUser.status).toBe(401);
    expect(waitSecondsFrom("600")).toBe(MAX_WAIT_SECONDS);
    expect(waitSecondsFrom("3")).toBe(3);
    expect(waitSecondsFrom(undefined)).toBe(MAX_WAIT_SECONDS);
  });
});
