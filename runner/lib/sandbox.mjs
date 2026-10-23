// The macOS sandbox (Seatbelt, /usr/bin/sandbox-exec) that every run of code the repair agent
// wrote goes through: the copy's vitest, whether the runner or the agent's check tool starts it
// (security review, 2026-10-22). safe-env.mjs keeps the tokens out of the environment; this keeps
// the files on disk out of reach: no reading anything in the founder's home folder except the
// node install, the checkout and the job, no writing anywhere in it except the sandbox checkout,
// and no network at all. Claude Code's own sandbox uses the same mechanism.
import { execFile } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { createServer } from "node:net";
import { homedir, tmpdir } from "node:os";
import { dirname, join } from "node:path";

export const SANDBOX_EXEC = "/usr/bin/sandbox-exec";

// Inside the sandbox root: the profile, and the home folder the sandboxed code gets (vitest and
// npm write their own files under HOME, so it must point somewhere writable that is not yours).
export const PROFILE_FILE_NAME = "sandbox.sb";
export const SANDBOX_HOME_NAME = "home";

// A path goes into the profile as a quoted string; one that could end the string is refused.
function profileString(path) {
  if (/["\\\n\r]/.test(path)) {
    throw new Error(`sandbox: the path ${path} has a quote, backslash or line break and cannot go into the sandbox profile`);
  }
  return `"${path}"`;
}

// Seatbelt matches real paths (/tmp is /private/tmp), so every folder is resolved first.
function realFolder(path) {
  return realpathSync(path);
}

function subpathList(folders) {
  const parts = [];
  for (const folder of folders) {
    parts.push(`(subpath ${profileString(realFolder(folder))})`);
  }
  return parts.join(" ");
}

// The node install the runner runs on (…/versions/node/v22/bin/node -> …/versions/node/v22), so
// node and npx can load their own files when that install sits in the home folder (nvm).
export function nodeInstallFolder(nodePath = process.execPath) {
  return dirname(dirname(realpathSync(nodePath)));
}

// The profile text. Later rules win in Seatbelt, so each deny comes before its exceptions.
// file-read-data, not file-read*: node looks up the folders above the checkout (names and sizes)
// to resolve real paths; their contents stay unreadable.
export function sandboxProfile({ homeFolder = homedir(), readableFolders, writableFolders }) {
  const home = profileString(realFolder(homeFolder));
  const lines = [
    "(version 1)",
    "(allow default)",
    "(deny network*)",
    `(deny file-read-data (subpath ${home}))`,
    `(allow file-read-data (literal ${home}) ${subpathList([...readableFolders, ...writableFolders])})`,
    `(deny file-write* (subpath ${home}))`,
    `(allow file-write* ${subpathList(writableFolders)})`,
  ];
  return `${lines.join("\n")}\n`;
}

// Writes the profile and the private home into sandboxRoot. Returns what a sandboxed run needs:
// { profilePath, sandboxHome }.
export function prepareSandbox({ sandboxRoot, homeFolder = homedir(), readableFolders, writableFolders }) {
  const sandboxHome = join(sandboxRoot, SANDBOX_HOME_NAME);
  mkdirSync(sandboxHome, { recursive: true });
  const profileText = sandboxProfile({ homeFolder, readableFolders, writableFolders: [sandboxRoot, ...writableFolders] });
  const profilePath = join(sandboxRoot, PROFILE_FILE_NAME);
  writeFileSync(profilePath, profileText);
  return { profilePath, sandboxHome };
}

// The command line that runs `command args` under the profile.
export function sandboxedInvocation({ profilePath, command, args }) {
  return { command: SANDBOX_EXEC, args: ["-f", profilePath, command, ...args] };
}

// Run inside the sandbox by the self-test: each attempt prints one line, "<name> blocked" or
// "<name> allowed". Reads the canary, connects to the runner's local port, writes in the home
// folder, and writes in the sandbox root (that one must work, or the sandbox is just broken).
const SELF_TEST_PROBE = `
const { readFileSync, writeFileSync } = require("node:fs");
const { connect } = require("node:net");
const [canaryPath, homeWritePath, sandboxWritePath, port] = process.argv.slice(1);
function attempt(name, action) {
  try { action(); console.log(name + " allowed"); } catch { console.log(name + " blocked"); }
}
attempt("read-home", function readCanary() { readFileSync(canaryPath); });
attempt("write-home", function writeHome() { writeFileSync(homeWritePath, "x"); });
attempt("write-sandbox", function writeSandbox() { writeFileSync(sandboxWritePath, "x"); });
const socket = connect(Number(port), "127.0.0.1");
socket.on("connect", function reportConnected() { console.log("network allowed"); socket.destroy(); });
socket.on("error", function reportRefused() { console.log("network blocked"); });
`;

// What each probe line must say for the sandbox to count as working.
const EXPECTED_PROBE_LINES = ["read-home blocked", "write-home blocked", "write-sandbox allowed", "network blocked"];

function listenOnLocalPort() {
  return new Promise((resolve, reject) => {
    const server = createServer(function closeIncoming(socket) {
      socket.destroy();
    });
    server.on("error", reject);
    server.listen(0, "127.0.0.1", function reportPort() {
      resolve(server);
    });
  });
}

function runProbe({ invocation }) {
  return new Promise((resolve) => {
    execFile(invocation.command, invocation.args, { encoding: "utf8", timeout: 30_000 }, function finishProbe(error, stdout, stderr) {
      resolve({ error, stdout, stderr });
    });
  });
}

// Runs the probe under a real profile and returns a list of problems; empty means the sandbox
// blocks what it must and still lets the job write its own files. The canary stands in for
// ~/.midas-runner/env: a file in the home folder outside every allowed folder. homeFolder and
// sandboxExec are injectable for the runner's own tests.
export async function sandboxSelfTestProblems({ homeFolder = homedir(), sandboxExec = SANDBOX_EXEC, nodePath = process.execPath } = {}) {
  if (!existsSync(sandboxExec)) {
    return [`${sandboxExec} is missing; the runner needs the macOS sandbox to run the agent's tests`];
  }
  const canaryFolder = join(homeFolder, ".midas-runner");
  mkdirSync(canaryFolder, { recursive: true });
  const canaryPath = join(canaryFolder, "sandbox-canary");
  writeFileSync(canaryPath, "the sandbox must not let this be read\n");
  const homeWritePath = join(homeFolder, ".midas-runner", "sandbox-write-probe");
  rmSync(homeWritePath, { force: true });

  const sandboxRoot = realpathSync(mkdtempSync(join(tmpdir(), "midas-sandbox-check-")));
  const server = await listenOnLocalPort();
  try {
    const { profilePath } = prepareSandbox({ sandboxRoot, homeFolder, readableFolders: [nodeInstallFolder(nodePath)], writableFolders: [] });
    const probeArgs = ["-e", SELF_TEST_PROBE, canaryPath, homeWritePath, join(sandboxRoot, "write-probe"), String(server.address().port)];
    const invocation = { command: sandboxExec, args: ["-f", profilePath, nodePath, ...probeArgs] };
    const { error, stdout, stderr } = await runProbe({ invocation });
    if (error !== null && stdout.trim() === "") {
      return [`the sandbox self-test could not run: ${(stderr || error.message).trim()}`];
    }
    const lines = stdout.trim().split("\n");
    const problems = [];
    for (const expected of EXPECTED_PROBE_LINES) {
      if (!lines.includes(expected)) {
        const name = expected.split(" ")[0];
        const seen = lines.find(function lineForName(line) {
          return line.startsWith(`${name} `);
        });
        problems.push(`sandbox self-test: expected "${expected}", got "${seen ?? "nothing"}"`);
      }
    }
    return problems;
  } finally {
    server.close();
    rmSync(sandboxRoot, { recursive: true, force: true });
    rmSync(homeWritePath, { force: true });
    rmSync(canaryPath, { force: true });
  }
}

// For runner.mjs and run-once.mjs: throws with every problem when the sandbox does not work.
export async function requireWorkingSandbox(options = {}) {
  const problems = await sandboxSelfTestProblems(options);
  if (problems.length > 0) {
    throw new Error(`the runner will not start: ${problems.join("; ")}`);
  }
}
