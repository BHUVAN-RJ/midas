// Publish first, setup (founder, 2026-11-13; docs/briefs/repair-lanes.md W7): a job's setup is on
// the way to the person. The copy's tests come through the Worker in one request
// (GET /repairs/:id/copy-tests) instead of one wrangler process per file, and the report's files
// download at the same time.
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import app from "../src/index";
import { createBackendClient } from "../../runner/lib/backend.mjs";
import { fetchCopyTestsThroughWorker } from "../../runner/lib/copy-tests.mjs";
import { runJob } from "../../runner/lib/run-job.mjs";
import { plannedSteps } from "../../runner/core-checks/page-open.mjs";
import { makeFakeR2 } from "./helpers/fake-r2";
import { makeMigratedD1 } from "./helpers/migrated-d1";
import {
  AGENT_THAT_FIXES_TITLE,
  REPO_ROOT,
  RUNNER_TOKEN as FIXTURE_RUNNER_TOKEN,
  fakeDeployThatLands,
  fakeFetchWithStoredTests,
  makeScratch,
  standardAssets,
  startFakeBackend,
  writeStubAgent,
  type FakeBackend,
} from "./helpers/runner-fixture";

const RUNNER_TOKEN = "runner-token-setup";
const USER_ID = "amogh";
const OWN_VERSION = "20261101T000000000Z-aaaaaaaa";
const BASE_VERSION = "20261020T000000000Z-bbbbbbbb";
const OWN_PREFIX = `sidekicks/todo/users/${USER_ID}`;

function makeEnv(objects: Record<string, string>) {
  const env = { DB: makeMigratedD1(), BUNDLES: makeFakeR2(objects), REPAIR_RUNNER_TOKEN: RUNNER_TOKEN };
  const token = `token-${USER_ID}`;
  const sessionHash = createHash("sha256").update(token).digest("hex");
  env.DB.execute("INSERT INTO users (id, name, created_at) VALUES (?, ?, 'now')", USER_ID, USER_ID);
  env.DB.execute("INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, 'now', ?)", sessionHash, USER_ID, Date.now() + 3_600_000);
  env.DB.execute("INSERT INTO assignments (user_id, sidekick_id, assigned_at) VALUES (?, 'todo', 'now')", USER_ID);
  return { env, token };
}

function ownCopyObjects(files: Record<string, string>) {
  const objects: Record<string, string> = {
    [`${OWN_PREFIX}/current.json`]: JSON.stringify({ version: OWN_VERSION, scriptHashes: [] }),
    [`${OWN_PREFIX}/${OWN_VERSION}/tests/index.json`]: JSON.stringify({ files: Object.keys(files) }),
  };
  for (const [name, body] of Object.entries(files)) {
    objects[`${OWN_PREFIX}/${OWN_VERSION}/tests/${name}`] = body;
  }
  return objects;
}

function backendFor(env: ReturnType<typeof makeEnv>["env"]) {
  async function fetchThroughWorker(url: string, init?: RequestInit) {
    return app.request(url.replace("https://worker.test", ""), init, env);
  }
  return createBackendClient({ baseUrl: "https://worker.test", token: RUNNER_TOKEN, fetchImplementation: fetchThroughWorker });
}

async function claimedReport(env: ReturnType<typeof makeEnv>["env"], token: string) {
  const form = new FormData();
  form.set("sidekickId", "todo");
  form.set("kind", "change");
  form.set("transcript", "bigger");
  const created = await app.request("/repairs", { method: "POST", headers: { Authorization: `Bearer ${token}` }, body: form }, env);
  expect(created.status).toBe(201);
  const backend = backendFor(env);
  const job = await backend.claimJob();
  return { backend, job };
}

describe("GET /repairs/:id/copy-tests", () => {
  it("gives the tests of the version the person has, without the index", async () => {
    const { env, token } = makeEnv(ownCopyObjects({ "todo-logic.test.ts": "it('a', () => {});", "TEST_CHANGES.md": "log" }));
    const { backend, job } = await claimedReport(env, token);
    const reply = await backend.copyTests(job.id);
    expect(reply).toEqual({ scope: "user", version: OWN_VERSION, files: { "todo-logic.test.ts": "it('a', () => {});", "TEST_CHANGES.md": "log" } });
  });

  it("falls back to the base's tests when the person has no copy of their own", async () => {
    const objects = {
      "sidekicks/todo/current.json": JSON.stringify({ version: BASE_VERSION, scriptHashes: [] }),
      [`sidekicks/todo/${BASE_VERSION}/tests/index.json`]: JSON.stringify({ files: ["todo-widget.test.ts"] }),
      [`sidekicks/todo/${BASE_VERSION}/tests/todo-widget.test.ts`]: "base test",
    };
    const { env, token } = makeEnv(objects);
    const { backend, job } = await claimedReport(env, token);
    const reply = await backend.copyTests(job.id);
    expect(reply).toEqual({ scope: "base", version: BASE_VERSION, files: { "todo-widget.test.ts": "base test" } });
  });

  it("refuses a listed file that is not stored, a user session, and a report not claimed", async () => {
    const objects = ownCopyObjects({ "todo-logic.test.ts": "x" });
    delete objects[`${OWN_PREFIX}/${OWN_VERSION}/tests/todo-logic.test.ts`];
    const { env, token } = makeEnv(objects);
    const { job } = await claimedReport(env, token);
    const missing = await app.request(`/repairs/${job.id}/copy-tests`, { headers: { Authorization: `Runner ${RUNNER_TOKEN}` } }, env);
    expect(missing.status).toBe(409);
    const asUser = await app.request(`/repairs/${job.id}/copy-tests`, { headers: { Authorization: `Bearer ${token}` } }, env);
    expect(asUser.status).toBe(401);
    env.DB.execute("UPDATE repair_reports SET status = 'queued' WHERE id = ?", job.id);
    const queued = await app.request(`/repairs/${job.id}/copy-tests`, { headers: { Authorization: `Runner ${RUNNER_TOKEN}` } }, env);
    expect(queued.status).toBe(409);
  });
});

