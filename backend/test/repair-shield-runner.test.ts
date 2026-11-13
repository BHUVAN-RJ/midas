// The shield in the runner (docs/briefs/repair-lanes.md W1; founder D3, 2026-11-13): checkRepair runs
// the deploy gate, then the shield, then the copy's tests; the shield is loaded from the platform
// checkout, never from the job folder, so nothing the repair agent writes can replace it; the
// agent's check tool runs it when the runner gives it the copy as it was and the person's records.
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { checkRepair, readCopyFolder, requestedToolsFromOutcome, runShieldForJob } from "../../runner/lib/check.mjs";
import { foreignFiles } from "../../runner/lib/job-folder.mjs";
import { CHECK_IDS, runShield, shieldReport, viewActions } from "../../runner/core-checks/shield.mjs";
import { NOW, repoRoot, sidekickCopy, todoRecords, withToolsAppended, type Copy } from "./repair-shield-fixtures";

const WEBKIT_TIMEOUT_MS = 180_000;
const todo = sidekickCopy("todo");
const records = todoRecords();
// todo.search answering something else: the deploy gate passes it, only the shield sees it
const CHANGED_SEARCH = "MidasSidekickTools.handlers.search = function newSearch() { return { ops: [], result: { text: 'Found it' } }; };";

function writeCopy(folder: string, copy: Copy) {
  mkdirSync(folder, { recursive: true });
  writeFileSync(join(folder, "index.html"), copy.html);
  writeFileSync(join(folder, "manifest.json"), copy.manifestText);
  if (copy.toolsText !== null) {
    writeFileSync(join(folder, "tools.js"), copy.toolsText);
  }
}

// A job folder holding the repaired copy, and the "before" snapshot beside it, as run-job.mjs keeps them
function makeJob(after: Copy) {
  const scratch = mkdtempSync(join(tmpdir(), "midas-shield-job-"));
  const jobFolder = join(scratch, "job");
  writeCopy(join(jobFolder, "sidekick"), after);
  const beforeFolder = join(scratch, "log", "before");
  writeCopy(beforeFolder, todo);
  const recordsPath = join(scratch, "log", "records.json");
  writeFileSync(recordsPath, JSON.stringify(records));
  return { scratch, jobFolder, beforeFolder, recordsPath };
}

// Stands in for WebKit where a test is about something else: every step opens clean
async function cleanPages({ actions }: { actions: string[] }) {
  const report = { errors: [], writes: [], written: {}, visibleElements: 5, textLength: 5, action: null };
  const steps = [{ name: "open", action: null, report }, { name: "widget", action: null, report }];
  for (const action of actions) {
    steps.push({ name: `view:${action}`, action: null, report });
  }
  return steps;
}

describe("shield: the whole run", () => {
  it("passes an unchanged To-Do copy in real WebKit, running every core check", async () => {
    const result = await runShield({ checkoutRoot: repoRoot, sidekickId: "todo", before: todo, after: todo, records, now: NOW });
    const ids = result.checks.map((check: { id: string }) => check.id);
    expect(ids).toEqual(CHECK_IDS);
    expect(shieldReport(result)).not.toContain("✕");
    expect(result.ok).toBe(true);
  }, WEBKIT_TIMEOUT_MS);

  it("taps every page control any tool names, old manifest or new", () => {
    const actions = viewActions(JSON.parse(todo.manifestText), JSON.parse(todo.manifestText));
    expect(actions).toContain("go-search");
    expect(actions).toContain("panel");
    expect(new Set(actions).size).toBe(actions.length);
  });

  it("fails closed when WebKit cannot run: a check that cannot run never reads as a pass", async () => {
    async function brokenWebKit(): Promise<never> {
      throw new Error("xcrun: error: unable to find utility swiftc");
    }
    const result = await runShield({ checkoutRoot: repoRoot, sidekickId: "todo", before: todo, after: todo, records, now: NOW, openPageImplementation: brokenWebKit });
    expect(result.ok).toBe(false);
    const pageCheck = result.checks.find((check: { id: string }) => check.id === "page-opens");
    expect(pageCheck.problems[0]).toContain("unable to find utility swiftc");
  });
});

