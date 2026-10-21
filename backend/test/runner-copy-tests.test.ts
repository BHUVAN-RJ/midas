// Tests move every copy forward (founder, 2026-10-13, docs/briefs/repair-contract.md "Settled"):
// the job folder gets the copy's tests in tests/, the check runs them (not the checkout's) in a
// sandbox, the agent may only add test files, the runner fails the job when a pre-existing test
// changed without a test-guardian log entry, and the tests go up with the page.
import { cpSync, existsSync, lstatSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createBackendClient } from "../../runner/lib/backend.mjs";
import { buildSandboxCheckout, runCopyTests, runVitestInSandbox, sandboxRootFor } from "../../runner/lib/check.mjs";
import {
  AGENT_SETTINGS_FILES,
  TEST_LOG_FILE,
  baseTestsFromCheckout,
  compareTests,
  guardianLogged,
  writeTestsFolder,
} from "../../runner/lib/copy-tests.mjs";
import { deployArgs, deployFolderFor } from "../../runner/lib/deploy.mjs";
import { listFilesRecursively } from "../../runner/lib/job-folder.mjs";
import { runJob } from "../../runner/lib/run-job.mjs";
import {
  AGENT_THAT_FIXES_TITLE,
  REPO_ROOT,
  RUNNER_TOKEN,
  fakeDeployThatLands,
  fakeFetchWithStoredTests,
  fakeFetchWithoutStoredTests,
  makeScratch,
  remindersBundle,
  standardAssets,
  startFakeBackend,
  writeStubAgent,
  type FakeBackend,
} from "./helpers/runner-fixture";

const JOB_ROW = { id: "rep-t1", user_id: "user-77", sidekick_id: "reminders", bundle_version: "20261011T065908559Z-1064a312", kind: "change", transcript: "rename the page to My Reminders" };

// Two small tests a copy might carry: one reads the page the way the real Reminders tests do.
const COPY_TEST_TITLE = [
  'import { readFileSync } from "node:fs";',
  'import { describe, expect, it } from "vitest";',
  'const page = readFileSync(new URL("../../sidekicks/reminders/index.html", import.meta.url), "utf8");',
  'describe("copy title", () => { it("has the page title", () => { expect(page).toContain("<title>"); }); });',
  "",
].join("\n");
const COPY_TEST_MANIFEST = [
  'import { readFileSync } from "node:fs";',
  'import { describe, expect, it } from "vitest";',
  'const manifest = JSON.parse(readFileSync(new URL("../../sidekicks/reminders/manifest.json", import.meta.url), "utf8"));',
  'describe("copy manifest", () => { it("is the reminders Sidekick", () => { expect(manifest.id).toBe("reminders"); }); });',
  "",
].join("\n");
const COPY_LOG = "# Test changes for this copy\n\n- 2026-10-12: copy started from base; no changes.\n";

// What the copy has stored in R2 beside its version (repair-copies, merged 2026-10-14): the fetch
// script brings these down into <out>/tests/.
function storedCopyTests(): Record<string, string> {
  return { "reminders-copy-title.test.ts": COPY_TEST_TITLE, "reminders-copy-manifest.test.ts": COPY_TEST_MANIFEST, [TEST_LOG_FILE]: COPY_LOG };
}

type FetchStub = ReturnType<typeof fakeFetchWithStoredTests>["runFetch"];

// A fetch that runs but fails, as when live has no version for the reporter.
function fakeFetchThatFails(): FetchStub {
  return async () => ({ ok: false, output: "live has no version of reminders for user user-77 and no base" });
}

// The fixture's scratch checkout plus what this step needs from a real clone: the test guard
// files for the agent's .claude/ and the base Reminders tests for the fallback.
function makeScratchWithGuard() {
  const made = makeScratch();
  for (const relativePath of AGENT_SETTINGS_FILES) {
    mkdirSync(join(made.checkout, relativePath, ".."), { recursive: true });
    cpSync(join(REPO_ROOT, relativePath), join(made.checkout, relativePath));
  }
  mkdirSync(join(made.checkout, "backend", "test"), { recursive: true });
  for (const name of ["reminders-logic.test.ts", "reminders-wording.test.ts"]) {
    cpSync(join(REPO_ROOT, "backend", "test", name), join(made.checkout, "backend", "test", name));
  }
  // Something that is not a Reminders test, to prove the fallback filters by Sidekick.
  writeFileSync(join(made.checkout, "backend", "test", "other-sidekick.test.ts"), "// not ours\n");
  return made;
}

