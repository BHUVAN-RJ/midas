// The runner end to end on the unified data rules (founder, 2026-10-19; docs/briefs/repair-data-2026-10-19.md):
// a repair that only adds to the schema and fits the reporter's records goes live; one that breaks
// the schema, writes an undeclared record type, does not fit a record, or cannot read the records
// ends failed and is never deployed; a copy with an older store helper gets today's before the agent.
import { createServer, type Server } from "node:http";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createBackendClient } from "../../runner/lib/backend.mjs";
import { runJob } from "../../runner/lib/run-job.mjs";
import { currentStoreHelper } from "../scripts/store-helper.mjs";
import {
  AGENT_THAT_FIXES_TITLE,
  RUNNER_TOKEN,
  fakeDeployThatLands,
  fakeFetchWithoutStoredTests,
  makeScratch,
  remindersBundle,
  writeStubAgent,
} from "./helpers/runner-fixture";

const JOB_ROW = { id: "rep-data-1", user_id: "user-42", sidekick_id: "reminders", bundle_version: "v-copy", kind: "change", transcript: "keep typing on the next line" };

type StoredRecord = { key: string; value: unknown };
type DataBackend = { baseUrl: string; statuses: Array<Record<string, unknown>>; recordRequests: string[]; close: () => Promise<void> };

const GOOD_RECORDS: StoredRecord[] = [
  { key: "reminder:1", value: { $type: "reminders.item", title: "Call mom", at: "2026-10-20T09:00:00.000Z", notes: "about Sunday" } },
  { key: "list:home", value: { $type: "reminders.list", name: "Home" } },
];

// One job, its assets, status posts, and GET /repairs/<id>/records (records null: that route 404s).
async function startDataBackend(assets: Record<string, string | Buffer>, records: StoredRecord[] | null): Promise<DataBackend> {
  const statuses: Array<Record<string, unknown>> = [];
  const recordRequests: string[] = [];
  let pendingJob: typeof JOB_ROW | null = JOB_ROW;
  const server: Server = createServer(function answerRequest(request, response) {
    if (request.headers.authorization !== `Runner ${RUNNER_TOKEN}`) {
      response.writeHead(401);
      response.end();
      return;
    }
    const url = request.url ?? "";
    if (request.method === "POST" && url === "/repairs/jobs/claim") {
      const body = pendingJob === null ? "" : JSON.stringify(pendingJob);
      response.writeHead(pendingJob === null ? 204 : 200, { "content-type": "application/json" });
      pendingJob = null;
      response.end(body);
      return;
    }
    const recordsMatch = /^\/repairs\/([^/]+)\/records$/.exec(url);
    if (request.method === "GET" && recordsMatch !== null) {
      recordRequests.push(decodeURIComponent(recordsMatch[1]));
      if (records === null) {
        response.writeHead(404);
        response.end();
        return;
      }
      response.writeHead(200, { "content-type": "application/json" });
      response.end(JSON.stringify({ userId: JOB_ROW.user_id, sidekickId: JOB_ROW.sidekick_id, records }));
      return;
    }
    const assetMatch = /^\/repairs\/([^/]+)\/assets\/(.+)$/.exec(url);
    if (request.method === "GET" && assetMatch !== null) {
      const asset = assets[decodeURIComponent(assetMatch[2])];
      response.writeHead(asset === undefined ? 404 : 200);
      response.end(asset);
      return;
    }
    if (request.method === "POST" && /^\/repairs\/[^/]+\/status$/.test(url)) {
      let body = "";
      request.on("data", function collectChunk(chunk) {
        body += chunk;
      });
      request.on("end", function recordStatus() {
        statuses.push(JSON.parse(body));
        response.writeHead(200, { "content-type": "application/json" });
        response.end("{}");
      });
      return;
    }
    response.writeHead(404);
    response.end();
  });
  await new Promise<void>(function listen(resolve) {
    server.listen(0, "127.0.0.1", resolve);
  });
  const address = server.address();
  const port = typeof address === "object" && address !== null ? address.port : 0;
  return {
    baseUrl: `http://127.0.0.1:${port}`,
    statuses,
    recordRequests,
    close: function closeServer() {
      return new Promise<void>(function waitForClose(resolve) {
        server.close(function closed() {
          resolve();
        });
      });
    },
  };
}

function assetsWithPage(html: string): Record<string, string | Buffer> {
  return { "bundle.html": html, "bundle.manifest.json": remindersBundle().manifestText, "bundle.tools.js": remindersBundle().toolsText };
}

let openBackend: DataBackend | null = null;

