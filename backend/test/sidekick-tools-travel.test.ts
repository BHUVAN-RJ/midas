// tools.js travels with the page (jess router, founder 2026-10-21, phase 2): the deploy gate,
// the content hash, the deploy plan, the user's first-load copy, GET /sidekicks/:id/tools.js, the
// repair asset bundle.tools.js, and the runner's job folder, check sandbox, staged deploy and
// expected hash. A Sidekick without tools.js keeps every path exactly as before.
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import app from "../src/index";
import { bundleContentHash, checkBundleFiles, planDeploy } from "../scripts/bundle-tools.mjs";
import { buildJobFolder, isAllowedJobFile, presentSidekickFiles, readSidekickFiles, snapshotSidekickFiles } from "../../runner/lib/job-folder.mjs";
import { buildSandboxCheckout, gateProblems } from "../../runner/lib/check.mjs";
import { expectedContentHash, stageDeployFolder } from "../../runner/lib/deploy.mjs";
import { ASSET_NAMES } from "../../runner/lib/backend.mjs";
import { makeMigratedD1 } from "./helpers/migrated-d1";
import { addSignedInUser as addRepairUser, createReport, getAsset, makeRepairEnv, runnerHeaders } from "./helpers/repair-fixtures";

const REPO_ROOT = join(__dirname, "..", "..");

function remindersFiles() {
  const folder = join(REPO_ROOT, "sidekicks", "reminders");
  return {
    html: readFileSync(join(folder, "index.html"), "utf8"),
    manifestText: readFileSync(join(folder, "manifest.json"), "utf8"),
    toolsText: readFileSync(join(folder, "tools.js"), "utf8"),
  };
}

const PLAIN_MANIFEST = JSON.stringify({ id: "notes", name: "Notes", icon: { symbol: "note.text", background: "#FFCC00" }, reads: [] });
const PLAIN_HTML = "<!doctype html><title>Notes</title><script>document.title='n'</script>";

describe("the deploy gate, hash and plan", () => {
  it("passes the Reminders page with its tools.js and refuses it without", () => {
    const files = remindersFiles();
    expect(checkBundleFiles(files.html, files.manifestText, "reminders", files.toolsText).problems).toEqual([]);
    expect(checkBundleFiles(files.html, files.manifestText, "reminders").problems).toEqual(["manifest.json has agent tools but there is no tools.js"]);
  });

  it("refuses tools.js whose copied page code drifted, and tools.js without an agent block", () => {
    const files = remindersFiles();
    const drifted = files.html.replace("function markDoneChange(occurrenceIso, nowIso) {", "function markDoneChange(occurrenceIso, nowIso) {\n    // changed");
    expect(checkBundleFiles(drifted, files.manifestText, "reminders", files.toolsText).problems.join(" ")).toContain("no longer matches index.html");
    expect(checkBundleFiles(PLAIN_HTML, PLAIN_MANIFEST, "notes", files.toolsText).problems.join(" ")).toContain("needs an agent block");
  });

  it("keeps the old hash without tools.js and changes it with", () => {
    const files = remindersFiles();
    const withoutTools = bundleContentHash(files.html, files.manifestText);
    expect(bundleContentHash(files.html, files.manifestText, null)).toBe(withoutTools);
    const withTools = bundleContentHash(files.html, files.manifestText, files.toolsText);
    expect(withTools).not.toBe(withoutTools);
    expect(bundleContentHash(files.html, files.manifestText, files.toolsText + " ")).not.toBe(withTools);
  });

  it("puts tools.js beside the page and names it in the pointer and version record", () => {
    const files = remindersFiles();
    const plan = planDeploy({ sidekickId: "reminders", userId: "u1", html: files.html, manifestText: files.manifestText, toolsText: files.toolsText, testFiles: [], deployedAt: new Date("2026-10-21T00:00:00Z"), version: "v9" });
    const keys = plan.puts.map(function putKey(put: { key: string }) {
      return put.key;
    });
    expect(keys.slice(0, 3)).toEqual(["sidekicks/reminders/users/u1/v9/index.html", "sidekicks/reminders/users/u1/v9/manifest.json", "sidekicks/reminders/users/u1/v9/tools.js"]);
    const toolsPut = plan.puts[2];
    expect(toolsPut.body).toBe(files.toolsText);
    expect(toolsPut.contentType).toBe("text/javascript; charset=utf-8");
    const pointerPut = plan.puts[plan.puts.length - 1];
    expect(JSON.parse(pointerPut.body)).toMatchObject({ version: "v9", tools: "tools.js", contentHash: bundleContentHash(files.html, files.manifestText, files.toolsText) });
    expect(JSON.parse(plan.puts[plan.puts.length - 2].body).tools).toBe("tools.js");
  });

  it("plans a Sidekick without tools.js exactly as before", () => {
    const plan = planDeploy({ sidekickId: "notes", html: PLAIN_HTML, manifestText: PLAIN_MANIFEST, testFiles: [], deployedAt: new Date("2026-10-21T00:00:00Z"), version: "n2" });
    const keys = plan.puts.map(function putKey(put: { key: string }) {
      return put.key;
    });
    expect(keys.some(function isTools(key: string) {
      return key.endsWith("tools.js");
    })).toBe(false);
    const pointer = JSON.parse(plan.puts[plan.puts.length - 1].body);
    expect("tools" in pointer).toBe(false);
    expect(pointer.contentHash).toBe(bundleContentHash(PLAIN_HTML, PLAIN_MANIFEST));
  });
});

