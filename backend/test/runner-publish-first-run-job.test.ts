// runJob in publish-first mode (founder, 2026-11-13; docs/briefs/repair-lanes.md W7): after the
// agent, the new version is uploaded through the Worker while the gate, the shield's fast part and
// the copy's tests run; the pointer flips when they pass and the person is told; the slow part runs
// after and rolls the copy back when it fails. The person's notes line goes out inside the version.
// No wrangler deploy is run on this path.
import { cpSync, existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createBackendClient } from "../../runner/lib/backend.mjs";
import { runJob } from "../../runner/lib/run-job.mjs";
import { plannedSteps } from "../../runner/core-checks/page-open.mjs";
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
  id: "rep-publish-first-1",
  user_id: "user-77",
  sidekick_id: "reminders",
  bundle_version: "20261011T065908559Z-1064a312",
  kind: "change",
  transcript: "call it My Reminders",
};

// Renames the page title (the new page is told apart by it); changedTools lists nothing
const AGENT_THAT_RENAMES = `
import { readFileSync, writeFileSync } from "node:fs";
const page = readFileSync("sidekick/index.html", "utf8");
writeFileSync("sidekick/index.html", page.replace("<title>Reminders</title>", "<title>My Reminders</title>"));
writeFileSync("outcome.json", JSON.stringify({ result: "fixed", summary: "The title says My Reminders.", note: "Title is My Reminders" }));
`;

// Also changes what reminders.add answers without naming it: the fast part's tools check refuses it
const AGENT_THAT_CHANGES_ADD = `
import { appendFileSync, readFileSync, writeFileSync } from "node:fs";
const page = readFileSync("sidekick/index.html", "utf8");
writeFileSync("sidekick/index.html", page.replace("<title>Reminders</title>", "<title>My Reminders</title>"));
appendFileSync("sidekick/tools.js", "\\nMidasSidekickTools.handlers.add = function changedAdd() { return { ops: [], result: { text: 'Added it' } }; };\\n");
writeFileSync("outcome.json", JSON.stringify({ result: "fixed", summary: "Add says Added it." }));
`;

// A stand-in for WebKit that honours the kinds of step; with breakTaps, the new page (its title is
// "My Reminders") throws after every tap, which only the slow part can see
function makePages(breakTaps: boolean) {
  async function openPageStandIn({ html, actions, kinds, records }: { html: string; actions: string[]; kinds: string[]; records: unknown[] }) {
    const steps = plannedSteps({ records, actions, kinds });
    const isNewPage = html.includes("<title>My Reminders</title>");
    return steps.map(function stepReport(step: { name: string; action: string | null }) {
      const broken = breakTaps && isNewPage && step.action !== null;
      const report = { errors: broken ? ["uncaught: Error: tap broke"] : [], writes: [], written: {}, visibleElements: 5, textLength: 5, action: step.action === null ? null : { found: true } };
      return { name: step.name, action: step.action, report };
    });
  }
  return openPageStandIn;
}

// The Worker's publish routes, as the runner calls them, kept in memory: what was uploaded, the
// person's pointer, and every call in order
function makePublishWorker() {
  const calls: string[] = [];
  const uploads: Record<string, Array<{ name: string; body: string }>> = {};
  const state = { pointerVersion: "previous-version" as string | null };
  async function publishFiles(_reportId: string, { version, files }: { version: string; files: Array<{ name: string; body: string }> }) {
    calls.push("files");
    uploads[version] = files;
    return { version, stored: files.length };
  }
  async function flipPointer(_reportId: string, { version }: { version: string }) {
    calls.push("pointer");
    const previousVersion = state.pointerVersion;
    state.pointerVersion = version;
    return { version, previousVersion };
  }
  async function rollBackPointer(_reportId: string, { version, reason }: { version: string; reason: string }) {
    calls.push(`rollback ${version === state.pointerVersion ? "of the live version" : "of another version"}: ${reason.slice(0, 40)}`);
    state.pointerVersion = "previous-version";
    return { rolledBack: true, version: "previous-version" };
  }
  return { calls, uploads, state, publishFiles, flipPointer, rollBackPointer };
}

let openBackend: FakeBackend | null = null;

afterEach(async () => {
  if (openBackend !== null) {
    await openBackend.close();
    openBackend = null;
  }
});

