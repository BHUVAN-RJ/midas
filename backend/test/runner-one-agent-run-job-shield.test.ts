// The shield runs on every repair (founder D3, 2026-11-13; W1 hand-back "What the lead must add",
// wired by W4 on the lead's request): runJob reads and freezes the person's records before the
// agent, gives the agent's check tool the copy as it was and the records, runs checkRepair (gate,
// shield, copy tests) and writes shield.txt. A tool whose answer changes without the agent naming
// it in outcome.json "changedTools" is refused before fix_ready; named, it goes live.
import { cpSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createBackendClient } from "../../runner/lib/backend.mjs";
import { runJob } from "../../runner/lib/run-job.mjs";
import {
  REPO_ROOT,
  RUNNER_TOKEN,
  fakeDeployThatLands,
  fakeFetchWithoutStoredTests,
  makeScratch,
  standardAssets,
  startFakeBackend,
  writeStubAgent,
  type FakeBackend,
} from "./helpers/runner-fixture";

const JOB_ROW = {
  id: "rep-shield-1",
  user_id: "user-77",
  sidekick_id: "reminders",
  bundle_version: "20261011T065908559Z-1064a312",
  kind: "change",
  transcript: "make add say something else",
};

// The agent changes what reminders.add answers. changedTools decides whether it says so; it also
// reports the two shield paths its environment got, so the test can see them.
function agentThatChangesAdd(changedTools: string[] | null): string {
  const outcomeExtra = changedTools === null ? "" : `, changedTools: ${JSON.stringify(changedTools)}`;
  return `
import { appendFileSync, readFileSync, writeFileSync } from "node:fs";
const page = readFileSync("sidekick/index.html", "utf8");
writeFileSync("sidekick/index.html", page.replace("<title>Reminders</title>", "<title>My Reminders</title>"));
appendFileSync("sidekick/tools.js", "\\nMidasSidekickTools.handlers.add = function changedAdd() { return { ops: [], result: { text: 'Added it' } }; };\\n");
const shieldInputs = { before: process.env.MIDAS_JOB_BEFORE_FOLDER ?? null, records: process.env.MIDAS_JOB_RECORDS ?? null };
writeFileSync("outcome.json", JSON.stringify({ result: "fixed", summary: "Add says Added it. " + JSON.stringify(shieldInputs)${outcomeExtra} }));
`;
}

// Stands in for WebKit (this checks the runner, not drawing; the shield's own tests open WebKit)
async function cleanPages({ actions }: { actions: string[] }) {
  const report = { errors: [], writes: [], written: {}, visibleElements: 5, textLength: 5, action: null };
  const steps: Array<Record<string, unknown>> = [{ name: "open", action: null, report }, { name: "widget", action: null, report }];
  for (const action of actions) {
    steps.push({ name: `view:${action}`, action: null, report });
  }
  return steps;
}

let openBackend: FakeBackend | null = null;

afterEach(async () => {
  if (openBackend !== null) {
    await openBackend.close();
    openBackend = null;
  }
});

async function runShieldJob(agentSource: string) {
  const { scratch, checkout, settings } = makeScratch();
  // The shield and the runner library it imports, loaded from the checkout like in production.
  cpSync(join(REPO_ROOT, "runner", "core-checks"), join(checkout, "runner", "core-checks"), { recursive: true, force: true });
  cpSync(join(REPO_ROOT, "runner", "lib"), join(checkout, "runner", "lib"), { recursive: true, force: true });
  const backendServer = await startFakeBackend(JOB_ROW, standardAssets());
  openBackend = backendServer;
  const backend = createBackendClient({ baseUrl: backendServer.baseUrl, token: RUNNER_TOKEN });
  const job = await backend.claimJob();
  const deploy = fakeDeployThatLands();
  const result = await runJob(job, {
    backend,
    settings,
    agentCommand: process.execPath,
    agentArgs: [writeStubAgent(scratch, agentSource)],
    runFetch: fakeFetchWithoutStoredTests().runFetch,
    runTests: async () => ({ ok: true, output: "1 passed" }),
    runDeploy: deploy.runDeploy,
    readPointer: deploy.readPointer,
    notify: async () => {},
    openPageImplementation: cleanPages,
  });
  return { result, backendServer, deploy };
}

describe("runJob runs the shield on every repair", () => {
  it("refuses a tool answer the agent did not name, before fix_ready and before any deploy", async () => {
    const { result, backendServer, deploy } = await runShieldJob(agentThatChangesAdd(null));
    expect(result.status).toBe("failed");
    expect(result.reason).toBe("check failed");
    expect(result.detail).toContain("shield tools");
    expect(result.detail).toContain("reminders.add");
    expect(backendServer.statuses.map((status) => status.status)).toEqual(["running", "failed"]);
    expect(deploy.deployCalls).toEqual([]);
    const shieldReport = readFileSync(join(result.logFolder, "shield.txt"), "utf8");
    expect(shieldReport).toContain("✕ tools");
    expect(shieldReport).toContain("✓ records-fit");
  });

  it("publishes the same change when outcome.json names the tool, with the shield report kept", async () => {
    const { result } = await runShieldJob(agentThatChangesAdd(["reminders.add"]));
    expect(result.status).toBe("deployed_live");
    const shieldReport = readFileSync(join(result.logFolder, "shield.txt"), "utf8");
    expect(shieldReport).toContain("✓ tools");
    expect(shieldReport).not.toContain("✕");
  });

  it("freezes the person's records before the agent and gives the agent's check tool both inputs", async () => {
    const { result } = await runShieldJob(agentThatChangesAdd(["reminders.add"]));
    const recordsPath = join(result.logFolder, "records.json");
    expect(Array.isArray(JSON.parse(readFileSync(recordsPath, "utf8")))).toBe(true);
    // Read-only: nothing after the read changes what the shield compares.
    expect(statSync(recordsPath).mode & 0o222).toBe(0);
    const outcome = JSON.parse(readFileSync(join(result.jobFolder, "outcome.json"), "utf8"));
    const shieldInputs = JSON.parse(outcome.summary.slice(outcome.summary.indexOf("{")));
    expect(shieldInputs).toEqual({ before: join(result.logFolder, "before"), records: recordsPath });
  });
});