describe("shield: in the runner's check", () => {
  it("reads the copy as it was and as it is, and names each failing check", async () => {
    const after = withToolsAppended(todo, "delete MidasSidekickTools.handlers.restore;");
    const { jobFolder, beforeFolder } = makeJob(after);
    expect(readCopyFolder(beforeFolder).toolsText).toBe(todo.toolsText);
    const shield = await runShieldForJob({ checkoutRoot: repoRoot, sidekickId: "todo", jobFolder, beforeFolder, records, openPageImplementation: cleanPages, now: NOW });
    expect(shield.ok).toBe(false);
    expect(shield.problems).toContain('shield tools: todo.restore: the new tools.js has no handler "restore"');
    expect(shield.report).toContain("✕ tools");
  });

  it("lets a tool change when outcome.json names it, and only then", async () => {
    const after = withToolsAppended(todo, CHANGED_SEARCH);
    const { jobFolder, beforeFolder } = makeJob(after);
    const unnamed = await runShieldForJob({ checkoutRoot: repoRoot, sidekickId: "todo", jobFolder, beforeFolder, records, openPageImplementation: cleanPages, now: NOW });
    expect(unnamed.ok).toBe(false);
    writeFileSync(join(jobFolder, "outcome.json"), JSON.stringify({ result: "fixed", summary: "Search finds more", changedTools: ["todo.search"] }));
    expect(requestedToolsFromOutcome(jobFolder)).toEqual(["todo.search"]);
    const named = await runShieldForJob({ checkoutRoot: repoRoot, sidekickId: "todo", jobFolder, beforeFolder, records, openPageImplementation: cleanPages, now: NOW });
    expect(named.ok).toBe(true);
    expect(named.changedTools).toEqual(["todo.search"]);
  });

  it("refuses a gate failure before the shield runs, and a shield failure before the copy's tests run", async () => {
    let testsRan = false;
    async function recordTestRun() {
      testsRan = true;
      return { ok: true, output: "" };
    }
    const forbiddenPage = { ...todo, html: todo.html.replace("</body>", "<script>var socket = WebSocket;</script></body>") };
    const gateJob = makeJob(forbiddenPage);
    const gated = await checkRepair({ checkoutRoot: repoRoot, sidekickId: "todo", jobFolder: gateJob.jobFolder, beforeFolder: gateJob.beforeFolder, records, runTests: recordTestRun, openPageImplementation: cleanPages, now: NOW });
    expect(gated.ok).toBe(false);
    expect(gated.problems[0]).toContain("deploy gate rejected: WebSocket");
    expect(gated.shield).toBe(null);

    // The gate cannot see a tool that answers differently; the shield can
    const shieldJob = makeJob(withToolsAppended(todo, CHANGED_SEARCH));
    const shielded = await checkRepair({ checkoutRoot: repoRoot, sidekickId: "todo", jobFolder: shieldJob.jobFolder, beforeFolder: shieldJob.beforeFolder, records, runTests: recordTestRun, openPageImplementation: cleanPages, now: NOW });
    expect(shielded.ok).toBe(false);
    expect(shielded.problems[0]).toContain("shield tools: todo.search answers differently");
    expect(testsRan).toBe(false);

    const goodJob = makeJob(todo);
    const passed = await checkRepair({ checkoutRoot: repoRoot, sidekickId: "todo", jobFolder: goodJob.jobFolder, beforeFolder: goodJob.beforeFolder, records, runTests: recordTestRun, openPageImplementation: cleanPages, now: NOW });
    expect(passed.problems).toEqual([]);
    expect(passed.ok).toBe(true);
    expect(testsRan).toBe(true);
  });

  it("loads the shield from the platform checkout: a shield planted in the job folder is never used", async () => {
    const after = withToolsAppended(todo, "delete MidasSidekickTools.handlers.restore;");
    const { jobFolder, beforeFolder } = makeJob(after);
    const plantedFolder = join(jobFolder, "runner", "core-checks");
    mkdirSync(plantedFolder, { recursive: true });
    const alwaysPass = "export async function runShield() { return { ok: true, checks: [], changedTools: [] }; }\nexport function shieldProblems() { return []; }\nexport function shieldReport() { return 'planted'; }\n";
    writeFileSync(join(plantedFolder, "shield.mjs"), alwaysPass);
    const shield = await runShieldForJob({ checkoutRoot: repoRoot, sidekickId: "todo", jobFolder, beforeFolder, records, openPageImplementation: cleanPages, now: NOW });
    expect(shield.ok).toBe(false);
    expect(shield.report).not.toBe("planted");
    // And the runner refuses a job folder holding anything but the Sidekick, report, tests and outcome
    expect(foreignFiles(jobFolder)).toContain("runner/core-checks/shield.mjs");
  });
});

describe("shield: the agent's check tool", () => {
  it("runs the shield when the runner gives the before copy and the records, and prints what failed", () => {
    const after = withToolsAppended(todo, CHANGED_SEARCH);
    const { jobFolder, beforeFolder, recordsPath, scratch } = makeJob(after);
    const manifestBeforePath = join(scratch, "log", "manifest-before.json");
    writeFileSync(manifestBeforePath, todo.manifestText);
    const checkToolPath = join(repoRoot, "runner", "tools", "check.mjs");
    const environment = {
      ...process.env,
      MIDAS_JOB_FOLDER: jobFolder,
      MIDAS_RUNNER_CHECKOUT: repoRoot,
      MIDAS_JOB_SIDEKICK_ID: "todo",
      MIDAS_JOB_MANIFEST_BEFORE: manifestBeforePath,
      MIDAS_JOB_BEFORE_FOLDER: beforeFolder,
      MIDAS_JOB_RECORDS: recordsPath,
    };
    let code = 0;
    let output = "";
    try {
      output = execFileSync(process.execPath, [checkToolPath], { env: environment, encoding: "utf8", timeout: WEBKIT_TIMEOUT_MS });
    } catch (error) {
      const failure = error as { status: number; stdout: string };
      code = failure.status;
      output = failure.stdout;
    }
    expect(code).toBe(1);
    expect(output).toContain("✕ tools");
    expect(output).toContain("✓ page-opens");
    expect(output).toContain("check failed: shield tools: todo.search answers differently");
  }, WEBKIT_TIMEOUT_MS);
});