let openBackend: FakeBackend | null = null;

afterEach(async () => {
  if (openBackend !== null) {
    await openBackend.close();
    openBackend = null;
  }
});

type RunOptions = { agentSource: string; runFetch?: FetchStub; testsPass?: boolean };

async function runWithTests(options: RunOptions) {
  const { scratch, settings } = makeScratchWithGuard();
  const runFetch = options.runFetch ?? fakeFetchWithStoredTests(storedCopyTests()).runFetch;
  const backendServer = await startFakeBackend(JOB_ROW, standardAssets());
  openBackend = backendServer;
  const backend = createBackendClient({ baseUrl: backendServer.baseUrl, token: RUNNER_TOKEN });
  const job = await backend.claimJob();
  const deploy = fakeDeployThatLands();
  const testRuns: Array<{ sandboxBackend: string; testFiles: string[] }> = [];
  const result = await runJob(job, {
    backend,
    settings,
    agentCommand: process.execPath,
    agentArgs: [writeStubAgent(scratch, options.agentSource)],
    runFetch,
    runTests: async ({ sandboxBackend }: { sandboxBackend: string }) => {
      testRuns.push({ sandboxBackend, testFiles: listFilesRecursively(join(sandboxBackend, "test")) });
      return { ok: options.testsPass ?? true, output: options.testsPass === false ? "FAIL" : "ok" };
    },
    runDeploy: deploy.runDeploy,
    readPointer: deploy.readPointer,
    notify: async () => {},
  });
  return { result, backendServer, deploy, testRuns, settings };
}

const AGENT_THAT_EDITS_A_TEST = `
import { readFileSync, writeFileSync } from "node:fs";
const page = readFileSync("sidekick/index.html", "utf8");
writeFileSync("sidekick/index.html", page.replace("<title>Reminders</title>", "<title>My Reminders</title>"));
const test = readFileSync("tests/reminders-copy-title.test.ts", "utf8");
writeFileSync("tests/reminders-copy-title.test.ts", test.replace("<title>", "<titl"));
writeFileSync("outcome.json", JSON.stringify({ result: "fixed", summary: "Renamed; loosened a test." }));
`;

const AGENT_THAT_DELETES_A_TEST = `
import { readFileSync, writeFileSync, unlinkSync } from "node:fs";
const page = readFileSync("sidekick/index.html", "utf8");
writeFileSync("sidekick/index.html", page.replace("<title>Reminders</title>", "<title>My Reminders</title>"));
unlinkSync("tests/reminders-copy-manifest.test.ts");
writeFileSync("outcome.json", JSON.stringify({ result: "fixed", summary: "Renamed; dropped a test." }));
`;

const AGENT_THAT_ADDS_A_TEST = `
import { readFileSync, writeFileSync } from "node:fs";
const page = readFileSync("sidekick/index.html", "utf8");
writeFileSync("sidekick/index.html", page.replace("<title>Reminders</title>", "<title>My Reminders</title>"));
writeFileSync("tests/reminders-copy-renamed.test.ts", 'import { describe, expect, it } from "vitest"; describe("renamed", () => { it("is", () => { expect(1).toBe(1); }); });');
writeFileSync("outcome.json", JSON.stringify({ result: "fixed", summary: "Renamed the page title to My Reminders." }));
`;