// A fake R2 bucket that records writes (as in sidekick-user-copies.test.ts).
function makeRecordingBucket(objectsByKey: Record<string, string>) {
  const store: Record<string, string> = { ...objectsByKey };
  const writtenKeys: string[] = [];
  async function getObject(key: string) {
    if (!(key in store)) {
      return null;
    }
    const objectText = store[key];
    return {
      body: new Response(objectText).body,
      json: async () => JSON.parse(objectText),
    };
  }
  async function putObject(key: string, body: ReadableStream | string) {
    const text = typeof body === "string" ? body : await new Response(body).text();
    store[key] = text;
    writtenKeys.push(key);
  }
  async function listObjects() {
    return { objects: [] };
  }
  return { get: getObject, put: putObject, list: listObjects, store, writtenKeys };
}

function sha256Hex(text: string): string {
  return createHash("sha256").update(text).digest("hex");
}

const TOOLS_V2 = "var MidasSidekickTools = { context: function () { return {}; }, handlers: {} };";
const TOOLS_U9 = "var MidasSidekickTools = { context: function () { return { mine: true }; }, handlers: {} };";

function makeEnv() {
  const manifest = JSON.stringify({ id: "reminders", name: "Reminders", icon: { symbol: "checklist", background: "#FF9500" }, reads: [] });
  const bucket = makeRecordingBucket({
    "sidekicks/reminders/current.json": JSON.stringify({ version: "b2", scriptHashes: [], contentHash: "hash-b2", baseVersion: null, tools: "tools.js" }),
    "sidekicks/reminders/b2/index.html": "<p>base</p>",
    "sidekicks/reminders/b2/manifest.json": manifest,
    "sidekicks/reminders/b2/tools.js": TOOLS_V2,
    "sidekicks/reminders/users/u-own/current.json": JSON.stringify({ version: "u9", scriptHashes: [], contentHash: "hash-u9", baseVersion: "b2", tools: "tools.js" }),
    "sidekicks/reminders/users/u-own/u9/index.html": "<p>own</p>",
    "sidekicks/reminders/users/u-own/u9/manifest.json": manifest,
    "sidekicks/reminders/users/u-own/u9/tools.js": TOOLS_U9,
    "sidekicks/notes/current.json": JSON.stringify({ version: "n1", scriptHashes: [], contentHash: "hash-n1", baseVersion: null }),
    "sidekicks/notes/n1/index.html": "<p>notes</p>",
    "sidekicks/notes/n1/manifest.json": JSON.stringify({ id: "notes", name: "Notes", icon: { symbol: "note.text", background: "#FFCC00" }, reads: [] }),
  });
  return { DB: makeMigratedD1(), BUNDLES: bucket };
}

type TestEnv = ReturnType<typeof makeEnv>;

