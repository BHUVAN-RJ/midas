// An X on the repair tag cancels the repair (founder, 2026-11-22; docs/PRODUCT.md, commit f2e047f):
// a job already running is stopped and nothing is published. The runner learns of the cancel from
// GET /repairs/:id (backend.isCancelled), checked between steps and right before the flip, from a
// 30 s watch that stops the agent, and from any status post the Worker refuses with cancelled: true
// (RepairCancelled). A cancelled job posts no failure, removes its job folder and keeps
// cancelled.json in its log folder. Both environments behave the same.
import { cpSync, existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { RepairCancelled, createBackendClient } from "../../runner/lib/backend.mjs";
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
  id: "rep-cancel-1",
  user_id: "user-77",
  sidekick_id: "reminders",
  bundle_version: "20261011T065908559Z-1064a312",
  kind: "change",
  transcript: "call it My Reminders",
};

const AGENT_THAT_RENAMES = `
import { readFileSync, writeFileSync } from "node:fs";
const page = readFileSync("sidekick/index.html", "utf8");
writeFileSync("sidekick/index.html", page.replace("<title>Reminders</title>", "<title>My Reminders</title>"));
writeFileSync("outcome.json", JSON.stringify({ result: "fixed", summary: "The title says My Reminders." }));
`;

// Works for a long time: only a cancel (or the timeout) ends it
const AGENT_THAT_TAKES_LONG = `
setTimeout(function finishLate() {}, 60000);
`;

function pagesThatOpen() {
  async function openPageStandIn({ actions, kinds, records }: { actions: string[]; kinds: string[]; records: unknown[] }) {
    const steps = plannedSteps({ records, actions, kinds });
    return steps.map(function stepReport(step: { name: string; action: string | null }) {
      const report = { errors: [], writes: [], written: {}, visibleElements: 5, textLength: 5, action: step.action === null ? null : { found: true } };
      return { name: step.name, action: step.action, report };
    });
  }
  return openPageStandIn;
}

type CancelPlan = {
  // isCancelled answers true from this call on (1 = the first); null: never
  cancelledFromCall: number | null;
  // The person cancels while the new version uploads (before the flip)
  cancelDuringUpload?: boolean;
  // The Worker refuses this status post with cancelled: true (after the flip)
  refuseStatus?: string;
};

function makeWorker(plan: CancelPlan) {
  const calls: string[] = [];
  const state = { pointerVersion: "previous-version" as string | null, cancelChecks: 0, cancelled: false };
  async function isCancelled() {
    state.cancelChecks += 1;
    if (plan.cancelledFromCall !== null && state.cancelChecks >= plan.cancelledFromCall) {
      state.cancelled = true;
    }
    return state.cancelled;
  }
  async function publishFiles(_reportId: string, { version, files }: { version: string; files: unknown[] }) {
    calls.push("files");
    if (plan.cancelDuringUpload === true) {
      state.cancelled = true;
    }
    return { version, stored: files.length };
  }
  async function flipPointer(_reportId: string, { version }: { version: string }) {
    calls.push("pointer");
    state.pointerVersion = version;
    return { version, previousVersion: "previous-version" };
  }
  async function rollBackPointer(_reportId: string, { reason }: { version: string; reason: string }) {
    calls.push(`rollback: ${reason}`);
    state.pointerVersion = "previous-version";
    return { rolledBack: true, version: "previous-version" };
  }
  return { calls, state, isCancelled, publishFiles, flipPointer, rollBackPointer };
}

let openBackend: FakeBackend | null = null;

afterEach(async () => {
  if (openBackend !== null) {
    await openBackend.close();
    openBackend = null;
  }
});

