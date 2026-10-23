// Security fix (founder go, 2026-10-22; docs/concerns/2026-10-13-repair-runner.md §4): the repair
// agent and the tests it writes could read any file on the Mac (~/.midas-runner/env, the wrangler
// login, ~/.ssh) and the tests could send it out.
//   agent  its file tools only read and write the job folder; secret folders are denied outright
//   tests  the copy's vitest runs under the macOS sandbox: no reading the home folder, no writing
//          outside the sandbox checkout (not even the job's page), no network
//   start  the runner does not start when the sandbox is missing or does not block
import { chmodSync, existsSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { createServer, type Server } from "node:net";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { AGENT_DENIED_TOOLS, AGENT_SECRET_PATHS, agentAllowedTools, buildClaudeArgs } from "../../runner/lib/agent.mjs";
import { runCopyTests, runVitestInSandbox } from "../../runner/lib/check.mjs";
import { writeTestsFolder } from "../../runner/lib/copy-tests.mjs";
import { requireWorkingSandbox, sandboxProfile, sandboxSelfTestProblems } from "../../runner/lib/sandbox.mjs";
import { REPO_ROOT, makeScratch, remindersBundle } from "./helpers/runner-fixture";

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

function listenLocally(): Promise<Server> {
  return new Promise((resolve) => {
    const server = createServer(function closeIncoming(socket) {
      socket.destroy();
    });
    server.listen(0, "127.0.0.1", function reportReady() {
      resolve(server);
    });
  });
}

function portOf(server: Server): number {
  const address = server.address();
  if (address === null || typeof address === "string") {
    throw new Error("no port");
  }
  return address.port;
}

// A home folder for the test: the runner's env file with a fake token, and a jobs folder inside it,
// the way the real jobs sit in ~/Library/Application Support/midas-runner.
function fakeHomeWithSecret(scratch: string) {
  const home = realpathSync(scratch);
  const secretPath = join(home, ".midas-runner", "env");
  mkdirSync(join(home, ".midas-runner"), { recursive: true });
  writeFileSync(secretPath, "MIDAS_RUNNER_TOKEN=fake-secret-for-the-sandbox-test\n");
  const jobFolder = join(home, "Library", "Application Support", "midas-runner", "jobs", "rep-sandbox");
  return { home, secretPath, jobFolder };
}

// The copy test an attacker would write: read the env file, overwrite the page the runner is about
// to deploy, phone home. Each must throw inside the sandbox; the test passes only if all three do.
function hostileCopyTest({ secretPath, pagePath, port }: { secretPath: string; pagePath: string; port: number }): string {
  return [
    'import { readFileSync, writeFileSync } from "node:fs";',
    'import { connect } from "node:net";',
    'import { expect, it } from "vitest";',
    `it("cannot read the runner's env file", () => {`,
    `  expect(() => readFileSync(${JSON.stringify(secretPath)}, "utf8")).toThrow(/EPERM/);`,
    "});",
    `it("cannot change the job's page", () => {`,
    `  expect(() => writeFileSync(${JSON.stringify(pagePath)}, "<p>replaced</p>")).toThrow(/EPERM/);`,
    "});",
    `it("cannot open a network connection", async () => {`,
    "  const outcome = await new Promise((resolve) => {",
    `    const socket = connect(${port}, "127.0.0.1");`,
    '    socket.on("connect", function connected() { socket.destroy(); resolve("connected"); });',
    '    socket.on("error", function refused(error) { resolve(error.code); });',
    "  });",
    '  expect(outcome).not.toBe("connected");',
    "});",
    "",
  ].join("\n");
}

describe("agent: file tools reach the job folder only", () => {
  const args = buildClaudeArgs({ systemPromptPath: "/tmp/prompt.md", model: "opus", maxTurns: 5, intelToolPath: "/r/tools/intel.mjs", checkToolPath: "/r/tools/check.mjs" });

  it("allows reading and editing only under the job folder", () => {
    const allowed = flagList(args, "--allowedTools");
    expect(allowed).toContain("Read(./**)");
    expect(allowed).toContain("Edit(./**)");
    for (const unrestricted of ["Read", "Edit", "Write", "Read(*)", "Edit(*)", "Read(**)", "Edit(**)"]) {
      expect(allowed).not.toContain(unrestricted);
    }
    expect(agentAllowedTools()).not.toContain("Read");
  });

  it("denies reading and editing the runner's env file, Claude's config, SSH keys and the Cloudflare login", () => {
    const denied = flagList(args, "--disallowedTools");
    for (const secretPath of ["~/.midas-runner/**", "~/.claude/**", "~/.ssh/**", "~/Library/Preferences/.wrangler/**", "~/Library/Keychains/**"]) {
      expect(AGENT_SECRET_PATHS).toContain(secretPath);
      expect(denied).toContain(`Read(${secretPath})`);
      expect(denied).toContain(`Edit(${secretPath})`);
    }
    expect(denied).toEqual(AGENT_DENIED_TOOLS);
  });

  it("denies editing the job's own .claude settings, hook and guardian", () => {
    expect(flagList(args, "--disallowedTools")).toContain("Edit(./.claude/**)");
  });
});

describe("tests: the copy's vitest runs under the macOS sandbox", () => {
  it("a copy test cannot read the env file, change the page or reach the network, and the copy's own tests still run", async () => {
    const { scratch } = makeScratch();
    const { home, secretPath, jobFolder } = fakeHomeWithSecret(scratch);
    const bundle = remindersBundle();
    mkdirSync(join(jobFolder, "sidekick"), { recursive: true });
    const pagePath = join(jobFolder, "sidekick", "index.html");
    writeFileSync(pagePath, bundle.html);
    writeFileSync(join(jobFolder, "sidekick", "manifest.json"), bundle.manifestText);
    const server = await listenLocally();
    let connections = 0;
    server.on("connection", function countConnection() {
      connections += 1;
    });
    try {
      writeTestsFolder(jobFolder, { "reminders-copy-hostile.test.ts": hostileCopyTest({ secretPath, pagePath, port: portOf(server) }) });
      const result = await runCopyTests({
        checkoutRoot: REPO_ROOT,
        sidekickId: "reminders",
        jobFolder,
        runTests: function sandboxedWithFakeHome(options: { sandboxBackend: string; sandboxRoot: string; checkoutRoot: string }) {
          return runVitestInSandbox({ ...options, homeFolder: home });
        },
      });
      expect(result.output).toMatch(/Tests\s+3 passed/);
      expect(result.ok).toBe(true);
      expect(readFileSync(pagePath, "utf8")).toBe(bundle.html);
      expect(connections).toBe(0);
    } finally {
      server.close();
    }
  }, 120_000);
});

describe("start: the runner checks the sandbox before it runs anything", () => {
  it("passes on this Mac's real sandbox", async () => {
    const { scratch } = makeScratch();
    expect(await sandboxSelfTestProblems({ homeFolder: realpathSync(scratch) })).toEqual([]);
    expect(existsSync(join(scratch, ".midas-runner", "sandbox-canary"))).toBe(false);
  }, 60_000);

  it("refuses when sandbox-exec is missing", async () => {
    const { scratch } = makeScratch();
    const problems = await sandboxSelfTestProblems({ homeFolder: realpathSync(scratch), sandboxExec: join(scratch, "no-sandbox-exec") });
    expect(problems).toHaveLength(1);
    expect(problems[0]).toContain("is missing");
    await expect(requireWorkingSandbox({ homeFolder: realpathSync(scratch), sandboxExec: join(scratch, "no-sandbox-exec") })).rejects.toThrow(/the runner will not start: .*is missing/);
  });

  it("refuses a sandbox-exec that runs the code without blocking anything", async () => {
    const { scratch } = makeScratch();
    // Takes "-f <profile> <command> ..." like the real one and runs the command unsandboxed.
    const fakeSandboxExec = join(scratch, "fake-sandbox-exec");
    writeFileSync(fakeSandboxExec, '#!/bin/sh\nshift 2\nexec "$@"\n');
    chmodSync(fakeSandboxExec, 0o755);
    const problems = await sandboxSelfTestProblems({ homeFolder: realpathSync(scratch), sandboxExec: fakeSandboxExec });
    expect(problems).toContain('sandbox self-test: expected "read-home blocked", got "read-home allowed"');
    expect(problems).toContain('sandbox self-test: expected "write-home blocked", got "write-home allowed"');
    expect(problems).toContain('sandbox self-test: expected "network blocked", got "network allowed"');
  }, 60_000);

  it("runner.mjs and run-once.mjs wait for the check before claiming a job", () => {
    for (const binName of ["runner.mjs", "run-once.mjs"]) {
      const source = readFileSync(join(REPO_ROOT, "runner", "bin", binName), "utf8");
      const checkAt = source.indexOf("await requireWorkingSandbox()");
      expect(checkAt).toBeGreaterThan(-1);
      expect(checkAt).toBeLessThan(source.indexOf("createBackendClient({"));
    }
  });

  it("refuses a path that could break out of the profile's quoted string", () => {
    const { scratch } = makeScratch();
    const unsafeFolder = join(scratch, 'bad"folder');
    mkdirSync(unsafeFolder);
    expect(() => sandboxProfile({ homeFolder: scratch, readableFolders: [unsafeFolder], writableFolders: [] })).toThrow(/cannot go into the sandbox profile/);
  });
});
