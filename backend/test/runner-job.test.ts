// The repair runner end to end against a fake backend and stub agents (docs/briefs/repair-runner.md,
// tests 6: a fake job runs end to end; a failing check stops the job short of fix_ready; the job
// folder contains nothing outside the Sidekick).
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createBackendClient } from "../../runner/lib/backend.mjs";
import { listFilesRecursively } from "../../runner/lib/job-folder.mjs";
import { runJob } from "../../runner/lib/run-job.mjs";
import {
  AGENT_THAT_ADDS_EXTERNAL_SCRIPT,
  AGENT_THAT_CLAIMS_FIX_BUT_CHANGES_NOTHING,
  AGENT_THAT_FIXES_TITLE,
  AGENT_THAT_SAYS_UNSUPPORTED,
  AGENT_THAT_WRITES_OUTSIDE,
  RUNNER_TOKEN,
  baseRemindersTestFiles,
  fakeDeployThatLands,
  fakeFetchWithoutStoredTests,
  makeScratch,
  standardAssets,
  startFakeBackend,
  writeStubAgent,
  type FakeBackend,
} from "./helpers/runner-fixture";

const JOB_ROW = { id: "rep-1", user_id: "user-77", sidekick_id: "reminders", bundle_version: "20261011T065908559Z-1064a312", kind: "change", transcript: "rename the page to My Reminders" };

type RunOptions = {
  agentSource: string;
  jobRow?: typeof JOB_ROW;
  assets?: Record<string, string | Buffer>;
  testsPass?: boolean;
};

let openBackend: FakeBackend | null = null;

afterEach(async () => {
  if (openBackend !== null) {
    await openBackend.close();
    openBackend = null;
  }
});

async function runWith(options: RunOptions) {
  const { scratch, settings } = makeScratch();
  const backendServer = await startFakeBackend(options.jobRow ?? JOB_ROW, options.assets ?? standardAssets());
  openBackend = backendServer;
  const backend = createBackendClient({ baseUrl: backendServer.baseUrl, token: RUNNER_TOKEN });
  const job = await backend.claimJob();
  const notifications: Array<{ title: string; body: string }> = [];
  const testRuns: string[] = [];
  const deploy = fakeDeployThatLands();
  const result = await runJob(job, {
    backend,
    settings,
    agentCommand: process.execPath,
    agentArgs: [writeStubAgent(scratch, options.agentSource)],
    runFetch: fakeFetchWithoutStoredTests().runFetch,
    runTests: async ({ sidekickId }: { sidekickId: string }) => {
      testRuns.push(sidekickId);
      return { ok: options.testsPass ?? true, output: options.testsPass === false ? "FAIL reminders-logic.test.ts" : "81 passed" };
    },
    runDeploy: deploy.runDeploy,
    readPointer: deploy.readPointer,
    notify: async (notification: { title: string; body: string }) => {
      notifications.push(notification);
    },
  });
  return { result, backendServer, notifications, testRuns, job, deploy };
}