// What a test-guardian accept looks like from the runner's side: the test changed and the log
// kept its lines and gained one naming the file.
const AGENT_WITH_GUARDIAN_LOGGED_CHANGE = `
import { readFileSync, writeFileSync, appendFileSync } from "node:fs";
const page = readFileSync("sidekick/index.html", "utf8");
writeFileSync("sidekick/index.html", page.replace("<title>Reminders</title>", "<title>My Reminders</title>"));
const test = readFileSync("tests/reminders-copy-title.test.ts", "utf8");
writeFileSync("tests/reminders-copy-title.test.ts", test.replace('toContain("<title>")', 'toContain("<title>My Reminders</title>")'));
appendFileSync("tests/TEST_CHANGES.md", "- 2026-10-13: reminders-copy-title.test.ts now expects the title My Reminders. Reason: the user asked for the rename (transcript). ACCEPTED by test-guardian.\\n");
writeFileSync("outcome.json", JSON.stringify({ result: "fixed", summary: "Renamed the page title to My Reminders." }));
`;

const AGENT_THAT_REWRITES_THE_LOG = `
import { readFileSync, writeFileSync } from "node:fs";
const page = readFileSync("sidekick/index.html", "utf8");
writeFileSync("sidekick/index.html", page.replace("<title>Reminders</title>", "<title>My Reminders</title>"));
const test = readFileSync("tests/reminders-copy-title.test.ts", "utf8");
writeFileSync("tests/reminders-copy-title.test.ts", test.replace("<title>", "<titl"));
writeFileSync("tests/TEST_CHANGES.md", "- 2026-10-13: reminders-copy-title.test.ts changed.\\n");
writeFileSync("outcome.json", JSON.stringify({ result: "fixed", summary: "Renamed." }));
`;

describe("the copy's tests reach the job folder", () => {
  it("falls back to the base Sidekick's tests from the checkout, with an empty log", () => {
    const { checkout } = makeScratchWithGuard();
    const base = baseTestsFromCheckout({ checkoutRoot: checkout, sidekickId: "reminders" });
    expect(Object.keys(base.files).sort()).toEqual([TEST_LOG_FILE, "reminders-logic.test.ts", "reminders-wording.test.ts"]);
    expect(base.files[TEST_LOG_FILE]).toBe("");
    expect(base.source).toBe("base checkout");
  });

  it("a job with stored copy tests holds those tests, the log and the guard files, and nothing else new", async () => {
    const { result, testRuns, deploy } = await runWithTests({ agentSource: AGENT_THAT_FIXES_TITLE });
    expect(result.status).toBe("deployed_live");
    expect(listFilesRecursively(result.jobFolder)).toEqual([
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
      "sidekick/tools.js",
      "tests/TEST_CHANGES.md",
      "tests/reminders-copy-manifest.test.ts",
      "tests/reminders-copy-title.test.ts",
    ]);
    expect(readFileSync(join(result.jobFolder, "tests", TEST_LOG_FILE), "utf8")).toBe(COPY_LOG);
    // The check ran the copy's tests, not the checkout's.
    expect(testRuns).toHaveLength(1);
    expect(testRuns[0].testFiles).toEqual([TEST_LOG_FILE, "reminders-copy-manifest.test.ts", "reminders-copy-title.test.ts"]);
    expect(testRuns[0].sandboxBackend).toBe(join(sandboxRootFor(result.jobFolder), "backend"));
    expect(existsSync(sandboxRootFor(result.jobFolder))).toBe(false);
    // The tests went up with the page, from the staged deploy folder (no --tests flag).
    const args = deploy.deployCalls[0].args;
    expect(args[args.indexOf("--dir") + 1]).toBe(deployFolderFor(result.jobFolder));
    expect(args).not.toContain("--tests");
    const report = JSON.parse(readFileSync(join(result.logFolder, "tests-report.json"), "utf8"));
    expect(report.source).toBe("user copy");
  });

  it("a copy with no stored tests runs the base tests from the checkout", async () => {
    const { result, testRuns } = await runWithTests({ agentSource: AGENT_THAT_FIXES_TITLE, runFetch: fakeFetchWithoutStoredTests().runFetch });
    expect(result.status).toBe("deployed_live");
    expect(testRuns[0].testFiles).toEqual([TEST_LOG_FILE, "reminders-logic.test.ts", "reminders-wording.test.ts"]);
    const report = JSON.parse(readFileSync(join(result.logFolder, "tests-report.json"), "utf8"));
    expect(report.source).toBe("base checkout");
  });

  it("a failing fetch fails the job before the agent runs", async () => {
    const { result } = await runWithTests({ agentSource: AGENT_THAT_FIXES_TITLE, runFetch: fakeFetchThatFails() });
    expect(result.status).toBe("failed");
    expect(result.reason).toBe("tests missing");
    expect(result.detail).toContain("fetch-sidekick-copy failed");
    expect(existsSync(join(result.logFolder, "agent-stream.jsonl"))).toBe(false);
  });
});