async function runCancelJob(agentSource: string, plan: CancelPlan, publishMode: "first" | "after", extraSettings: Record<string, unknown> = {}) {
  const { scratch, checkout, settings } = makeScratch();
  cpSync(join(REPO_ROOT, "runner", "core-checks"), join(checkout, "runner", "core-checks"), { recursive: true, force: true });
  cpSync(join(REPO_ROOT, "runner", "lib"), join(checkout, "runner", "lib"), { recursive: true, force: true });
  const backendServer = await startFakeBackend(JOB_ROW, standardAssets());
  openBackend = backendServer;
  const worker = makeWorker(plan);
  const client = createBackendClient({ baseUrl: backendServer.baseUrl, token: RUNNER_TOKEN });
  async function postStatusUnlessRefused(reportId: string, status: string, extra?: Record<string, unknown>) {
    if (plan.refuseStatus === status) {
      worker.state.cancelled = true;
      throw new RepairCancelled(reportId);
    }
    return client.postStatus(reportId, status, extra);
  }
  const backend = {
    ...client,
    isCancelled: worker.isCancelled,
    postStatus: postStatusUnlessRefused,
    publishFiles: worker.publishFiles,
    flipPointer: worker.flipPointer,
    rollBackPointer: worker.rollBackPointer,
  };
  const job = await backend.claimJob();
  const deploy = fakeDeployThatLands();
  const notifications: string[] = [];
  async function recordNotification({ title }: { title: string }) {
    notifications.push(title);
  }
  async function testsPass() {
    return { ok: true, output: "1 passed" };
  }
  const startedAt = Date.now();
  const result = await runJob(job, {
    backend,
    settings: { ...settings, publishMode, ...extraSettings },
    agentCommand: process.execPath,
    agentArgs: [writeStubAgent(scratch, agentSource)],
    runFetch: fakeFetchWithoutStoredTests().runFetch,
    runTests: testsPass,
    runDeploy: deploy.runDeploy,
    readPointer: deploy.readPointer,
    notify: recordNotification,
    openPageImplementation: pagesThatOpen(),
  });
  const statuses = backendServer.statuses.map(function statusName(entry: Record<string, unknown>) {
    return entry.status;
  });
  return { result, worker, deploy, statuses, notifications, seconds: (Date.now() - startedAt) / 1000 };
}

describe("runJob honours a cancel", () => {
  it("without a cancel the job publishes as before (the check reads false)", async () => {
    const { result, worker, statuses } = await runCancelJob(AGENT_THAT_RENAMES, { cancelledFromCall: null }, "first");
    expect(result.status).toBe("deployed_live");
    expect(worker.calls).toEqual(["files", "pointer"]);
    expect(worker.state.cancelChecks).toBeGreaterThan(0);
    expect(statuses).toEqual(["running", "fix_ready", "deployed_live"]);
  });

  it("a cancel before the agent starts: no agent, nothing published, no failure posted", async () => {
    const { result, worker, statuses, notifications } = await runCancelJob(AGENT_THAT_RENAMES, { cancelledFromCall: 1 }, "first");
    expect(result.status).toBe("cancelled");
    expect(existsSync(join(result.logFolder, "agent-exit.json"))).toBe(false);
    expect(worker.calls).toEqual([]);
    expect(statuses).toEqual(["running"]);
    expect(existsSync(join(result.logFolder, "cancelled.json"))).toBe(true);
    expect(notifications.some(function isCancelNote(title: string) {
      return title.startsWith("Repair cancelled:");
    })).toBe(true);
  });

  it("a cancel while the new version uploads: the pointer never flips (publish first, staging)", async () => {
    const { result, worker, statuses } = await runCancelJob(AGENT_THAT_RENAMES, { cancelledFromCall: null, cancelDuringUpload: true }, "first");
    expect(result.status).toBe("cancelled");
    expect(worker.calls).toEqual(["files"]);
    expect(worker.state.pointerVersion).toBe("previous-version");
    expect(statuses).toEqual(["running"]);
    expect(result.jobFolder).toBeNull();
  });

  it("a cancel between the flip and 'live': the copy is rolled back, the person keeps what they had", async () => {
    const { result, worker, statuses } = await runCancelJob(AGENT_THAT_RENAMES, { cancelledFromCall: null, refuseStatus: "fix_ready" }, "first");
    expect(result.status).toBe("cancelled");
    expect(worker.calls).toEqual(["files", "pointer", "rollback: cancelled by the person"]);
    expect(worker.state.pointerVersion).toBe("previous-version");
    expect(statuses).toEqual(["running"]);
  });

  it("a cancel before the deploy in publish-after mode (live): no deploy is run", async () => {
    const { result, deploy, statuses } = await runCancelJob(AGENT_THAT_RENAMES, { cancelledFromCall: 3 }, "after");
    expect(result.status).toBe("cancelled");
    expect(deploy.deployCalls).toEqual([]);
    expect(statuses).not.toContain("deployed_live");
    expect(statuses).not.toContain("failed");
  });

  it("the watch stops a long agent soon after the cancel", async () => {
    const { result, seconds } = await runCancelJob(AGENT_THAT_TAKES_LONG, { cancelledFromCall: 3 }, "first", { cancelPollMs: 100 });
    expect(result.status).toBe("cancelled");
    expect(seconds).toBeLessThan(20);
    const exit = JSON.parse(readFileSync(join(result.logFolder, "agent-exit.json"), "utf8"));
    expect(exit.aborted).toBe(true);
  }, 30000);
});
