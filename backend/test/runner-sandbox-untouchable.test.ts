// Founder, 2026-10-22: "the agents should not be able to touch the sandbox".
//   agent  deny rules for the runner's code (checkout, tool link: no edits) and for the logs and
//          this job's sandbox checkout and profile (no reads, no edits), passed by runJob itself
//   tests  the copy's vitest cannot rewrite its own profile, the checkout or the job folder, even
//          where those are outside the home folder the profile already closes
//   start  the self-test fails when the profile can be rewritten
import { chmodSync, existsSync, mkdirSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { randomBytes } from "node:crypto";
import { describe, expect, it } from "vitest";
import { buildClaudeArgs, jobPathRules } from "../../runner/lib/agent.mjs";
import { createBackendClient } from "../../runner/lib/backend.mjs";
import { runCopyTests, runVitestInSandbox, sandboxRootFor } from "../../runner/lib/check.mjs";
import { writeTestsFolder } from "../../runner/lib/copy-tests.mjs";
import { agentPathLimits, runJob } from "../../runner/lib/run-job.mjs";
import { sandboxProfile, sandboxProfilePathFor, sandboxSelfTestProblems } from "../../runner/lib/sandbox.mjs";
import {
  REPO_ROOT,
  RUNNER_TOKEN,
  fakeDeployThatLands,
  fakeFetchWithoutStoredTests,
  makeScratch,
  remindersBundle,
  standardAssets,
  startFakeBackend,
} from "./helpers/runner-fixture";

// Everything after a list flag until the next "--" flag.
function flagList(args: string[], flag: string): string[] {
  const index = args.indexOf(flag);
  expect(index).toBeGreaterThan(-1);
  const values: string[] = [];
  for (let position = index + 1; position < args.length && !args[position].startsWith("--"); position += 1) {
    values.push(args[position]);
  }
  return values;
}

describe("agent: deny rules for the runner's code, the logs and the sandbox", () => {
  it("turns absolute patterns into Claude Code's // rules: code read-only, logs and sandbox closed", () => {
    expect(jobPathRules({ noEditPaths: ["/checkout/**"], noReadPaths: ["/logs/**"] })).toEqual(["Edit(//checkout/**)", "Read(//logs/**)", "Edit(//logs/**)"]);
    const args = buildClaudeArgs({ systemPromptPath: "/p", model: "opus", maxTurns: 5, intelToolPath: "/r/i.mjs", checkToolPath: "/r/c.mjs", noEditPaths: ["/checkout/**"], noReadPaths: ["/logs/**"] });
    const denied = flagList(args, "--disallowedTools");
    expect(denied).toContain("Edit(//checkout/**)");
    expect(denied).not.toContain("Read(//checkout/**)");
    expect(denied).toContain("Read(//logs/**)");
    expect(denied).toContain("Edit(//logs/**)");
  });

  it("names the checkout, the tool link, the logs, the sandbox checkout and its profile", () => {
    const limits = agentPathLimits({ settings: { checkoutRoot: "/checkout", toolLinkRoot: "/links", logsRoot: "/logs" }, jobFolder: "/jobs/rep-1" });
    expect(limits.noEditPaths).toEqual(["/checkout/**", "/links/**"]);
    expect(limits.noReadPaths).toEqual(["/logs/**", "/jobs/rep-1.check/**", "/jobs/rep-1.check.sb"]);
  });

  it("runJob gives the real claude command line those rules for this job's own paths", async () => {
    const { scratch, settings } = makeScratch();
    // A stand-in for claude that only records its arguments, one per line.
    const recordPath = join(scratch, "claude-args.txt");
    const fakeClaude = join(scratch, "fake-claude");
    writeFileSync(fakeClaude, `#!/bin/sh\nprintf '%s\\n' "$@" > ${JSON.stringify(recordPath)}\nexit 0\n`);
    chmodSync(fakeClaude, 0o755);
    const backendServer = await startFakeBackend({ id: "rep-untouchable", user_id: "user-1", sidekick_id: "reminders", transcript: "title" }, standardAssets(), []);
    try {
      const backend = createBackendClient({ baseUrl: backendServer.baseUrl, token: RUNNER_TOKEN });
      const job = await backend.claimJob();
      const deploy = fakeDeployThatLands();
      await runJob(job, {
        backend,
        settings,
        agentCommand: fakeClaude,
        runFetch: fakeFetchWithoutStoredTests().runFetch,
        runTests: async function passingTests() {
          return { ok: true, output: "all passed" };
        },
        runDeploy: deploy.runDeploy,
        readPointer: deploy.readPointer,
        notify: async function ignoreNotification() {},
      });
      const recorded = readFileSync(recordPath, "utf8").split("\n");
      const denied = flagList(recorded, "--disallowedTools");
      const jobFolder = join(settings.jobsRoot, "rep-untouchable");
      expect(denied).toContain(`Edit(/${settings.checkoutRoot}/**)`);
      expect(denied).toContain(`Edit(/${settings.toolLinkRoot}/**)`);
      expect(denied).toContain(`Read(/${settings.logsRoot}/**)`);
      expect(denied).toContain(`Read(/${jobFolder}.check/**)`);
      expect(denied).toContain(`Edit(/${jobFolder}.check.sb)`);
      expect(deploy.deployCalls).toEqual([]);
    } finally {
      await backendServer.close();
    }
  });
});

describe("tests: the copy's vitest cannot change its sandbox, the checkout or the job", () => {
  it("cannot rewrite its profile, add a file to the checkout or change the page, with all three outside the protected home", async () => {
    const homeScratch = makeScratch();
    const jobScratch = makeScratch();
    // The home the profile closes holds none of the three, so only the explicit protection counts.
    const home = realpathSync(homeScratch.scratch);
    const jobFolder = join(realpathSync(jobScratch.scratch), "jobs", "rep-untouchable");
    const bundle = remindersBundle();
    mkdirSync(join(jobFolder, "sidekick"), { recursive: true });
    const pagePath = join(jobFolder, "sidekick", "index.html");
    writeFileSync(pagePath, bundle.html);
    writeFileSync(join(jobFolder, "sidekick", "manifest.json"), bundle.manifestText);
    const checkoutProbePath = join(REPO_ROOT, "runner", "lib", `.sandbox-probe-${randomBytes(6).toString("hex")}`);
    const profilePath = sandboxProfilePathFor(sandboxRootFor(jobFolder));
    const hostileTest = [
      'import { writeFileSync } from "node:fs";',
      'import { expect, it } from "vitest";',
      'it("cannot rewrite the sandbox profile", () => {',
      `  expect(() => writeFileSync(${JSON.stringify(profilePath)}, "(version 1)\\n(allow default)\\n")).toThrow(/EPERM/);`,
      "});",
      'it("cannot add a file to the checkout", () => {',
      `  expect(() => writeFileSync(${JSON.stringify(checkoutProbePath)}, "x")).toThrow(/EPERM/);`,
      "});",
      'it("cannot change the job page", () => {',
      `  expect(() => writeFileSync(${JSON.stringify(pagePath)}, "<p>replaced</p>")).toThrow(/EPERM/);`,
      "});",
      "",
    ].join("\n");
    writeTestsFolder(jobFolder, { "reminders-copy-untouchable.test.ts": hostileTest });
    try {
      const result = await runCopyTests({
        checkoutRoot: REPO_ROOT,
        sidekickId: "reminders",
        jobFolder,
        runTests: function sandboxedWithFakeHome(options: { sandboxBackend: string; sandboxRoot: string; checkoutRoot: string; jobFolder: string }) {
          return runVitestInSandbox({ ...options, homeFolder: home });
        },
      });
      expect(result.output).toMatch(/Tests\s+3 passed/);
      expect(result.ok).toBe(true);
      expect(readFileSync(pagePath, "utf8")).toBe(bundle.html);
      expect(existsSync(checkoutProbePath)).toBe(false);
      expect(existsSync(profilePath)).toBe(false);
    } finally {
      rmSync(checkoutProbePath, { force: true });
    }
  }, 120_000);

  it("the profile sits beside the sandbox checkout, not inside its writable folder", () => {
    expect(sandboxProfilePathFor("/jobs/rep-1.check")).toBe("/jobs/rep-1.check.sb");
    const { scratch } = makeScratch();
    const root = realpathSync(scratch);
    const text = sandboxProfile({ homeFolder: root, readableFolders: [], writableFolders: [join(root)], protectedPaths: [join(root, "missing-yet.sb")] });
    const lines = text.trim().split("\n");
    expect(lines[lines.length - 1]).toBe(`(deny file-write* (subpath "${join(root, "missing-yet.sb")}"))`);
  });
});

describe("start: the self-test checks the profile cannot be rewritten", () => {
  it("fails a sandbox-exec that lets the profile be written", async () => {
    const { scratch } = makeScratch();
    // Takes "-f <profile> <command> ..." like the real one and runs the command unsandboxed.
    const fakeSandboxExec = join(scratch, "fake-sandbox-exec");
    writeFileSync(fakeSandboxExec, '#!/bin/sh\nshift 2\nexec "$@"\n');
    chmodSync(fakeSandboxExec, 0o755);
    const problems = await sandboxSelfTestProblems({ homeFolder: realpathSync(scratch), sandboxExec: fakeSandboxExec });
    expect(problems).toContain('sandbox self-test: expected "write-profile blocked", got "write-profile allowed"');
  }, 60_000);
});