function signIn(env: TestEnv, userId: string, sidekickIds: string[]): RequestInit {
  const token = `token-${userId}`;
  env.DB.execute("INSERT INTO users (id, name, created_at) VALUES (?, ?, 'now')", userId, userId);
  env.DB.execute("INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, 'now', ?)", sha256Hex(token), userId, Date.now() + 3_600_000);
  for (const sidekickId of sidekickIds) {
    env.DB.execute("INSERT INTO assignments (user_id, sidekick_id, assigned_at) VALUES (?, ?, ?)", userId, sidekickId, "2026-10-21T09:00:00.000Z");
  }
  return { headers: { Authorization: `Bearer ${token}` } };
}

describe("the Worker: first-load copy and GET /sidekicks/:id/tools.js", () => {
  it("copies tools.js with the base on a user's first load and names it in their pointer", async () => {
    const env = makeEnv();
    const auth = signIn(env, "u-new", ["reminders"]);
    const response = await app.request("/sidekicks/reminders/bundle", auth, env);
    expect(response.status).toBe(200);
    expect(env.BUNDLES.store["sidekicks/reminders/users/u-new/b2/tools.js"]).toBe(TOOLS_V2);
    expect(JSON.parse(env.BUNDLES.store["sidekicks/reminders/users/u-new/current.json"]).tools).toBe("tools.js");
    expect(JSON.parse(env.BUNDLES.store["sidekicks/reminders/users/u-new/b2/version.json"]).tools).toBe("tools.js");
  });

  it("serves the user's own version's tools.js, keyed by version", async () => {
    const env = makeEnv();
    const auth = signIn(env, "u-own", ["reminders"]);
    const response = await app.request("/sidekicks/reminders/tools.js?version=u9", auth, env);
    expect(response.status).toBe(200);
    expect(await response.text()).toBe(TOOLS_U9);
    expect(response.headers.get("X-Midas-Bundle-Version")).toBe("u9");
    expect(response.headers.get("Content-Type")).toContain("javascript");
  });

  it("answers 409 for a version that is no longer current, 404 without tools or assignment", async () => {
    const env = makeEnv();
    const auth = signIn(env, "u-own", ["reminders", "notes"]);
    const stale = await app.request("/sidekicks/reminders/tools.js?version=b2", auth, env);
    expect(stale.status).toBe(409);
    expect(await stale.json()).toEqual({ error: "version changed", version: "u9" });
    const noTools = await app.request("/sidekicks/notes/tools.js", auth, env);
    expect(noTools.status).toBe(404);
    const other = signIn(env, "u-other", []);
    const notAssigned = await app.request("/sidekicks/reminders/tools.js", other, env);
    expect(notAssigned.status).toBe(404);
    const signedOut = await app.request("/sidekicks/reminders/tools.js", {}, env);
    expect(signedOut.status).toBe(401);
  });

  it("a base without tools copies none and leaves the pointer as before", async () => {
    const env = makeEnv();
    const auth = signIn(env, "u-notes", ["notes"]);
    await app.request("/sidekicks/notes/bundle", auth, env);
    expect("sidekicks/notes/users/u-notes/n1/tools.js" in env.BUNDLES.store).toBe(false);
    expect("tools" in JSON.parse(env.BUNDLES.store["sidekicks/notes/users/u-notes/current.json"])).toBe(false);
  });
});

describe("the repair asset bundle.tools.js", () => {
  it("serves the reporter's copy's tools.js to the runner, and 404 when the copy has none", async () => {
    const env = makeRepairEnv({
      "sidekicks/reminders/current.json": JSON.stringify({ version: "v3", scriptHashes: [], tools: "tools.js" }),
      "sidekicks/reminders/v3/index.html": "<p>base</p>",
      "sidekicks/reminders/v3/manifest.json": "{}",
      "sidekicks/reminders/v3/tools.js": TOOLS_V2,
      "sidekicks/notes/current.json": JSON.stringify({ version: "n1", scriptHashes: [] }),
      "sidekicks/notes/n1/index.html": "<p>notes</p>",
      "sidekicks/notes/n1/manifest.json": "{}",
    });
    const token = addRepairUser(env, "amogh", ["reminders", "notes"]);
    const reportId = await createReport(env, token);
    const tools = await getAsset(env, reportId, ASSET_NAMES.bundleTools, runnerHeaders());
    expect(tools.status).toBe(200);
    expect(await tools.text()).toBe(TOOLS_V2);
    expect(tools.headers.get("Content-Type")).toContain("javascript");
    const notesReport = await createReport(env, token, { sidekickId: "notes" });
    const none = await getAsset(env, notesReport, ASSET_NAMES.bundleTools, runnerHeaders());
    expect(none.status).toBe(404);
  });
});