describe("runJob end to end", () => {
  it("runs a fake job to deployed_live: statuses, diff, summary with the live version, notifications", async () => {
    const { result, backendServer, notifications, testRuns, deploy } = await runWith({ agentSource: AGENT_THAT_FIXES_TITLE });

    expect(result.status).toBe("deployed_live");
    const statusNames = backendServer.statuses.map((status) => status.status);
    expect(statusNames).toEqual(["running", "fix_ready", "deployed_live"]);
    expect(backendServer.statuses[1].summary).toBe("Renamed the page title to My Reminders.");
    expect(backendServer.statuses[2]).toEqual({ status: "deployed_live", summary: "Renamed the page title to My Reminders.", version: "v-test" });
    expect(testRuns).toEqual(["reminders"]);

    // One deploy, for the reporter's copy, never the base.
    expect(deploy.deployCalls).toHaveLength(1);
    const deployArgs = deploy.deployCalls[0].args;
    expect(deployArgs[deployArgs.indexOf("--user") + 1]).toBe("user-77");
    expect(deployArgs).not.toContain("--from-base");

    const diff = readFileSync(join(result.logFolder, "diff.patch"), "utf8");
    expect(diff).toContain("-<title>Reminders</title>");
    expect(diff).toContain("+<title>My Reminders</title>");

    const summary = readFileSync(join(result.logFolder, "summary.md"), "utf8");
    expect(summary).toContain("rename the page to My Reminders");
    expect(summary).toContain("Version v-test is live for user user-77");
    expect(summary).toContain("node scripts/deploy-sidekick.mjs reminders --env live --user user-77 --from-base");
    expect(summary).not.toContain("founder-live-id");
    expect(existsSync(join(result.logFolder, "agent-stream.jsonl"))).toBe(true);
    expect(existsSync(join(result.logFolder, "system-prompt.md"))).toBe(true);

    expect(notifications.map((notification) => notification.title)).toEqual(["Repair request: reminders", "Fixed and live: reminders"]);
  });

  it("asked the backend for the reporter's bundle and the report assets with the runner token", async () => {
    const { backendServer } = await runWith({ agentSource: AGENT_THAT_FIXES_TITLE });
    expect(backendServer.assetRequests).toContain("bundle.html");
    expect(backendServer.assetRequests).toContain("bundle.manifest.json");
    expect(backendServer.assetRequests).toContain("screenshot.png");
    expect(backendServer.assetRequests).toContain("drawing.png");
    expect(backendServer.assetRequests).toContain("strokes.json");
  });

  it("builds a job folder holding only the guard, the Sidekick, the report, the copy's tests and outcome.json", async () => {
    const { result } = await runWith({ agentSource: AGENT_THAT_FIXES_TITLE });
    const files = listFilesRecursively(result.jobFolder);
    // The copy's tests fall back to the base Reminders tests in the checkout (contract, 2026-10-13).
    const copyTestFiles = baseRemindersTestFiles().map((name) => `tests/${name}`);
    expect(copyTestFiles.length).toBeGreaterThan(0);
    expect(files).toEqual([
      ".claude/agents/test-guardian.md",
      ".claude/hooks/guard_tests.py",
      ".claude/settings.json",
      "outcome.json",
      "report/drawing.png",
      "report/report.json",
      "report/screenshot.png",
      "report/strokes.json",
      "report/transcript.txt",
      "sidekick/index.html",
      "sidekick/manifest.json",
      "tests/TEST_CHANGES.md",
      ...copyTestFiles,
    ]);
    expect(readFileSync(join(result.jobFolder, "report", "transcript.txt"), "utf8")).toBe("rename the page to My Reminders");
    const reportRecord = JSON.parse(readFileSync(join(result.jobFolder, "report", "report.json"), "utf8"));
    expect(reportRecord.bundleVersion).toBe("20261011T065908559Z-1064a312");
    expect(reportRecord.kind).toBe("change");
  });

  it("a failing Sidekick test ends the job as failed, never fix_ready", async () => {
    const { result, backendServer } = await runWith({ agentSource: AGENT_THAT_FIXES_TITLE, testsPass: false });
    expect(result.status).toBe("failed");
    expect(result.reason).toBe("check failed");
    const statusNames = backendServer.statuses.map((status) => status.status);
    expect(statusNames).toEqual(["running", "failed"]);
    expect(backendServer.statuses[1].reason).toBe("check failed");
    expect(readFileSync(join(result.logFolder, "check-output.txt"), "utf8")).toContain("FAIL");
  });

  it("the deploy gate stops a page with an external script before any test runs", async () => {
    const { result, testRuns } = await runWith({ agentSource: AGENT_THAT_ADDS_EXTERNAL_SCRIPT });
    expect(result.status).toBe("failed");
    expect(result.reason).toBe("check failed");
    expect(result.detail).toContain("script tag with attributes");
    expect(testRuns).toEqual([]);
  });

  it("an agent that writes outside sidekick/ fails the job", async () => {
    const { result, backendServer } = await runWith({ agentSource: AGENT_THAT_WRITES_OUTSIDE });
    expect(result.status).toBe("failed");
    expect(result.reason).toBe("agent wrote outside the Sidekick");
    expect(result.detail).toBe("notes.txt");
    expect(backendServer.statuses.map((status) => status.status)).toEqual(["running", "failed"]);
  });

  it("an unsupported request is reported as failed with the user's action as detail", async () => {
    const { result, backendServer, notifications } = await runWith({ agentSource: AGENT_THAT_SAYS_UNSUPPORTED });
    expect(result.status).toBe("failed");
    expect(result.reason).toBe("unsupported");
    expect(result.detail).toBe("a notification that wiggles");
    expect(backendServer.statuses[1]).toEqual({ status: "failed", reason: "unsupported", detail: "a notification that wiggles" });
    expect(notifications[1].title).toBe("Repair failed: reminders");
  });

  it("an agent that reports a fix but changes nothing fails as no change", async () => {
    const { result } = await runWith({ agentSource: AGENT_THAT_CLAIMS_FIX_BUT_CHANGES_NOTHING });
    expect(result.status).toBe("failed");
    expect(result.reason).toBe("no change");
  });

  it("a report with no transcript anywhere fails before the agent runs", async () => {
    const assets = standardAssets();
    const { result, backendServer } = await runWith({ agentSource: AGENT_THAT_FIXES_TITLE, jobRow: { ...JOB_ROW, transcript: "   " }, assets });
    expect(result.status).toBe("failed");
    expect(result.reason).toBe("transcript missing");
    expect(backendServer.assetRequests).toContain("transcript.txt");
    expect(existsSync(join(result.logFolder, "agent-stream.jsonl"))).toBe(false);
  });

  it("a missing bundle fails the job", async () => {
    const assets = standardAssets();
    delete assets["bundle.html"];
    const { result } = await runWith({ agentSource: AGENT_THAT_FIXES_TITLE, assets });
    expect(result.status).toBe("failed");
    expect(result.reason).toBe("bundle missing");
  });
});