afterEach(async () => {
  if (openBackend !== null) {
    await openBackend.close();
    openBackend = null;
  }
});

async function runDataJob({ agentSource, records = GOOD_RECORDS, html = remindersBundle().html }: { agentSource: string; records?: StoredRecord[] | null; html?: string }) {
  const { scratch, settings } = makeScratch();
  const backendServer = await startDataBackend(assetsWithPage(html), records);
  openBackend = backendServer;
  const backend = createBackendClient({ baseUrl: backendServer.baseUrl, token: RUNNER_TOKEN });
  const job = await backend.claimJob();
  const deploy = fakeDeployThatLands();
  const testRuns: string[] = [];
  const result = await runJob(job, {
    backend,
    settings,
    agentCommand: process.execPath,
    agentArgs: [writeStubAgent(scratch, agentSource)],
    runFetch: fakeFetchWithoutStoredTests().runFetch,
    runTests: async function stubTests({ sidekickId }: { sidekickId: string }) {
      testRuns.push(sidekickId);
      return { ok: true, output: "all passed" };
    },
    runDeploy: deploy.runDeploy,
    readPointer: deploy.readPointer,
    notify: async function ignoreNotification() {},
  });
  const statusNames = backendServer.statuses.map(function nameOfStatus(status: Record<string, unknown>) {
    return status.status;
  });
  return { result, backendServer, deploy, testRuns, statusNames };
}

// Adds an optional "priority" field to reminder: in the manifest and shows it on the page.
const AGENT_THAT_ADDS_AN_OPTIONAL_FIELD = `
import { readFileSync, writeFileSync } from "node:fs";
const manifest = JSON.parse(readFileSync("sidekick/manifest.json", "utf8"));
manifest.types["reminder:"].schema.properties.priority = { type: "string", enum: ["low", "high"] };
writeFileSync("sidekick/manifest.json", JSON.stringify(manifest, null, 2));
const page = readFileSync("sidekick/index.html", "utf8");
writeFileSync("sidekick/index.html", page.replace("<title>Reminders</title>", "<title>Reminders · priority</title>"));
writeFileSync("outcome.json", JSON.stringify({ result: "fixed", summary: "Added an optional priority." }));
`;

// Renames notes to memo in the schema: a breaking change.
const AGENT_THAT_RENAMES_A_FIELD = `
import { readFileSync, writeFileSync } from "node:fs";
const manifest = JSON.parse(readFileSync("sidekick/manifest.json", "utf8"));
const properties = manifest.types["reminder:"].schema.properties;
properties.memo = properties.notes;
delete properties.notes;
writeFileSync("sidekick/manifest.json", JSON.stringify(manifest, null, 2));
const page = readFileSync("sidekick/index.html", "utf8");
writeFileSync("sidekick/index.html", page.replace("<title>Reminders</title>", "<title>Reminders · memo</title>"));
writeFileSync("outcome.json", JSON.stringify({ result: "fixed", summary: "Renamed notes to memo." }));
`;

// Writes a new tag: record type without declaring it in the manifest.
const AGENT_THAT_WRITES_AN_UNDECLARED_TYPE = `
import { readFileSync, writeFileSync } from "node:fs";
const page = readFileSync("sidekick/index.html", "utf8");
const lastScriptEnd = page.lastIndexOf("</script>");
const added = "\\nfunction saveTag(id, name) { return store.set('tag:' + id, { name: name }); }\\n";
writeFileSync("sidekick/index.html", page.slice(0, lastScriptEnd) + added + page.slice(lastScriptEnd));
writeFileSync("outcome.json", JSON.stringify({ result: "fixed", summary: "Added tags." }));
`;

