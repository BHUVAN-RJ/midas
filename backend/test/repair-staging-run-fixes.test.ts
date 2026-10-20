// Fixes from the first real staging run (2026-10-19, report 13edb182; lead items 11 and 12).
//   11 every wrangler call runs from backend/ with npx --no-install (npx waited 30 minutes on a
//      hidden "install wrangler?" prompt when run from the repo root), the read-back has a
//      timeout, and a failed read-back names the real environment.
//   12 the agent reaches its two tools at a path without spaces (the clone lives under
//      "~/Library/Application Support"), the prompt gives the exact command, and that command
//      matches the allow rule.
import { execFileSync } from "node:child_process";
import { cpSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { agentAllowedTools, buildClaudeArgs, checkToolCommand, linkAgentTools } from "../../runner/lib/agent.mjs";
import { createBackendClient } from "../../runner/lib/backend.mjs";
import { VITEST_NPX_ARGS } from "../../runner/lib/check.mjs";
import { BACKEND_HOSTS, startupSettings } from "../../runner/lib/config.mjs";
import { READ_BACK_TIMEOUT_MS, readLiveUserPointer, verifyPointer } from "../../runner/lib/deploy.mjs";
import { buildSystemPrompt } from "../../runner/lib/prompt.mjs";
import { runJob } from "../../runner/lib/run-job.mjs";
import { wranglerInvocation } from "../scripts/wrangler.mjs";
import {
  AGENT_THAT_FIXES_TITLE,
  REPO_ROOT,
  RUNNER_TOKEN,
  fakeDeployThatLands,
  fakeFetchWithoutStoredTests,
  makeScratch,
  standardAssets,
  startFakeBackend,
  writeStubAgent,
} from "./helpers/runner-fixture";

const savedRunnerEnv = process.env.MIDAS_RUNNER_ENV;

afterEach(() => {
  if (savedRunnerEnv === undefined) {
    delete process.env.MIDAS_RUNNER_ENV;
  } else {
    process.env.MIDAS_RUNNER_ENV = savedRunnerEnv;
  }
});

function scratchFolder(): string {
  return realpathSync(mkdtempSync(join(tmpdir(), "midas-staging-fixes-")));
}

describe("11: wrangler and npx never wait on a hidden install prompt", () => {
  it("runs wrangler with npx --no-install from backend/, wherever the caller's cwd is", () => {
    const invocation = wranglerInvocation(["r2", "object", "get", "bucket/key", "--pipe", "--remote"]);
    expect(invocation.command).toBe("npx");
    expect(invocation.args.slice(0, 2)).toEqual(["--no-install", "wrangler"]);
    expect(invocation.args.slice(2)).toEqual(["r2", "object", "get", "bucket/key", "--pipe", "--remote"]);
    expect(resolve(invocation.cwd)).toBe(resolve(REPO_ROOT, "backend"));
  });

  it("runs the sandbox's vitest with npx --no-install", () => {
    expect(VITEST_NPX_ARGS[0]).toBe("--no-install");
    expect(VITEST_NPX_ARGS[1]).toBe("vitest");
  });

  it("gives the read-back a timeout", async () => {
    const checkout = scratchFolder();
    const scriptsFolder = join(checkout, "backend", "scripts");
    mkdirSync(scriptsFolder, { recursive: true });
    for (const fileName of ["bundle-tools.mjs", "environments.mjs"]) {
      cpSync(join(REPO_ROOT, "backend", "scripts", fileName), join(scriptsFolder, fileName));
    }
    // A stand-in for the checkout's wrangler.mjs that answers with the options it was given.
    writeFileSync(join(scriptsFolder, "wrangler.mjs"), [
      "export function captureWrangler(wranglerArgs, options = {}) {",
      "  return JSON.stringify({ version: 'v-1', contentHash: 'h', wranglerArgs, timeoutMs: options.timeoutMs ?? null });",
      "}",
    ].join("\n"));
    process.env.MIDAS_RUNNER_ENV = "staging";
    const pointer = await readLiveUserPointer({ checkoutRoot: checkout, sidekickId: "reminders", userId: "user-1" });
    expect(pointer.timeoutMs).toBe(READ_BACK_TIMEOUT_MS);
    expect(READ_BACK_TIMEOUT_MS).toBeLessThanOrEqual(5 * 60_000);
    expect(pointer.wranglerArgs[3]).toMatch(/^midas-bundles-staging\//);
  });

  it("names the environment the read-back used, not always live", () => {
    expect(verifyPointer({ pointer: null, expectedHash: "h", environmentName: "staging" })).toBe("the user's current.json could not be read back from staging");
    process.env.MIDAS_RUNNER_ENV = "staging";
    expect(verifyPointer({ pointer: null, expectedHash: "h" })).toBe("the user's current.json could not be read back from staging");
    expect(verifyPointer({ pointer: { version: "v", contentHash: "other" }, expectedHash: "h" })).toBe("staging has content hash other, expected h");
    delete process.env.MIDAS_RUNNER_ENV;
    expect(verifyPointer({ pointer: null, expectedHash: "h" })).toBe("the user's current.json could not be read back from live");
  });
});

describe("12: the agent's tools work from a clone whose path has a space", () => {
  // A copy of runner/ under "Application Support", the way runner/README.md tells the founder
  // to clone, and the tool link folder the runner uses.
  function spacedClone() {
    const scratch = scratchFolder();
    const spacedRoot = join(scratch, "Library", "Application Support", "midas-runner", "midas");
    cpSync(join(REPO_ROOT, "runner"), join(spacedRoot, "runner"), { recursive: true });
    return { scratch, toolsFolder: join(spacedRoot, "runner", "tools"), linkRoot: join(scratch, "runner-home") };
  }

  it("links the tools at a plain path whose command matches the allow rule exactly and runs", () => {
    const { toolsFolder, linkRoot } = spacedClone();
    expect(toolsFolder).toContain(" ");
    const toolPaths = linkAgentTools({ linkRoot, toolsFolder });
    expect(toolPaths.checkToolPath).not.toMatch(/\s/);
    expect(toolPaths.intelToolPath).not.toMatch(/\s/);
    expect(realpathSync(toolPaths.checkToolPath)).toBe(join(toolsFolder, "check.mjs"));

    const prompt = buildSystemPrompt({
      job: { id: "r", sidekickId: "reminders", kind: "change", transcript: "x", createdAt: "2026-10-19T10:00:00.000Z" },
      reportFiles: ["transcript.txt"],
      manifestText: readFileSync(join(REPO_ROOT, "sidekicks", "reminders", "manifest.json"), "utf8"),
      ...toolPaths,
    });
    const command = checkToolCommand(toolPaths.checkToolPath);
    expect(prompt).toContain(`\`${command}\``);
    const rules = agentAllowedTools(toolPaths);
    expect(rules).toContain(`Bash(${command}:*)`);
    expect(buildClaudeArgs({ systemPromptPath: "/p", model: "opus", maxTurns: 5, ...toolPaths })).toContain(`Bash(${command}:*)`);

    // The command as the prompt gives it starts the real tool (it reports its missing settings).
    let failure: { status: number; stderr: string } | null = null;
    try {
      execFileSync(process.execPath, [toolPaths.checkToolPath], { encoding: "utf8", env: { PATH: process.env.PATH ?? "" }, stdio: ["ignore", "pipe", "pipe"] });
    } catch (error) {
      failure = error as { status: number; stderr: string };
    }
    expect(failure?.status).toBe(2);
    expect(failure?.stderr).toContain("MIDAS_JOB_FOLDER, MIDAS_RUNNER_CHECKOUT and MIDAS_JOB_SIDEKICK_ID must be set");
  });

  it("replaces a link that points at another clone, and refuses a link folder with a space", () => {
    const first = spacedClone();
    const second = spacedClone();
    linkAgentTools({ linkRoot: first.linkRoot, toolsFolder: first.toolsFolder });
    const relinked = linkAgentTools({ linkRoot: first.linkRoot, toolsFolder: second.toolsFolder });
    expect(realpathSync(relinked.checkToolPath)).toBe(join(second.toolsFolder, "check.mjs"));
    expect(() => linkAgentTools({ linkRoot: join(first.scratch, "has space"), toolsFolder: first.toolsFolder })).toThrow(/without spaces/);
    const environment = { MIDAS_BACKEND_URL: `https://${BACKEND_HOSTS.staging}`, MIDAS_RUNNER_TOKEN: "t", MIDAS_RUNNER_ENV: "staging", MIDAS_RUNNER_TOOL_LINKS: join(first.scratch, "has space") };
    expect(() => startupSettings(environment)).toThrow(/MIDAS_RUNNER_TOOL_LINKS/);
  });

  it("tells the agent to run the commands bare: no quotes, pipes or redirects", () => {
    for (const sidekickId of ["reminders", "care-reminders"]) {
      const template = readFileSync(join(REPO_ROOT, "runner", "agents", `${sidekickId}.md`), "utf8");
      expect(template).toContain("Run both commands exactly as written here: `node`, then the path bare (never in quotes),");
      expect(template).toContain("no `2>&1`, `|`, `>` or `;` after them");
    }
  });

  it("runJob gives the agent the linked paths in its prompt", async () => {
    const { scratch, settings } = makeScratch();
    const linkRoot = join(scratch, "runner-home");
    const backendServer = await startFakeBackend({ id: "rep-link-1", user_id: "user-1", sidekick_id: "reminders", transcript: "rename" }, standardAssets());
    try {
      const backend = createBackendClient({ baseUrl: backendServer.baseUrl, token: RUNNER_TOKEN });
      const job = await backend.claimJob();
      const deploy = fakeDeployThatLands();
      const result = await runJob(job, {
        backend,
        settings: { ...settings, toolLinkRoot: linkRoot },
        agentCommand: process.execPath,
        agentArgs: [writeStubAgent(scratch, AGENT_THAT_FIXES_TITLE)],
        runFetch: fakeFetchWithoutStoredTests().runFetch,
        runTests: async function passingTests() {
          return { ok: true, output: "all passed" };
        },
        runDeploy: deploy.runDeploy,
        readPointer: deploy.readPointer,
        notify: async function ignoreNotification() {},
      });
      expect(result.status).toBe("deployed_live");
      const systemPrompt = readFileSync(join(result.logFolder, "system-prompt.md"), "utf8");
      expect(systemPrompt).toContain(`\`node ${join(linkRoot, "runner-tools", "check.mjs")}\``);
      expect(systemPrompt).toContain(`\`node ${join(linkRoot, "runner-tools", "intel.mjs")} list\``);
    } finally {
      await backendServer.close();
    }
  });
});
