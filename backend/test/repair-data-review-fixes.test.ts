// Fixes from the two reviews of the repair-data branch (founder go, 2026-10-19). Each case fails
// without its fix:
//   1  the copies planner never publishes a copy that skipped the schema and records checks
//   2  the add-only check: "not" and "contains" polarity, a new field a stored record already
//      holds, a new prefix that shadows existing keys
//   3  the records route: one GROUP BY (no per-key subquery), delete-then-rewrite, a byte cap
//   4  key order in a const and order in a type list are not changes
//   5  the agent cannot move the schema baseline
//   6  the runner refuses to start when its backend and publish environment differ
//   7  the validator comes from the checkout the runner deploys from
//   8  care-reminders' prompt describes everyHours as its own field
//   9  a failure names the key as it is stored
//   10 a copy without types is refused before the agent
import { createHash } from "node:crypto";
import { appendFileSync, cpSync, existsSync, mkdirSync, readFileSync, rmSync, statSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import app from "../src/index";
import { MAX_REPORT_RECORD_BYTES, REPORT_RECORDS_SIZE_SQL, REPORT_RECORDS_SQL } from "../src/repairs";
import { createBackendClient } from "../../runner/lib/backend.mjs";
import { BACKEND_HOSTS, checkBackendMatchesEnvironment, startupSettings } from "../../runner/lib/config.mjs";
import { buildSystemPrompt } from "../../runner/lib/prompt.mjs";
import { NO_SCHEMA_REASON, runJob } from "../../runner/lib/run-job.mjs";
import { compareSchema, schemaChangeProblems } from "../../runner/lib/schema-change.mjs";
import { checkUserRecords, recordFailureDetail, storedRecordSchemaProblems } from "../../runner/lib/user-records.mjs";
import { bundleContentHash } from "../scripts/bundle-tools.mjs";
import { currentStoreHelper } from "../scripts/store-helper.mjs";
import { planUserCopy } from "../scripts/user-copy-plan.mjs";
import { makeFakeR2 } from "./helpers/fake-r2";
import { makeMigratedD1 } from "./helpers/migrated-d1";
import {
  AGENT_THAT_FIXES_TITLE,
  REPO_ROOT,
  RUNNER_TOKEN,
  fakeDeployThatLands,
  fakeFetchWithoutStoredTests,
  makeScratch,
  remindersBundle,
  startFakeBackend,
  writeStubAgent,
} from "./helpers/runner-fixture";

function readRepoText(relativePath: string): string {
  return readFileSync(join(REPO_ROOT, relativePath), "utf8");
}

function manifestOf(sidekickId: string) {
  return JSON.parse(readRepoText(`sidekicks/${sidekickId}/manifest.json`));
}

function typesOf(sidekickId: string) {
  return JSON.parse(JSON.stringify(manifestOf(sidekickId).types));
}

function problemsBetween(oldSchema: unknown, newSchema: unknown): string[] {
  const problems: string[] = [];
  compareSchema(oldSchema, newSchema, "t", problems);
  return problems;
}

// ---- the runner, end to end -------------------------------------------------------------------

type StoredRecord = { key: string; value: unknown };
type OpenBackend = Awaited<ReturnType<typeof startFakeBackend>>;

const JOB_ROW = { id: "rep-review-1", user_id: "user-7", sidekick_id: "reminders", bundle_version: "v-copy", kind: "change", transcript: "add a priority" };

let openBackend: OpenBackend | null = null;

afterEach(async () => {
  if (openBackend !== null) {
    await openBackend.close();
    openBackend = null;
  }
});

// The scratch checkout with the validator and the store helper the runner loads from it (the
// fixture may not copy them; the runner must find them in the checkout).
function completeCheckout(checkout: string) {
  const files = [
    join("shell", "sdk", "record-schema.js"),
    join("shell", "sdk", "shell-types.js"),
    join("shell", "sdk", "midas-store.js"),
  ];
  for (const file of files) {
    const target = join(checkout, file);
    if (!existsSync(target)) {
      mkdirSync(join(target, ".."), { recursive: true });
      cpSync(join(REPO_ROOT, file), target);
    }
  }
}

type RunOptions = {
  agentSource: string;
  records?: StoredRecord[];
  manifestText?: string;
  prepareCheckout?: (checkout: string) => void;
};

async function runReviewJob({ agentSource, records = [], manifestText = remindersBundle().manifestText, prepareCheckout }: RunOptions) {
  const { scratch, checkout, settings } = makeScratch();
  completeCheckout(checkout);
  if (prepareCheckout !== undefined) {
    prepareCheckout(checkout);
  }
  const assets = { "bundle.html": remindersBundle().html, "bundle.manifest.json": manifestText, "bundle.tools.js": remindersBundle().toolsText };
  const backendServer = await startFakeBackend(JOB_ROW, assets, records);
  openBackend = backendServer;
  const backend = createBackendClient({ baseUrl: backendServer.baseUrl, token: RUNNER_TOKEN });
  const job = await backend.claimJob();
  const deploy = fakeDeployThatLands();
  const agentPath = writeStubAgent(scratch, agentSource);
  const result = await runJob(job, {
    backend,
    settings,
    agentCommand: process.execPath,
    agentArgs: [agentPath],
    runFetch: fakeFetchWithoutStoredTests().runFetch,
    runTests: async function passingTests() {
      return { ok: true, output: "all passed" };
    },
    runDeploy: deploy.runDeploy,
    readPointer: deploy.readPointer,
    notify: async function ignoreNotification() {},
  });
  return { result, deploy, backendServer, checkout };
}

const AGENT_THAT_ADDS_PRIORITY = `
import { readFileSync, writeFileSync } from "node:fs";
const manifest = JSON.parse(readFileSync("sidekick/manifest.json", "utf8"));
manifest.types["reminder:"].schema.properties.priority = { type: "integer", minimum: 1, maximum: 3 };
writeFileSync("sidekick/manifest.json", JSON.stringify(manifest, null, 2));
const page = readFileSync("sidekick/index.html", "utf8");
writeFileSync("sidekick/index.html", page.replace("<title>Reminders</title>", "<title>Reminders · priority</title>"));
writeFileSync("outcome.json", JSON.stringify({ result: "fixed", summary: "Added a priority." }));
`;

// Renames notes to memo (breaking), then tries to move the baseline: overwrites the file the
// check tool is given and the log folder's before/manifest.json with its own manifest.
const AGENT_THAT_MOVES_THE_BASELINE = `
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
const manifest = JSON.parse(readFileSync("sidekick/manifest.json", "utf8"));
const properties = manifest.types["reminder:"].schema.properties;
properties.memo = properties.notes;
delete properties.notes;
const manifestText = JSON.stringify(manifest, null, 2);
writeFileSync("sidekick/manifest.json", manifestText);
const baselinePath = process.env.MIDAS_JOB_MANIFEST_BEFORE;
const targets = [baselinePath, join(dirname(baselinePath), "before", "manifest.json"), join(dirname(baselinePath), "manifest.json")];
for (const target of targets) {
  try {
    if (existsSync(target)) {
      writeFileSync(target, manifestText);
    }
  } catch {}
}
const page = readFileSync("sidekick/index.html", "utf8");
writeFileSync("sidekick/index.html", page.replace("<title>Reminders</title>", "<title>Reminders · memo</title>"));
writeFileSync("outcome.json", JSON.stringify({ result: "fixed", summary: "Renamed notes to memo." }));
`;

const AGENT_THAT_RECORDS_IT_RAN = `
import { readFileSync, writeFileSync } from "node:fs";
writeFileSync("agent-ran.txt", "yes");
const page = readFileSync("sidekick/index.html", "utf8");
writeFileSync("sidekick/index.html", page.replace("<title>Reminders</title>", "<title>X</title>"));
writeFileSync("outcome.json", JSON.stringify({ result: "fixed", summary: "x" }));
`;

describe("2: a new field a stored record already holds is refused", () => {
  it("refuses the repair when the reporter's record already has a priority field, and publishes when none has", async () => {
    const records = [
      { key: "reminder:1", value: { $type: "reminders.item", title: "Call mom", priority: 2 } },
      { key: "reminder:2", value: { $type: "reminders.item", title: "Plain" } },
    ];
    const clash = await runReviewJob({ agentSource: AGENT_THAT_ADDS_PRIORITY, records });
    expect(clash.result.status).toBe("failed");
    expect(clash.result.reason).toBe("schema not backward compatible");
    expect(clash.result.detail).toContain("reminders.item.priority is new but reminder:1 already holds a priority field");
    expect(clash.deploy.deployCalls).toEqual([]);
    await openBackend?.close();
    openBackend = null;

    const clean = await runReviewJob({ agentSource: AGENT_THAT_ADDS_PRIORITY, records: [records[1]] });
    expect(clean.result.status).toBe("deployed_live");
  });

  it("finds the clash at the top level, inside a $ref'd definition, and for a new patternProperties entry", () => {
    const before = manifestOf("reminders");
    const after = JSON.parse(JSON.stringify(before));
    after.types["reminder:"].schema.properties.priority = { type: "integer" };
    after.types["reminder:"].schema.$defs.repeat.properties.hourly = { type: "integer" };
    after.types["list:"].schema.patternProperties = { "^x-": { type: "string" } };
    const records = [
      { key: "reminder:1", value: { $type: "reminders.item", title: "a", priority: "high" } },
      { key: "reminder:2", value: { $type: "reminders.item", title: "b", at: "2026-10-20T09:00:00.000Z", repeat: { every: "day", hourly: 3 } } },
      { key: "list:home", value: { $type: "reminders.list", name: "Home", "x-colour": "red" } },
      { key: "reminder:3", value: { $type: "reminders.item", title: "c" } },
    ];
    const problems = storedRecordSchemaProblems({ sidekickId: "reminders", records, manifestBefore: before, manifest: after });
    expect(problems).toContain("reminders.item.priority is new but reminder:1 already holds a priority field");
    expect(problems).toContain("reminders.item.repeat.hourly is new but reminder:2 already holds a hourly field");
    expect(problems).toContain('reminders.list.patternProperties["^x-"] is new but list:home already holds a matching x-colour field');
    expect(problems).toHaveLength(3);
  });

  it("says so in both prompts", () => {
    for (const sidekickId of ["reminders", "care-reminders"]) {
      const prompt = buildSystemPrompt({
        job: { id: "r", sidekickId, kind: "change", transcript: "x", createdAt: "2026-10-19T10:00:00.000Z" },
        reportFiles: ["transcript.txt"],
        manifestText: readRepoText(`sidekicks/${sidekickId}/manifest.json`),
      });
      expect(prompt).toContain("**A new field name is one no record uses today.**");
      expect(prompt).toContain("**A new prefix shares no start with an existing one.**");
    }
  });
});

describe("2: a new prefix that shadows existing keys is refused", () => {
  it("refuses a new prefix that extends an existing one, or that one extends", () => {
    const after = typesOf("reminders");
    after["reminder:a"] = { $type: "reminders.alarm", schema: { type: "object" } };
    after["lis"] = { $type: "reminders.lis", schema: { type: "object" } };
    after["tag:"] = { $type: "reminders.tag", schema: { type: "object" } };
    const problems = schemaChangeProblems(typesOf("reminders"), after);
    expect(problems).toContain('types["reminder:a"] is new and overlaps types["reminder:"]: keys stored under one would be read as the other (use a prefix that shares no start with an existing one)');
    expect(problems.some(function namesLis(problem: string) {
      return problem.startsWith('types["lis"] is new and overlaps types["list:"]');
    })).toBe(true);
    expect(problems.some(function namesTag(problem: string) {
      return problem.includes('types["tag:"]');
    })).toBe(false);
  });

  it("refuses a new prefix that the reporter's stored keys would match", () => {
    const before = manifestOf("reminders");
    const after = JSON.parse(JSON.stringify(before));
    after.types["note:"] = { $type: "reminders.note", schema: { type: "object" } };
    const records = [{ key: "note:1", value: { $type: "reminders.note", text: "stored before any type" } }];
    const problems = storedRecordSchemaProblems({ sidekickId: "reminders", records, manifestBefore: before, manifest: after });
    expect(problems).toEqual(['the user\'s note:1 had no type and would now be reminders.note (types["note:"] is new)']);
    const withoutStoredKeys = storedRecordSchemaProblems({ sidekickId: "reminders", records: [], manifestBefore: before, manifest: after });
    expect(withoutStoredKeys).toEqual([]);
  });
});

describe("2: not and contains", () => {
  it("refuses a new not, even not: {} and not: true, and a not that now matches more", () => {
    expect(problemsBetween({ type: "object" }, { type: "object", not: {} })).toEqual(["t.not was added, so values that passed before may not"]);
    expect(problemsBetween({ type: "object" }, { type: "object", not: true })).toEqual(["t.not was added, so values that passed before may not"]);
    const widened = problemsBetween({ type: "string", not: { const: "a" } }, { type: "string", not: { enum: ["a", "b"] } });
    expect(widened).toHaveLength(1);
    expect(widened[0]).toMatch(/^t\.not now matches more values, so the field accepts fewer/);
    const widenedLimit = problemsBetween({ not: { type: "string", maxLength: 3 } }, { not: { type: "string" } });
    expect(widenedLimit).toHaveLength(1);
  });

  it("allows removing a not, a not that now matches less, and not: false", () => {
    expect(problemsBetween({ type: "string", not: { const: "a" } }, { type: "string" })).toEqual([]);
    expect(problemsBetween({ not: { type: "string" } }, { not: { type: "string", maxLength: 3 } })).toEqual([]);
    expect(problemsBetween({ type: "string" }, { type: "string", not: false })).toEqual([]);
  });

  it("refuses a new contains, even contains: {}", () => {
    expect(problemsBetween({ type: "array" }, { type: "array", contains: {} })).toEqual(["t.contains was added, so values that passed before may not"]);
  });
});

describe("4: order is not a change in a const or a type list; everything else stays refused", () => {
  it("allows a const with its keys reordered, a reordered type list, and \"string\" vs [\"string\"]", () => {
    expect(problemsBetween({ const: { a: 1, b: { c: 2, d: 3 } } }, { const: { b: { d: 3, c: 2 }, a: 1 } })).toEqual([]);
    expect(problemsBetween({ type: ["string", "null"] }, { type: ["null", "string"] })).toEqual([]);
    expect(problemsBetween({ type: "string" }, { type: ["string"] })).toEqual([]);
    expect(problemsBetween({ properties: { a: { type: "string" }, b: { type: "integer" } } }, { properties: { b: { type: "integer" }, a: { type: "string" } } })).toEqual([]);
  });

  it("still refuses a widened type, a reordered const array, a removed format and a changed anyOf", () => {
    expect(problemsBetween({ type: "string" }, { type: ["string", "null"] })).toEqual(["t changed its type"]);
    expect(problemsBetween({ const: [1, 2] }, { const: [2, 1] })).toEqual(["t changed its const"]);
    expect(problemsBetween({ type: "string", format: "date" }, { type: "string" })).toEqual(["t changed its format"]);
    expect(problemsBetween({ anyOf: [{ type: "string" }] }, { anyOf: [{ type: "string" }, { type: "integer" }] })).toEqual(["t changed its anyOf"]);
  });
});

describe("5: the agent cannot move the schema baseline", () => {
  it("still refuses a breaking change after the agent overwrote every baseline file it can reach", async () => {
    const { result, deploy } = await runReviewJob({ agentSource: AGENT_THAT_MOVES_THE_BASELINE });
    expect(result.status).toBe("failed");
    expect(result.reason).toBe("schema not backward compatible");
    expect(result.detail).toContain("reminders.item.notes was removed");
    expect(deploy.deployCalls).toEqual([]);
    const baselinePath = join(result.logFolder, "manifest-baseline.json");
    expect(statSync(baselinePath).mode & 0o222).toBe(0);
    expect(readFileSync(baselinePath, "utf8")).toBe(remindersBundle().manifestText);
  });
});

describe("7: the validator comes from the checkout the runner deploys from", () => {
  it("checks the records with the checkout's validator", async () => {
    const { result, deploy } = await runReviewJob({
      agentSource: AGENT_THAT_FIXES_TITLE,
      records: [{ key: "reminder:1", value: { $type: "reminders.item", title: "Fine by the repo's rules" } }],
      prepareCheckout: function useStrictValidator(checkout: string) {
        appendFileSync(join(checkout, "shell", "sdk", "record-schema.js"), '\nMidasRecordSchema.checkRecord = function refuseEverything() { return "the checkout validator says no"; };\n');
      },
    });
    expect(result.status).toBe("failed");
    expect(result.reason).toBe("records do not fit schema");
    expect(result.detail).toContain("the checkout validator says no");
    expect(deploy.deployCalls).toEqual([]);
  });

  it("fails as a runner error, before the agent, when the checkout has no validator or no store helper", async () => {
    for (const missing of [join("shell", "sdk", "record-schema.js"), join("shell", "sdk", "midas-store.js")]) {
      const { result, deploy } = await runReviewJob({
        agentSource: AGENT_THAT_RECORDS_IT_RAN,
        prepareCheckout: function removeFile(checkout: string) {
          rmSync(join(checkout, missing));
        },
      });
      expect(result.status).toBe("failed");
      expect(result.reason).toBe("runner error");
      expect(result.detail).toContain(missing);
      expect(deploy.deployCalls).toEqual([]);
      if (result.jobFolder !== null) {
        expect(existsSync(join(result.jobFolder, "agent-ran.txt"))).toBe(false);
      }
      await openBackend?.close();
      openBackend = null;
    }
  });
});

describe("10: a copy without types is refused before the agent", () => {
  it("fails as copy has no schema, never runs the agent, never reads records, never deploys", async () => {
    const manifest = manifestOf("reminders");
    delete manifest.types;
    const { result, deploy, backendServer } = await runReviewJob({ agentSource: AGENT_THAT_RECORDS_IT_RAN, manifestText: JSON.stringify(manifest) });
    expect(result.status).toBe("failed");
    expect(result.reason).toBe(NO_SCHEMA_REASON);
    expect(NO_SCHEMA_REASON).toBe("copy has no schema");
    expect(result.detail).toContain("needs the schema pass first");
    expect(result.jobFolder).toBeNull();
    expect(backendServer.recordRequests).toBe(0);
    expect(deploy.deployCalls).toEqual([]);
    expect(backendServer.statuses[backendServer.statuses.length - 1]).toMatchObject({ status: "failed", reason: "copy has no schema" });
  });
});

// ---- the records check's own numbers ------------------------------------------------------------

describe("9: a failure names the key as it is stored", () => {
  const remindersManifest = manifestOf("reminders");

  it("names reminder:9 alone, with no stored-as key", () => {
    const result = checkUserRecords({ sidekickId: "reminders", records: [{ key: "reminder:9", value: { $type: "reminders.item", title: "" } }], manifest: remindersManifest });
    expect(result.failures).toHaveLength(1);
    expect(Object.keys(result.failures[0])).toEqual(["key", "problem"]);
    const detail = recordFailureDetail(result.failures);
    expect(detail).toContain("reminder:9: ");
    expect(detail).not.toContain("stored as");
  });
});

// ---- 8: care prompt -----------------------------------------------------------------------------

describe("8: care-reminders' prompt matches its manifest", () => {
  it("describes everyHours as a field of care.item, not part of repeat", () => {
    const template = readRepoText("runner/agents/care-reminders.md");
    expect(template).not.toContain("`repeat` with `everyHours`");
    expect(template).toContain("`everyHours` (2, 3 or 4), a field of its own next to `repeat`");
    const careSchema = manifestOf("care-reminders").types["reminder:"].schema;
    expect(careSchema.properties.everyHours).toBeDefined();
    expect(careSchema.$defs.repeat.properties.everyHours).toBeUndefined();
  });
});

// ---- 6: backend and publish environment ---------------------------------------------------------

describe("6: the runner refuses to start when its backend and publish environment differ", () => {
  const stagingUrl = `https://${BACKEND_HOSTS.staging}`;
  const liveUrl = `https://${BACKEND_HOSTS.live}`;

  it("starts with matching pairs", () => {
    expect(startupSettings({ MIDAS_BACKEND_URL: stagingUrl, MIDAS_RUNNER_TOKEN: "t", MIDAS_RUNNER_ENV: "staging" }).deployEnvironment).toBe("staging");
    expect(startupSettings({ MIDAS_BACKEND_URL: `${liveUrl}/`, MIDAS_RUNNER_TOKEN: "t", MIDAS_RUNNER_ENV: "live" }).deployEnvironment).toBe("live");
    expect(startupSettings({ MIDAS_BACKEND_URL: liveUrl, MIDAS_RUNNER_TOKEN: "t" }).deployEnvironment).toBe("live");
  });

  it("refuses a staging URL with live, a live URL with staging, and any other host", () => {
    expect(() => startupSettings({ MIDAS_BACKEND_URL: stagingUrl, MIDAS_RUNNER_TOKEN: "t", MIDAS_RUNNER_ENV: "live" })).toThrow(/staging Worker but MIDAS_RUNNER_ENV is live/);
    expect(() => startupSettings({ MIDAS_BACKEND_URL: stagingUrl, MIDAS_RUNNER_TOKEN: "t" })).toThrow(/staging Worker but MIDAS_RUNNER_ENV is live/);
    expect(() => startupSettings({ MIDAS_BACKEND_URL: liveUrl, MIDAS_RUNNER_TOKEN: "t", MIDAS_RUNNER_ENV: "staging" })).toThrow(/live Worker but MIDAS_RUNNER_ENV is staging/);
    expect(() => checkBackendMatchesEnvironment({ backendUrl: "http://127.0.0.1:8787", deployEnvironment: "live" })).toThrow(/neither the live nor the staging Worker/);
  });

  it("is what both runner commands start with", () => {
    for (const binary of ["runner/bin/runner.mjs", "runner/bin/run-once.mjs"]) {
      const source = readRepoText(binary);
      expect(source).toContain("const settings = startupSettings();");
      expect(source).not.toContain("settingsFromEnv");
    }
  });
});

// ---- 3: the records route -----------------------------------------------------------------------

const ROUTE_RUNNER_TOKEN = "runner-secret-for-review";

function makeEnv() {
  return { DB: makeMigratedD1(), BUNDLES: makeFakeR2(), REPAIR_RUNNER_TOKEN: ROUTE_RUNNER_TOKEN };
}

type RouteEnv = ReturnType<typeof makeEnv>;

let routeOpCounter = 0;

function addReporter(env: RouteEnv): string {
  const token = "token-reporter";
  const tokenHash = createHash("sha256").update(token).digest("hex");
  env.DB.execute("INSERT INTO users (id, name, created_at) VALUES ('reporter', 'reporter', 'now')");
  env.DB.execute("INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, 'reporter', 'now', ?)", tokenHash, Date.now() + 3_600_000);
  env.DB.execute("INSERT INTO assignments (user_id, sidekick_id, assigned_at) VALUES ('reporter', 'reminders', 'now')");
  return token;
}

function addOp(env: RouteEnv, key: string, value: unknown) {
  routeOpCounter += 1;
  const deleted = value === null ? 1 : 0;
  const valueText = value === null ? null : JSON.stringify(value);
  env.DB.execute(
    "INSERT INTO ops (op_id, user_id, sidekick_id, key, value, deleted, client_time, received_at) VALUES (?, 'reporter', 'reminders', ?, ?, ?, 'now', 'now')",
    `review-op-${routeOpCounter}`,
    key,
    valueText,
    deleted,
  );
}

async function fileReport(env: RouteEnv, token: string): Promise<string> {
  const form = new FormData();
  form.set("sidekickId", "reminders");
  form.set("kind", "change");
  form.set("transcript", "x");
  form.set("bundleVersion", "v1");
  const response = await app.request("/repairs", { method: "POST", headers: { Authorization: `Bearer ${token}` }, body: form }, env);
  expect(response.status).toBe(201);
  const reply = (await response.json()) as { id: string };
  return reply.id;
}

function getRecords(env: RouteEnv, reportId: string) {
  return app.request(`/repairs/${reportId}/records`, { headers: { Authorization: `Runner ${ROUTE_RUNNER_TOKEN}` } }, env);
}

describe("3: the records route", () => {
  it("returns a key that was deleted and then written again, with its newest value", async () => {
    const env = makeEnv();
    const token = addReporter(env);
    addOp(env, "reminder:1", { $type: "reminders.item", title: "First" });
    addOp(env, "reminder:1", null);
    addOp(env, "reminder:1", { $type: "reminders.item", title: "Written again" });
    addOp(env, "reminder:2", { $type: "reminders.item", title: "Gone" });
    addOp(env, "reminder:2", null);
    const reportId = await fileReport(env, token);
    const response = await getRecords(env, reportId);
    expect(response.status).toBe(200);
    const reply = (await response.json()) as { records: Array<{ key: string; value: { title: string } }> };
    expect(reply.records).toEqual([{ key: "reminder:1", value: { $type: "reminders.item", title: "Written again" } }]);
  });

  it("refuses with 413 when the live records are larger than the cap, counting only the latest values", async () => {
    const env = makeEnv();
    const token = addReporter(env);
    const bigText = "x".repeat(1024 * 1024);
    // Many old versions of one key: only the latest counts, so this stays under the cap.
    for (let version = 0; version < 6; version += 1) {
      addOp(env, "reminder:big", { $type: "reminders.item", title: "Big", notes: `${version}${bigText}` });
    }
    const reportId = await fileReport(env, token);
    const underCap = await getRecords(env, reportId);
    expect(underCap.status).toBe(200);

    const recordCount = Math.floor(MAX_REPORT_RECORD_BYTES / bigText.length) + 1;
    for (let index = 0; index < recordCount; index += 1) {
      addOp(env, `reminder:${index}`, { $type: "reminders.item", title: "Big", notes: bigText });
    }
    const overCap = await getRecords(env, reportId);
    expect(overCap.status).toBe(413);
    const reply = (await overCap.json()) as { error: string; bytes: number; limit: number };
    expect(reply.error).toBe("records too large");
    expect(reply.limit).toBe(MAX_REPORT_RECORD_BYTES);
    expect(reply.bytes).toBeGreaterThan(MAX_REPORT_RECORD_BYTES);
  });

  it("reads the latest op per key with one GROUP BY, no per-key subquery", () => {
    const env = makeEnv();
    for (const sql of [REPORT_RECORDS_SQL, REPORT_RECORDS_SIZE_SQL]) {
      const plan = env.DB.query(`EXPLAIN QUERY PLAN ${sql}`, "reporter", "reminders") as Array<{ detail: string }>;
      const details = plan.map(function detailOf(row) {
        return row.detail;
      });
      expect(details.join("\n")).not.toMatch(/CORRELATED/);
      expect(sql).toContain("GROUP BY key");
    }
  });

  it("the runner's client names the cap in its error", async () => {
    async function fakeFetch() {
      return new Response(JSON.stringify({ error: "records too large", count: 3, bytes: 5_000_000, limit: 4_194_304 }), { status: 413 });
    }
    const backend = createBackendClient({ baseUrl: "https://example.invalid", token: "t", fetchImplementation: fakeFetch });
    await expect(backend.listRecords("rep-1")).rejects.toThrow("records failed: 413 records too large (5000000 bytes, limit 4194304)");
  });
});

// ---- 1: the copies planner ----------------------------------------------------------------------

describe("1: the copies planner publishes only a copy that passed the schema and records checks", () => {
  const baseHtml = readRepoText("sidekicks/reminders/index.html");
  const baseManifestText = readRepoText("sidekicks/reminders/manifest.json");
  const baseManifest = JSON.parse(baseManifestText);
  const helper = currentStoreHelper();
  const base = { pointer: { version: "base-2" }, manifest: baseManifest };
  const baseContentHashes = { "base-2": bundleContentHash(baseHtml, baseManifestText) };
  const oldHelper = [
    "// Midas local store for Sidekicks. Paste this into the Sidekick bundle's inline script (its",
    "var store = (function createMidasStore() {",
    "  return { set: setRecord, get: getRecord, delete: deleteRecord, query: queryRecords };",
    "})();",
  ].join("\n");
  const oldPage = baseHtml.replace(helper, oldHelper).replace("<title>Reminders</title>", "<title>My Reminders</title>");
  const repairedPointer = { version: "u-1", baseVersion: "base-2", contentHash: "repaired" };

  function planWith({ manifestText = baseManifestText, records }: { manifestText?: string; records: StoredRecord[] | null }) {
    return planUserCopy({ sidekickId: "reminders", envName: "live", copy: { userId: "user-1", pointer: repairedPointer, html: oldPage, manifestText }, base, baseContentHashes, helperText: helper, records });
  }

  function deployActions(actions: string[]): string[] {
    return actions.filter(function isDeploy(action) {
      return action.includes("--dir");
    });
  }

  it("prints the --dir deploy for an older helper only when every record fits", () => {
    const plan = planWith({ records: [{ key: "reminder:1", value: { $type: "reminders.item", title: "Fine" } }] });
    expect(plan.upgraded).not.toBeNull();
    expect(plan.upgraded.html).toContain(helper);
    expect(plan.actions).toContain("checked: schema unchanged, every literal write declared, 1 of the user's records fit");
    expect(deployActions(plan.actions)).toEqual(["node scripts/deploy-sidekick.mjs reminders --env live --user user-1 --dir <out>/reminders/user-1"]);
  });

  it("prints no deploy when a record does not fit or the records were not read", () => {
    const misfit = planWith({ records: [{ key: "reminder:1", value: { $type: "reminders.item", title: "" } }] });
    expect(misfit.upgraded).toBeNull();
    expect(deployActions(misfit.actions)).toEqual([]);
    expect(misfit.actions[0]).toMatch(/^not published: 1 of the user's records do not fit the new schema: reminder:1/);
    const unread = planWith({ records: null });
    expect(unread.upgraded).toBeNull();
    expect(deployActions(unread.actions)).toEqual([]);
  });

  it("never gives a copy without types the base's types; it prints the user's records against them for the schema pass", () => {
    const manifest = JSON.parse(baseManifestText);
    delete manifest.types;
    const records = [{ key: "reminder:1", value: { $type: "reminders.item", title: "Fits", at: "2026-10-20T09:00:00.000Z" } }, { key: "reminder:2", value: { $type: "reminders.item", title: "" } }];
    const plan = planWith({ manifestText: JSON.stringify(manifest), records });
    expect(plan.upgraded).toBeNull();
    expect(deployActions(plan.actions)).toEqual([]);
    expect(plan.actions[0]).toMatch(/^needs the schema pass first/);
    expect(plan.actions[1]).toMatch(/^the user's records against the base's types, for that pass: 1 of the user's records do not fit the new schema: reminder:2/);
  });
});