describe("existing tests are add-only for the agent", () => {
  it("compareTests: identical passes; a change needs a guardian log line that keeps the old ones", () => {
    const before = { "a.test.ts": Buffer.from("x"), "b.test.ts": Buffer.from("y"), [TEST_LOG_FILE]: Buffer.from("- old entry\n") };
    const same = compareTests({ before, after: { ...before } });
    expect(same.problems).toEqual([]);

    const changedNoLog = compareTests({ before, after: { ...before, "a.test.ts": Buffer.from("z") } });
    expect(changedNoLog.changed).toEqual(["a.test.ts"]);
    expect(changedNoLog.problems).toEqual(["test changed without a test-guardian entry in TEST_CHANGES.md: a.test.ts"]);

    const changedLogged = compareTests({ before, after: { ...before, "a.test.ts": Buffer.from("z"), [TEST_LOG_FILE]: Buffer.from("- old entry\n- 2026-10-13 a.test.ts ACCEPTED\n") } });
    expect(changedLogged.problems).toEqual([]);
    expect(changedLogged.changed).toEqual(["a.test.ts"]);
    expect(changedLogged.logGrew).toBe(true);

    const changedWrongFileLogged = compareTests({ before, after: { ...before, "a.test.ts": Buffer.from("z"), [TEST_LOG_FILE]: Buffer.from("- old entry\n- 2026-10-13 b.test.ts ACCEPTED\n") } });
    expect(changedWrongFileLogged.problems).toHaveLength(1);

    const logRewritten = compareTests({ before, after: { ...before, "a.test.ts": Buffer.from("z"), [TEST_LOG_FILE]: Buffer.from("- 2026-10-13 a.test.ts\n") } });
    expect(logRewritten.problems).toEqual(["test changed without a test-guardian entry in TEST_CHANGES.md: a.test.ts", "TEST_CHANGES.md lost entries"]);

    const deleted = compareTests({ before, after: { "a.test.ts": Buffer.from("x"), [TEST_LOG_FILE]: Buffer.from("- old entry\n") } });
    expect(deleted.deleted).toEqual(["b.test.ts"]);
    expect(deleted.problems).toEqual(["test deleted: b.test.ts"]);

    const added = compareTests({ before, after: { ...before, "c.test.ts": Buffer.from("new") } });
    expect(added.added).toEqual(["c.test.ts"]);
    expect(added.problems).toEqual([]);

    expect(guardianLogged({ logBefore: "", logAfter: "- a.test.ts accepted", fileName: "a.test.ts" })).toBe(true);
    expect(guardianLogged({ logBefore: "- kept", logAfter: "- a.test.ts accepted", fileName: "a.test.ts" })).toBe(false);
  });

  it("an agent that edits an existing test ends failed as test changed, never deployed", async () => {
    const { result, backendServer, deploy } = await runWithTests({ agentSource: AGENT_THAT_EDITS_A_TEST });
    expect(result.status).toBe("failed");
    expect(result.reason).toBe("test changed");
    expect(result.detail).toContain("reminders-copy-title.test.ts");
    expect(backendServer.statuses.map((status) => status.status)).toEqual(["running", "failed"]);
    expect(deploy.deployCalls).toEqual([]);
  });

  it("an agent that deletes an existing test ends failed", async () => {
    const { result, deploy } = await runWithTests({ agentSource: AGENT_THAT_DELETES_A_TEST });
    expect(result.status).toBe("failed");
    expect(result.reason).toBe("test changed");
    expect(result.detail).toBe("test deleted: reminders-copy-manifest.test.ts");
    expect(deploy.deployCalls).toEqual([]);
  });

  it("an agent that rewrites the log to cover its change still fails", async () => {
    const { result } = await runWithTests({ agentSource: AGENT_THAT_REWRITES_THE_LOG });
    expect(result.status).toBe("failed");
    expect(result.reason).toBe("test changed");
    expect(result.detail).toContain("TEST_CHANGES.md lost entries");
  });

  it("an added test file is allowed, runs in the check, and goes live with the page", async () => {
    const { result, testRuns, deploy } = await runWithTests({ agentSource: AGENT_THAT_ADDS_A_TEST });
    expect(result.status).toBe("deployed_live");
    expect(testRuns[0].testFiles).toContain("reminders-copy-renamed.test.ts");
    expect(deploy.deployCalls).toHaveLength(1);
    const report = JSON.parse(readFileSync(join(result.logFolder, "tests-report.json"), "utf8"));
    expect(report.added).toEqual(["reminders-copy-renamed.test.ts"]);
    const summary = readFileSync(join(result.logFolder, "summary.md"), "utf8");
    expect(summary).toContain("Added by the agent: reminders-copy-renamed.test.ts.");
    expect(summary).toContain("Tests came from: user copy.");
  });

  it("a change the guardian logged is accepted and named in the summary", async () => {
    const { result } = await runWithTests({ agentSource: AGENT_WITH_GUARDIAN_LOGGED_CHANGE });
    expect(result.status).toBe("deployed_live");
    const report = JSON.parse(readFileSync(join(result.logFolder, "tests-report.json"), "utf8"));
    expect(report.changed).toEqual(["reminders-copy-title.test.ts"]);
    const summary = readFileSync(join(result.logFolder, "summary.md"), "utf8");
    expect(summary).toContain("Changed by test-guardian: reminders-copy-title.test.ts.");
    expect(summary).toContain("TEST_CHANGES.md has new entries");
  });

  it("a failing copy test still stops the job before any deploy", async () => {
    const { result, deploy } = await runWithTests({ agentSource: AGENT_THAT_ADDS_A_TEST, testsPass: false });
    expect(result.status).toBe("failed");
    expect(result.reason).toBe("check failed");
    expect(deploy.deployCalls).toEqual([]);
  });
});