describe("runJob on the unified data rules", () => {
  it("publishes a repair that only adds an optional field and fits every record the reporter has", async () => {
    const { result, backendServer, deploy, statusNames } = await runDataJob({ agentSource: AGENT_THAT_ADDS_AN_OPTIONAL_FIELD });
    expect(result.status).toBe("deployed_live");
    expect(statusNames).toEqual(["running", "fix_ready", "deployed_live"]);
    expect(backendServer.recordRequests).toEqual([JOB_ROW.id]);
    expect(deploy.deployCalls).toHaveLength(1);
    const recordsCheck = JSON.parse(readFileSync(join(result.logFolder, "records-check.json"), "utf8"));
    expect(recordsCheck).toEqual({ checked: 2, failures: [] });
    const summary = readFileSync(join(result.logFolder, "summary.md"), "utf8");
    expect(summary).toContain("User's records: 2 checked against the new schema, all fit");
  });

  it("refuses a breaking schema change before the check: failed, never fix_ready, never deployed", async () => {
    const { result, deploy, testRuns, statusNames, backendServer } = await runDataJob({ agentSource: AGENT_THAT_RENAMES_A_FIELD });
    expect(result.status).toBe("failed");
    expect(result.reason).toBe("schema not backward compatible");
    expect(result.detail).toContain("reminders.item.notes was removed");
    expect(statusNames).toEqual(["running", "failed"]);
    expect(backendServer.statuses[1]).toMatchObject({ status: "failed", reason: "schema not backward compatible" });
    expect(testRuns).toEqual([]);
    expect(deploy.deployCalls).toEqual([]);
  });

  it("refuses a page that writes a record type the manifest does not declare", async () => {
    const { result, deploy, statusNames } = await runDataJob({ agentSource: AGENT_THAT_WRITES_AN_UNDECLARED_TYPE });
    expect(result.status).toBe("failed");
    expect(result.reason).toBe("schema missing");
    expect(result.detail).toContain("tag:");
    expect(statusNames).toEqual(["running", "failed"]);
    expect(deploy.deployCalls).toEqual([]);
  });

  it("does not publish when one of the reporter's records does not fit the new schema", async () => {
    const records = [...GOOD_RECORDS, { key: "reminder:2", value: { $type: "reminders.item", title: "" } }];
    const { result, deploy, testRuns, statusNames } = await runDataJob({ agentSource: AGENT_THAT_FIXES_TITLE, records });
    expect(result.status).toBe("failed");
    expect(result.reason).toBe("records do not fit schema");
    expect(result.detail).toContain("reminder:2");
    // Records are checked before the shield and the copy's tests (shield wiring, 2026-11-13): a repair the person's records refuse is not tested further.
    expect(testRuns).toEqual([]);
    expect(statusNames).toEqual(["running", "failed"]);
    expect(deploy.deployCalls).toEqual([]);
  });

  it("does not publish when the reporter's records cannot be read", async () => {
    const { result, deploy, statusNames } = await runDataJob({ agentSource: AGENT_THAT_FIXES_TITLE, records: null });
    expect(result.status).toBe("failed");
    expect(result.reason).toBe("records unreadable");
    expect(result.detail).toContain("404");
    expect(statusNames).toEqual(["running", "failed"]);
    expect(deploy.deployCalls).toEqual([]);
  });

  it("does not publish when a record lacks its $type: records are checked as stored", async () => {
    const records = [{ key: "reminder:8", value: { title: "Dated", at: "2026-10-20T09:00:00.000Z" } }];
    const { result, deploy } = await runDataJob({ agentSource: AGENT_THAT_FIXES_TITLE, records });
    expect(result.status).toBe("failed");
    expect(result.reason).toBe("records do not fit schema");
    expect(result.detail).toContain('reminder:8: reminders.item.$type must be "reminders.item"');
    expect(deploy.deployCalls).toEqual([]);
  });

  it("gives a copy with an older store helper today's helper before the agent, and says so in the summary", async () => {
    const helper = currentStoreHelper();
    const oldHelper = [
      "// Midas local store for Sidekicks. Paste this into the Sidekick bundle's inline script (its",
      "var store = (function createMidasStore() {",
      "  return { set: setRecord, get: getRecord, delete: deleteRecord, query: queryRecords };",
      "})();",
    ].join("\n");
    const basePage = remindersBundle().html;
    expect(basePage).toContain(helper);
    const oldPage = basePage.replace(helper, oldHelper);
    const { result } = await runDataJob({ agentSource: AGENT_THAT_FIXES_TITLE, html: oldPage });
    expect(result.status).toBe("deployed_live");
    expect(readFileSync(join(result.logFolder, "store-helper.txt"), "utf8").trim()).toBe("refreshed");
    const before = readFileSync(join(result.logFolder, "before", "index.html"), "utf8");
    expect(before).toContain(helper);
    expect(before).not.toContain("return { set: setRecord, get: getRecord, delete: deleteRecord, query: queryRecords };");
    const diff = readFileSync(join(result.logFolder, "diff.patch"), "utf8");
    expect(diff).not.toContain("createMidasStore");
    const summary = readFileSync(join(result.logFolder, "summary.md"), "utf8");
    expect(summary).toContain("Store helper: an older copy in the page was replaced");
    expect(existsSync(join(result.jobFolder, "sidekick", "index.html"))).toBe(true);
    expect(readFileSync(join(result.jobFolder, "sidekick", "index.html"), "utf8")).toContain(helper);
  });
});