describe("fetchCopyTestsThroughWorker", () => {
  it("keeps the copy's own tests, and uses the base Sidekick's from the checkout when it has none", async () => {
    const stored = makeEnv(ownCopyObjects({ "todo-logic.test.ts": "own", "TEST_CHANGES.md": "" }));
    const storedJob = await claimedReport(stored.env, stored.token);
    const own = await fetchCopyTestsThroughWorker({ backend: storedJob.backend, reportId: storedJob.job.id, checkoutRoot: REPO_ROOT, sidekickId: "todo" });
    expect(own.source).toBe("user copy");
    expect(own.files["todo-logic.test.ts"]).toBe("own");
    const onlyLog = makeEnv(ownCopyObjects({ "TEST_CHANGES.md": "" }));
    const onlyLogJob = await claimedReport(onlyLog.env, onlyLog.token);
    const base = await fetchCopyTestsThroughWorker({ backend: onlyLogJob.backend, reportId: onlyLogJob.job.id, checkoutRoot: REPO_ROOT, sidekickId: "todo" });
    expect(base.source).toBe("base checkout");
    expect(Object.keys(base.files)).toContain("todo-logic.test.ts");
  });

  it("refuses a file name that could leave tests/", async () => {
    const forgedBackend = {
      copyTests: async function forgedReply() {
        return { scope: "user", version: OWN_VERSION, files: { "../escape.ts": "x" } };
      },
    };
    await expect(fetchCopyTestsThroughWorker({ backend: forgedBackend, reportId: "r", checkoutRoot: REPO_ROOT, sidekickId: "todo" })).rejects.toThrow("bad file name");
  });
});

// ---- runJob: setup through the Worker, downloads at the same time -------------------------------

const JOB_ROW = {
  id: "rep-setup-1",
  user_id: "user-77",
  sidekick_id: "reminders",
  bundle_version: "20261011T065908559Z-1064a312",
  kind: "change",
  transcript: "call it My Reminders",
};

let openBackend: FakeBackend | null = null;

afterEach(async () => {
  if (openBackend !== null) {
    await openBackend.close();
    openBackend = null;
  }
});

async function cleanPages({ actions, kinds, records }: { actions: string[]; kinds: string[]; records: unknown[] }) {
  const steps = plannedSteps({ records, actions, kinds });
  return steps.map(function cleanStep(step: { name: string; action: string | null }) {
    const report = { errors: [], writes: [], written: {}, visibleElements: 5, textLength: 5, action: step.action === null ? null : { found: true } };
    return { name: step.name, action: step.action, report };
  });
}

describe("runJob setup, publish first", () => {
  it("takes the copy's tests from the Worker (no fetch script) and downloads the report's files at the same time", async () => {
    const { scratch, checkout, settings } = makeScratch();
    const backendServer = await startFakeBackend(JOB_ROW, standardAssets());
    openBackend = backendServer;
    const client = createBackendClient({ baseUrl: backendServer.baseUrl, token: FIXTURE_RUNNER_TOKEN });
    let inFlight = 0;
    let mostAtOnce = 0;
    async function countedDownload(reportId: string, assetName: string) {
      inFlight += 1;
      mostAtOnce = Math.max(mostAtOnce, inFlight);
      await new Promise(function shortWait(resolve) {
        setTimeout(resolve, 20);
      });
      try {
        return await client.downloadAsset(reportId, assetName);
      } finally {
        inFlight -= 1;
      }
    }
    const storedTests = { "reminders-stored.test.ts": "it('stored', () => {});\n", "TEST_CHANGES.md": "" };
    async function copyTestsFromWorker() {
      return { scope: "user", version: "v1", files: storedTests };
    }
    let pointerVersion: string | null = null;
    const backend = {
      ...client,
      downloadAsset: countedDownload,
      copyTests: copyTestsFromWorker,
      publishFiles: async function stored() {
        return {};
      },
      flipPointer: async function flipped(_reportId: string, { version }: { version: string }) {
        pointerVersion = version;
        return { version, previousVersion: null };
      },
      rollBackPointer: async function notExpected() {
        throw new Error("no roll back expected");
      },
    };
    const job = await backend.claimJob();
    const fetchScript = fakeFetchWithStoredTests({});
    const deploy = fakeDeployThatLands();
    async function testsPass() {
      return { ok: true, output: "1 passed" };
    }
    async function quiet() {}
    const result = await runJob(job, {
      backend,
      settings: { ...settings, publishMode: "first" },
      agentCommand: process.execPath,
      agentArgs: [writeStubAgent(scratch, AGENT_THAT_FIXES_TITLE)],
      runFetch: fetchScript.runFetch,
      runTests: testsPass,
      runDeploy: deploy.runDeploy,
      readPointer: deploy.readPointer,
      notify: quiet,
      openPageImplementation: cleanPages,
    });
    expect(result.status).toBe("deployed_live");
    expect(pointerVersion).toBe(result.version);
    expect(fetchScript.calls).toEqual([]);
    const report = JSON.parse(readFileSync(join(result.logFolder, "tests-report.json"), "utf8"));
    expect(report.source).toBe("user copy");
    expect(readFileSync(join(result.jobFolder, "tests", "reminders-stored.test.ts"), "utf8")).toContain("stored");
    expect(mostAtOnce).toBeGreaterThanOrEqual(5);
    expect(checkout.length).toBeGreaterThan(0);
  });
});