describe("the sandbox checkout", () => {
  it("links the checkout, copies in the job's tests and page, and leaves the checkout untouched", () => {
    const { scratch, checkout } = makeScratchWithGuard();
    const bundle = remindersBundle();
    const jobFolder = join(scratch, "job");
    mkdirSync(join(jobFolder, "sidekick"), { recursive: true });
    const repaired = bundle.html.replace("<title>Reminders</title>", "<title>Repaired</title>");
    writeFileSync(join(jobFolder, "sidekick", "index.html"), repaired);
    writeFileSync(join(jobFolder, "sidekick", "manifest.json"), bundle.manifestText);
    writeTestsFolder(jobFolder, { "reminders-copy-title.test.ts": COPY_TEST_TITLE, [TEST_LOG_FILE]: COPY_LOG });

    const sandboxRoot = join(scratch, "sandbox");
    const sandboxBackend = buildSandboxCheckout({ checkoutRoot: checkout, sidekickId: "reminders", jobFolder, sandboxRoot });
    expect(sandboxBackend).toBe(join(sandboxRoot, "backend"));
    expect(lstatSync(join(sandboxBackend, "scripts")).isSymbolicLink()).toBe(true);
    expect(lstatSync(join(sandboxRoot, "docs")).isSymbolicLink()).toBe(true);
    expect(lstatSync(join(sandboxBackend, "test")).isDirectory()).toBe(true);
    expect(listFilesRecursively(join(sandboxBackend, "test"))).toEqual([TEST_LOG_FILE, "reminders-copy-title.test.ts"]);
    expect(readFileSync(join(sandboxRoot, "sidekicks", "reminders", "index.html"), "utf8")).toBe(repaired);
    // The checkout's own page and tests are as they were.
    expect(readFileSync(join(checkout, "sidekicks", "reminders", "index.html"), "utf8")).toBe(bundle.html);
    expect(listFilesRecursively(join(checkout, "backend", "test"))).toEqual(["other-sidekick.test.ts", "reminders-logic.test.ts", "reminders-wording.test.ts"]);
    expect(existsSync(join(jobFolder, "sidekick.check"))).toBe(false);
  });

  it("runCopyTests removes the sandbox afterwards, pass, fail or crash", async () => {
    const { scratch, checkout } = makeScratchWithGuard();
    const bundle = remindersBundle();
    const jobFolder = join(scratch, "job");
    mkdirSync(join(jobFolder, "sidekick"), { recursive: true });
    writeFileSync(join(jobFolder, "sidekick", "index.html"), bundle.html);
    writeFileSync(join(jobFolder, "sidekick", "manifest.json"), bundle.manifestText);
    writeTestsFolder(jobFolder, { "reminders-copy-title.test.ts": COPY_TEST_TITLE });
    const sandboxRoot = sandboxRootFor(jobFolder);

    let seenDuringTests = "";
    const passing = await runCopyTests({ checkoutRoot: checkout, sidekickId: "reminders", jobFolder, runTests: async ({ sandboxBackend }: { sandboxBackend: string }) => {
      seenDuringTests = readFileSync(join(sandboxBackend, "..", "sidekicks", "reminders", "index.html"), "utf8");
      return { ok: true, output: "ok" };
    } });
    expect(passing.ok).toBe(true);
    expect(seenDuringTests).toBe(bundle.html);
    expect(existsSync(sandboxRoot)).toBe(false);

    const failing = await runCopyTests({ checkoutRoot: checkout, sidekickId: "reminders", jobFolder, runTests: async () => ({ ok: false, output: "1 failed" }) });
    expect(failing.ok).toBe(false);
    expect(existsSync(sandboxRoot)).toBe(false);

    await expect(runCopyTests({ checkoutRoot: checkout, sidekickId: "reminders", jobFolder, runTests: async () => { throw new Error("vitest crashed"); } })).rejects.toThrow("vitest crashed");
    expect(existsSync(sandboxRoot)).toBe(false);
  });

  it("really runs vitest in a sandbox of this repo: the copy's tests pass against the page, and fail when the page breaks", async () => {
    const { scratch } = makeScratch();
    const bundle = remindersBundle();
    const jobFolder = join(scratch, "real-job");
    mkdirSync(join(jobFolder, "sidekick"), { recursive: true });
    writeFileSync(join(jobFolder, "sidekick", "index.html"), bundle.html);
    writeFileSync(join(jobFolder, "sidekick", "manifest.json"), bundle.manifestText);
    writeTestsFolder(jobFolder, { "reminders-copy-title.test.ts": COPY_TEST_TITLE, "reminders-copy-manifest.test.ts": COPY_TEST_MANIFEST, [TEST_LOG_FILE]: COPY_LOG });

    const passing = await runCopyTests({ checkoutRoot: REPO_ROOT, sidekickId: "reminders", jobFolder, runTests: runVitestInSandbox });
    expect(passing.ok).toBe(true);
    expect(passing.output).toMatch(/Test Files\s+2 passed/);

    writeFileSync(join(jobFolder, "sidekick", "index.html"), bundle.html.replace("<title>", "<titl"));
    const failing = await runCopyTests({ checkoutRoot: REPO_ROOT, sidekickId: "reminders", jobFolder, runTests: runVitestInSandbox });
    expect(failing.ok).toBe(false);
    expect(failing.output).toContain("copy title");
    expect(existsSync(sandboxRootFor(jobFolder))).toBe(false);
  }, 120_000);
});

describe("deploy carries the tests", () => {
  it("points --dir at the staged deploy folder, which holds the tests, and adds no --tests flag", () => {
    const args = deployArgs({ sidekickId: "reminders", userId: "user-77", deployFolder: "/jobs/rep-t1.deploy" });
    expect(args).toEqual(["scripts/deploy-sidekick.mjs", "reminders", "--env", "live", "--user", "user-77", "--dir", "/jobs/rep-t1.deploy"]);
    expect(args).not.toContain("--tests");
    expect(deployFolderFor("/jobs/rep-t1")).toBe("/jobs/rep-t1.deploy");
  });
});