describe("the runner carries tools.js", () => {
  const job = { id: "job-tools", sidekickId: "reminders", kind: "change", bundleVersion: "v3", device: null, appVersion: null, createdAt: null, transcript: "make it bigger" };

  it("writes tools.js into the job folder, allows it there, snapshots and reads it", () => {
    const files = remindersFiles();
    const jobsRoot = mkdtempSync(join(tmpdir(), "tools-jobs-"));
    const jobFolder = buildJobFolder({ jobsRoot, job, bundle: files, assets: {} });
    expect(readFileSync(join(jobFolder, "sidekick", "tools.js"), "utf8")).toBe(files.toolsText);
    expect(isAllowedJobFile("sidekick/tools.js")).toBe(true);
    expect(presentSidekickFiles(jobFolder)).toEqual(["index.html", "manifest.json", "tools.js"]);
    expect(readSidekickFiles(jobFolder)["tools.js"]).toBe(files.toolsText);
    const snapshot = join(jobsRoot, "before");
    snapshotSidekickFiles(jobFolder, snapshot);
    expect(readFileSync(join(snapshot, "tools.js"), "utf8")).toBe(files.toolsText);
  });

  it("a copy without tools.js gets a job folder without it", () => {
    const jobsRoot = mkdtempSync(join(tmpdir(), "tools-jobs-"));
    const jobFolder = buildJobFolder({ jobsRoot, job, bundle: { html: PLAIN_HTML, manifestText: PLAIN_MANIFEST, toolsText: null }, assets: {} });
    expect(existsSync(join(jobFolder, "sidekick", "tools.js"))).toBe(false);
    expect(presentSidekickFiles(jobFolder)).toEqual(["index.html", "manifest.json"]);
  });

  it("the runner's gate refuses an agent block without tools.js and drifted tools.js", async () => {
    const files = remindersFiles();
    const checkoutRoot = REPO_ROOT;
    expect(await gateProblems({ checkoutRoot, sidekickId: "reminders", html: files.html, manifestText: files.manifestText, toolsText: files.toolsText })).toEqual([]);
    expect(await gateProblems({ checkoutRoot, sidekickId: "reminders", html: files.html, manifestText: files.manifestText, toolsText: null })).toEqual(["manifest.json has agent tools but there is no tools.js"]);
    const drifted = files.html.replace("function markDoneChange(occurrenceIso, nowIso) {", "function markDoneChange(occurrenceIso, nowIso) {\n    // changed");
    const driftProblems = await gateProblems({ checkoutRoot, sidekickId: "reminders", html: drifted, manifestText: files.manifestText, toolsText: files.toolsText });
    expect(driftProblems.join(" ")).toContain("no longer matches index.html");
  });

  it("the check sandbox, the staged deploy and the expected hash all hold tools.js", async () => {
    const files = remindersFiles();
    const jobsRoot = mkdtempSync(join(tmpdir(), "tools-jobs-"));
    const jobFolder = buildJobFolder({ jobsRoot, job, bundle: files, assets: {} });
    const checkout = join(jobsRoot, "checkout");
    mkdirSync(join(checkout, "sidekicks", "reminders"), { recursive: true });
    mkdirSync(join(checkout, "backend", "scripts"), { recursive: true });
    writeFileSync(join(checkout, "backend", "scripts", "bundle-tools.mjs"), readFileSync(join(REPO_ROOT, "backend", "scripts", "bundle-tools.mjs"), "utf8"));
    const sandboxRoot = join(jobsRoot, "sandbox");
    buildSandboxCheckout({ checkoutRoot: checkout, sidekickId: "reminders", jobFolder, sandboxRoot });
    expect(readFileSync(join(sandboxRoot, "sidekicks", "reminders", "tools.js"), "utf8")).toBe(files.toolsText);

    const deployFolder = join(jobsRoot, "deploy");
    stageDeployFolder({ jobFolder, deployFolder });
    expect(readFileSync(join(deployFolder, "tools.js"), "utf8")).toBe(files.toolsText);
    expect(await expectedContentHash({ checkoutRoot: checkout, jobFolder })).toBe(bundleContentHash(files.html, files.manifestText, files.toolsText));
  });
});
