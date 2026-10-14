import { createHash } from "node:crypto";
import { describe, expect, it } from "vitest";
import app from "../src/index";
import {
  TEST_FILE_NAME_PATTERN,
  baseTestFileNames,
  planDeploy,
  planTestFiles,
  testFileKey,
  testsIndexKey,
} from "../scripts/bundle-tools.mjs";
import { makeMigratedD1 } from "./helpers/migrated-d1";

// Tests move every copy forward (founder, 2026-10-13): each version in R2 carries its tests and
// test log under <version>/tests/, listed in tests/index.json. A new user copy starts with the
// base's tests. Nothing under tests/ is ever served to the phone.

const BASE_HTML = "<!doctype html><title>Reminders</title><script>document.title='base'</script>";
const BASE_MANIFEST = { id: "reminders", name: "Reminders", icon: { symbol: "checklist", background: "#FF9500" }, reads: [] };
const LOGIC_TEST = "import { it } from 'vitest'; it('fires once', () => {});";
const WORDING_TEST = "import { it } from 'vitest'; it('says the action', () => {});";
const TEST_LOG = "# Test changes\n\n- 2026-10-13 base tests\n";
const AT = new Date("2026-10-13T10:00:00.000Z");

const TEST_FILES = [
  { name: "reminders-logic.test.ts", body: LOGIC_TEST },
  { name: "reminders-wording.test.ts", body: WORDING_TEST },
  { name: "TEST_CHANGES.md", body: TEST_LOG },
];

function keysOf(puts: Array<{ key: string }>): string[] {
  return puts.map(keyOf);
}

function keyOf(put: { key: string }): string {
  return put.key;
}

describe("planDeploy stores the tests with the version", () => {
  const plan = planDeploy({ sidekickId: "reminders", userId: "u-amogh", html: BASE_HTML, manifestText: JSON.stringify(BASE_MANIFEST), testFiles: TEST_FILES, deployedAt: AT, baseVersion: "b2" });
  const prefix = `sidekicks/reminders/users/u-amogh/${plan.version}`;

  it("writes every test file and the index under tests/, before version.json and the pointer", () => {
    expect(keysOf(plan.puts)).toEqual([
      `${prefix}/index.html`,
      `${prefix}/manifest.json`,
      `${prefix}/tests/reminders-logic.test.ts`,
      `${prefix}/tests/reminders-wording.test.ts`,
      `${prefix}/tests/TEST_CHANGES.md`,
      `${prefix}/tests/index.json`,
      `${prefix}/version.json`,
      "sidekicks/reminders/users/u-amogh/current.json",
    ]);
    const indexPut = plan.puts[5];
    expect(JSON.parse(indexPut.body)).toEqual({ files: ["reminders-logic.test.ts", "reminders-wording.test.ts", "TEST_CHANGES.md"] });
    expect(plan.puts[2].body).toBe(LOGIC_TEST);
    expect(plan.puts[4].body).toBe(TEST_LOG);
  });

  it("lists the test files in version.json", () => {
    const versionRecord = JSON.parse(plan.puts[6].body);
    expect(versionRecord.testFiles).toEqual(["reminders-logic.test.ts", "reminders-wording.test.ts", "TEST_CHANGES.md"]);
  });

  it("writes an empty index when a version has no tests, so a fetch can tell none from missing", () => {
    const puts = planTestFiles("sidekicks/reminders", "b1", []);
    expect(keysOf(puts)).toEqual(["sidekicks/reminders/b1/tests/index.json"]);
    expect(JSON.parse(puts[0].body)).toEqual({ files: [] });
  });

  it("refuses a test file name that could leave tests/", () => {
    function keyWithSlash() {
      return testFileKey("sidekicks/reminders", "b1", "../index.html");
    }
    function keyNamedIndex() {
      return testFileKey("sidekicks/reminders", "b1", "index.json");
    }
    expect(keyWithSlash).toThrow(/bad test file name/);
    expect(keyNamedIndex).toThrow(/bad test file name/);
    expect(TEST_FILE_NAME_PATTERN.test("reminders-logic.test.ts")).toBe(true);
    expect(TEST_FILE_NAME_PATTERN.test(".hidden")).toBe(false);
    expect(testsIndexKey("sidekicks/reminders", "b1")).toBe("sidekicks/reminders/b1/tests/index.json");
  });
});

describe("baseTestFileNames", () => {
  const directoryEntries = ["reminders-wording.test.ts", "reminders-logic.test.ts", "sync.test.ts", "reminders-notes.md", "helpers", "care-reminders-bundle.test.ts"];

  it("takes only backend/test/<id>-*.test.ts, sorted", () => {
    expect(baseTestFileNames("reminders", directoryEntries)).toEqual(["reminders-logic.test.ts", "reminders-wording.test.ts"]);
    expect(baseTestFileNames("care-reminders", directoryEntries)).toEqual(["care-reminders-bundle.test.ts"]);
    expect(baseTestFileNames("calendar", directoryEntries)).toEqual([]);
  });
});

// ---- the Worker: first load copies the base's tests; nothing under tests/ is served ----------

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