async function runPublishFirstJob(agentSource: string, breakTaps: boolean) {
  const { scratch, checkout, settings } = makeScratch();
  cpSync(join(REPO_ROOT, "runner", "core-checks"), join(checkout, "runner", "core-checks"), { recursive: true, force: true });
  cpSync(join(REPO_ROOT, "runner", "lib"), join(checkout, "runner", "lib"), { recursive: true, force: true });
  const backendServer = await startFakeBackend(JOB_ROW, standardAssets());
  openBackend = backendServer;
  const worker = makePublishWorker();
  const client = createBackendClient({ baseUrl: backendServer.baseUrl, token: RUNNER_TOKEN });
  const backend = { ...client, publishFiles: worker.publishFiles, flipPointer: worker.flipPointer, rollBackPointer: worker.rollBackPointer };
  const job = await backend.claimJob();
  const deploy = fakeDeployThatLands();
  const notifications: string[] = [];
  async function recordNotification({ title }: { title: string }) {
    notifications.push(title);
  }
  async function testsPass() {
    return { ok: true, output: "1 passed" };
  }
  const result = await runJob(job, {
    backend,
    settings: { ...settings, publishMode: "first" },
    agentCommand: process.execPath,
    agentArgs: [writeStubAgent(scratch, agentSource)],
    runFetch: fakeFetchWithoutStoredTests().runFetch,
    runTests: testsPass,
    runDeploy: deploy.runDeploy,
    readPointer: deploy.readPointer,
    notify: recordNotification,
    openPageImplementation: makePages(breakTaps),
  });
  const statuses = backendServer.statuses.map(function statusName(entry: { status: string }) {
    return entry.status;
  });
  return { result, backendServer, deploy, worker, statuses, notifications };
}

function timingNames(logFolder: string): string[] {
  const steps = JSON.parse(readFileSync(join(logFolder, "timings.json"), "utf8"));
  return steps.map(function stepName(step: { name: string }) {
    return step.name;
  });
}

describe("runJob, publish first", () => {
  it("publishes through the Worker, tells the person, then runs the slow part; no wrangler deploy", async () => {
    const { result, deploy, worker, statuses } = await runPublishFirstJob(AGENT_THAT_RENAMES, false);
    expect(result.status).toBe("deployed_live");
    expect(statuses).toEqual(["running", "fix_ready", "deployed_live"]);
    expect(worker.calls).toEqual(["files", "pointer"]);
    expect(worker.state.pointerVersion).toBe(result.version);
    expect(deploy.deployCalls).toEqual([]);
    const names = timingNames(result.logFolder);
    expect(names.indexOf("pointer flip")).toBeLessThan(names.indexOf("checks after publish"));
    expect(names.indexOf("status: live (the person is told)")).toBeLessThan(names.indexOf("checks after publish"));
    expect(existsSync(join(result.logFolder, "shield-after-publish.txt"))).toBe(true);
  });

  it("sends this person's notes line inside the published version", async () => {
    const { result, worker } = await runPublishFirstJob(AGENT_THAT_RENAMES, false);
    const files = worker.uploads[result.version];
    const notes = files.find(function isNotes(file: { name: string }) {
      return file.name.endsWith("PERSON_NOTES.md");
    });
    expect(notes?.body).toContain("Title is My Reminders");
  });

  it("rolls the person back at once when a slow check fails after the publish", async () => {
    const { result, worker, statuses, backendServer, notifications } = await runPublishFirstJob(AGENT_THAT_RENAMES, true);
    expect(result.status).toBe("failed");
    expect(result.reason).toBe("rolled back");
    expect(result.rolledBack).toBe(true);
    expect(result.detail).toContain("tap broke");
    expect(worker.calls[0]).toBe("files");
    expect(worker.calls[1]).toBe("pointer");
    expect(worker.calls[2]).toMatch(/^rollback of the live version: shield page-views/);
    expect(worker.state.pointerVersion).toBe("previous-version");
    expect(statuses).toEqual(["running", "fix_ready", "deployed_live", "failed"]);
    const lastStatus = backendServer.statuses[backendServer.statuses.length - 1] as Record<string, unknown>;
    expect(lastStatus.rolledBack).toBe(true);
    expect(notifications.some(function isRollBackNote(title: string) {
      return title.startsWith("Rolled back:");
    })).toBe(true);
  });

  it("never flips the pointer when the fast part refuses the copy", async () => {
    const { result, worker, statuses } = await runPublishFirstJob(AGENT_THAT_CHANGES_ADD, false);
    expect(result.status).toBe("failed");
    expect(result.reason).toBe("check failed");
    expect(result.detail).toContain("reminders.add");
    expect(worker.calls).not.toContain("pointer");
    expect(worker.state.pointerVersion).toBe("previous-version");
    expect(statuses).toEqual(["running", "failed"]);
  });
});