function makeEnv(extraObjects: Record<string, string> = {}) {
  const bucket = makeRecordingBucket({
    "sidekicks/reminders/current.json": JSON.stringify({ version: "b2", scriptHashes: ["'sha256-BASE='"], contentHash: "hash-b2", baseVersion: null }),
    "sidekicks/reminders/b2/index.html": BASE_HTML,
    "sidekicks/reminders/b2/manifest.json": JSON.stringify(BASE_MANIFEST),
    "sidekicks/reminders/b2/tests/reminders-logic.test.ts": LOGIC_TEST,
    "sidekicks/reminders/b2/tests/reminders-wording.test.ts": WORDING_TEST,
    "sidekicks/reminders/b2/tests/TEST_CHANGES.md": TEST_LOG,
    "sidekicks/reminders/b2/tests/index.json": JSON.stringify({ files: ["reminders-logic.test.ts", "reminders-wording.test.ts", "TEST_CHANGES.md"] }),
    // An older base, deployed before tests were stored: no index.
    "sidekicks/notes/current.json": JSON.stringify({ version: "n1", scriptHashes: [], contentHash: "hash-n1" }),
    "sidekicks/notes/n1/index.html": "<p>notes</p>",
    "sidekicks/notes/n1/manifest.json": JSON.stringify({ ...BASE_MANIFEST, id: "notes", name: "Notes" }),
    ...extraObjects,
  });
  return { DB: makeMigratedD1(), BUNDLES: bucket };
}

type TestEnv = ReturnType<typeof makeEnv>;

function addSignedInUser(env: TestEnv, userId: string, name: string): string {
  const token = `token-${userId}`;
  const farFuture = Date.now() + 60 * 60 * 1000;
  env.DB.execute("INSERT INTO users (id, name, created_at) VALUES (?, ?, 'now')", userId, name);
  env.DB.execute("INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, 'now', ?)", sha256Hex(token), userId, farFuture);
  return token;
}

function assign(env: TestEnv, userId: string, sidekickId: string) {
  env.DB.execute("INSERT INTO assignments (user_id, sidekick_id, assigned_at) VALUES (?, ?, ?)", userId, sidekickId, "2026-10-13T09:00:00.000Z");
}

function authorized(token: string) {
  return { headers: { Authorization: `Bearer ${token}` } };
}

describe("first load copies the base's tests into the user's copy", () => {
  it("copies every listed test file, the log and the index, and records them in version.json", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "u-priya", "Priya");
    assign(env, "u-priya", "reminders");
    const response = await app.request("/sidekicks/reminders/bundle", authorized(token), env);
    expect(response.status).toBe(200);

    const ownPrefix = "sidekicks/reminders/users/u-priya/b2";
    expect(env.BUNDLES.writtenKeys).toEqual([
      `${ownPrefix}/index.html`,
      `${ownPrefix}/manifest.json`,
      `${ownPrefix}/tests/reminders-logic.test.ts`,
      `${ownPrefix}/tests/reminders-wording.test.ts`,
      `${ownPrefix}/tests/TEST_CHANGES.md`,
      `${ownPrefix}/tests/index.json`,
      `${ownPrefix}/version.json`,
      "sidekicks/reminders/users/u-priya/current.json",
    ]);
    expect(env.BUNDLES.store[`${ownPrefix}/tests/reminders-logic.test.ts`]).toBe(LOGIC_TEST);
    expect(env.BUNDLES.store[`${ownPrefix}/tests/TEST_CHANGES.md`]).toBe(TEST_LOG);
    expect(JSON.parse(env.BUNDLES.store[`${ownPrefix}/tests/index.json`])).toEqual({ files: ["reminders-logic.test.ts", "reminders-wording.test.ts", "TEST_CHANGES.md"] });
    const versionRecord = JSON.parse(env.BUNDLES.store[`${ownPrefix}/version.json`]);
    expect(versionRecord.testFiles).toEqual(["reminders-logic.test.ts", "reminders-wording.test.ts", "TEST_CHANGES.md"]);
  });

  it("copies a base deployed before tests were stored without tests, and says so", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "u-priya", "Priya");
    assign(env, "u-priya", "notes");
    const response = await app.request("/sidekicks/notes/bundle", authorized(token), env);
    expect(response.status).toBe(200);
    const ownPrefix = "sidekicks/notes/users/u-priya/n1";
    expect(env.BUNDLES.writtenKeys).toEqual([`${ownPrefix}/index.html`, `${ownPrefix}/manifest.json`, `${ownPrefix}/version.json`, "sidekicks/notes/users/u-priya/current.json"]);
    expect(JSON.parse(env.BUNDLES.store[`${ownPrefix}/version.json`]).testFiles).toBeNull();
  });

  it("does not write the pointer when a listed test file is missing, so the copy is retried", async () => {
    const env = makeEnv({ "sidekicks/reminders/b2/tests/index.json": JSON.stringify({ files: ["reminders-logic.test.ts", "reminders-gone.test.ts"] }) });
    const token = addSignedInUser(env, "u-priya", "Priya");
    assign(env, "u-priya", "reminders");
    const response = await app.request("/sidekicks/reminders/bundle", authorized(token), env);
    expect(response.status).toBe(200);
    expect(await response.text()).toBe(BASE_HTML);
    expect(env.BUNDLES.writtenKeys).not.toContain("sidekicks/reminders/users/u-priya/current.json");
  });
});

describe("tests are never served", () => {
  it("has no route for a version's tests and the bundle route serves only index.html", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "u-priya", "Priya");
    assign(env, "u-priya", "reminders");
    const bundle = await app.request("/sidekicks/reminders/bundle", authorized(token), env);
    const bundleText = await bundle.text();
    expect(bundleText).toBe(BASE_HTML);
    expect(bundleText).not.toContain("vitest");

    const testPaths = [
      "/sidekicks/reminders/tests/reminders-logic.test.ts",
      "/sidekicks/reminders/b2/tests/reminders-logic.test.ts",
      "/sidekicks/reminders/b2/tests/index.json",
      "/sidekicks/reminders/users/u-priya/b2/tests/index.json",
      "/sidekicks/reminders/bundle/tests/index.json",
    ];
    for (const testPath of testPaths) {
      const response = await app.request(testPath, authorized(token), env);
      expect(response.status).toBe(404);
      expect(await response.text()).not.toContain(LOGIC_TEST);
    }
  });
});
