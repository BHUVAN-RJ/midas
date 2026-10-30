// Tests move every copy forward (founder, 2026-10-13, docs/briefs/repair-contract.md "Settled"):
// each user copy carries its own tests and its own TEST_CHANGES.md. A repair job gets them in
// tests/. The repair agent may add test files but never change or delete one; only the
// test-guardian subagent may, and it logs every accept and refusal in tests/TEST_CHANGES.md.
// The runner compares every pre-existing test file byte for byte after the agent and fails the
// job on a change that the log does not account for.
import { execFile } from "node:child_process";
import { cpSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { REPO_ROOT, runnerEnvironment } from "./config.mjs";

export const TESTS_FOLDER = "tests";
export const TEST_LOG_FILE = "TEST_CHANGES.md";
// Written by the deploy beside the test files in R2; the fetch brings it down. Not a test: the
// deploy rebuilds it, so it never enters the job folder.
export const TESTS_INDEX_FILE = "index.json";

// One name, flat, no path parts, no hidden files: what a test file in tests/ may be called
// (same rule as bundle-tools.mjs TEST_FILE_NAME_PATTERN).
const TEST_FILE_NAME = /^[A-Za-z0-9][A-Za-z0-9._-]{0,120}$/;

// The copy's tests come down with the checkout's fetch-sidekick-copy.mjs (repair-copies,
// 2026-10-13): node scripts/fetch-sidekick-copy.mjs <id> --env live --user <uid> --out <dir>.
// environmentName is the job's environment (the runner serves live and staging, founder
// 2026-10-21); without one, MIDAS_RUNNER_ENV as before.
export function fetchArgs({ sidekickId, userId, outFolder, environmentName = runnerEnvironment() }) {
  return ["scripts/fetch-sidekick-copy.mjs", sidekickId, "--env", environmentName, "--user", userId, "--out", outFolder];
}

// Runs the fetch script in <checkout>/backend. Resolves with { ok, output }.
export function runFetchScript({ checkoutRoot, args, timeoutMs = 5 * 60_000 }) {
  return new Promise((resolve) => {
    const options = { cwd: join(checkoutRoot, "backend"), encoding: "utf8", maxBuffer: 20 * 1024 * 1024, timeout: timeoutMs };
    execFile(process.execPath, args, options, function finishFetch(error, stdout, stderr) {
      resolve({ ok: error === null, output: `${stdout}\n${stderr}` });
    });
  });
}

// Where the fetch lands: beside the job folder, never inside it.
export function fetchFolderFor(jobFolder) {
  return `${jobFolder}.fetch`;
}

// Reads the fetched tests/ folder: every plain file except the index. Throws on a bad name.
export function readFetchedTests(outFolder) {
  const testsFolder = join(outFolder, TESTS_FOLDER);
  const files = {};
  if (!existsSync(testsFolder)) {
    return files;
  }
  for (const entry of readdirSync(testsFolder, { withFileTypes: true })) {
    if (!entry.isFile() || entry.name === TESTS_INDEX_FILE) {
      continue;
    }
    if (!TEST_FILE_NAME.test(entry.name)) {
      throw new Error(`fetched tests have a bad file name: ${JSON.stringify(entry.name)}`);
    }
    files[entry.name] = readFileSync(join(testsFolder, entry.name), "utf8");
  }
  return files;
}

// The tests for this job: the reporter's stored copy tests when the copy has any, else the base
// Sidekick's from the checkout (a copy made before tests were stored, or a user with no copy
// yet). Resolves with { files, source, output }; throws when the fetch script fails.
export async function fetchCopyTests({ checkoutRoot, sidekickId, userId, jobFolder, runFetch = runFetchScript, environmentName = runnerEnvironment() }) {
  const outFolder = fetchFolderFor(jobFolder);
  rmSync(outFolder, { recursive: true, force: true });
  try {
    const args = fetchArgs({ sidekickId, userId, outFolder, environmentName });
    const fetched = await runFetch({ checkoutRoot, args, outFolder });
    if (!fetched.ok) {
      throw new Error(`fetch-sidekick-copy failed: ${fetched.output.trim().split("\n").slice(-3).join(" / ")}`);
    }
    const files = readFetchedTests(outFolder);
    const testFileNames = Object.keys(files).filter((name) => name !== TEST_LOG_FILE);
    if (testFileNames.length === 0) {
      const base = baseTestsFromCheckout({ checkoutRoot, sidekickId });
      return { ...base, output: fetched.output };
    }
    return { files, source: "user copy", output: fetched.output };
  } finally {
    rmSync(outFolder, { recursive: true, force: true });
  }
}

// Until intake serves a copy's tests, a copy's tests are the base Sidekick's (a new copy starts
// with them, per the contract): backend/test/<id>-*.test.ts from the runner's checkout, plus an
// empty log.
export function baseTestsFromCheckout({ checkoutRoot, sidekickId }) {
  const testFolder = join(checkoutRoot, "backend", "test");
  const files = {};
  if (existsSync(testFolder)) {
    const prefix = `${sidekickId}-`;
    for (const entry of readdirSync(testFolder, { withFileTypes: true })) {
      if (entry.isFile() && entry.name.startsWith(prefix) && entry.name.endsWith(".test.ts")) {
        files[entry.name] = readFileSync(join(testFolder, entry.name), "utf8");
      }
    }
  }
  files[TEST_LOG_FILE] = "";
  return { files, source: "base checkout" };
}

export function writeTestsFolder(jobFolder, files) {
  const testsFolder = join(jobFolder, TESTS_FOLDER);
  mkdirSync(testsFolder, { recursive: true });
  for (const [name, content] of Object.entries(files)) {
    writeFileSync(join(testsFolder, name), content);
  }
  if (!existsSync(join(testsFolder, TEST_LOG_FILE))) {
    writeFileSync(join(testsFolder, TEST_LOG_FILE), "");
  }
  return testsFolder;
}

// Every file in tests/ as bytes, keyed by name.
export function readTestsFolder(jobFolder) {
  const testsFolder = join(jobFolder, TESTS_FOLDER);
  const files = {};
  if (!existsSync(testsFolder)) {
    return files;
  }
  for (const entry of readdirSync(testsFolder, { withFileTypes: true })) {
    if (entry.isFile()) {
      files[entry.name] = readFileSync(join(testsFolder, entry.name));
    }
  }
  return files;
}

// Saves tests/ outside the job folder, for the comparison after the agent.
export function snapshotTests(jobFolder, snapshotFolder) {
  const testsFolder = join(jobFolder, TESTS_FOLDER);
  mkdirSync(snapshotFolder, { recursive: true });
  if (existsSync(testsFolder)) {
    cpSync(testsFolder, snapshotFolder, { recursive: true });
  }
}

function linesOf(text) {
  return text.split("\n").map((line) => line.trimEnd()).filter((line) => line.length > 0);
}

// Did the guardian log a change to this file? The log must keep every line it had and gain at
// least one line naming the file. (The agent cannot write the log: the guard hook in the job
// folder denies it; only the test-guardian subagent passes.)
export function guardianLogged({ logBefore, logAfter, fileName }) {
  const before = linesOf(logBefore);
  const after = linesOf(logAfter);
  const kept = before.every((line) => after.includes(line));
  if (!kept) {
    return false;
  }
  const newLines = after.filter((line) => !before.includes(line));
  return newLines.some((line) => line.includes(fileName));
}

// Compares tests/ before and after the agent. Returns { added, changed, deleted, problems }:
// problems is empty when every pre-existing file is byte-identical or its change or deletion is
// logged.
export function compareTests({ before, after }) {
  const added = [];
  const changed = [];
  const deleted = [];
  const problems = [];
  const logBefore = (before[TEST_LOG_FILE] ?? Buffer.alloc(0)).toString("utf8");
  const logAfter = (after[TEST_LOG_FILE] ?? Buffer.alloc(0)).toString("utf8");

  for (const name of Object.keys(before)) {
    if (name === TEST_LOG_FILE) {
      continue;
    }
    if (!(name in after)) {
      deleted.push(name);
      // A deletion passes only when the guardian logged it, like a change (founder, 2026-10-25:
      // the guardian removes a removed feature's test, reminders.md "A feature removed").
      if (!guardianLogged({ logBefore, logAfter, fileName: name })) {
        problems.push(`test deleted: ${name}`);
      }
      continue;
    }
    if (!before[name].equals(after[name])) {
      changed.push(name);
      if (!guardianLogged({ logBefore, logAfter, fileName: name })) {
        problems.push(`test changed without a test-guardian entry in ${TEST_LOG_FILE}: ${name}`);
      }
    }
  }
  for (const name of Object.keys(after)) {
    if (!(name in before) && name !== TEST_LOG_FILE) {
      added.push(name);
    }
  }
  if (TEST_LOG_FILE in before && !(TEST_LOG_FILE in after)) {
    problems.push(`${TEST_LOG_FILE} deleted`);
  } else if (!linesOf(logBefore).every((line) => linesOf(logAfter).includes(line))) {
    problems.push(`${TEST_LOG_FILE} lost entries`);
  }
  return { added, changed, deleted, problems, logGrew: logAfter.length > logBefore.length };
}

// The guard files the repair agent's own Claude session needs: the PreToolUse hook that lets
// only test-guardian change a test, the settings that install it, and the guardian itself.
// Copied from the runner's checkout, so the founder's current versions apply.
export const AGENT_SETTINGS_FILES = [
  join(".claude", "settings.json"),
  join(".claude", "hooks", "guard_tests.py"),
  join(".claude", "agents", "test-guardian.md"),
];

// The job's guardian is the Sidekick test guardian, not the shell's (founder, 2026-10-30): the
// user's request is the authority for their copy, and a test that only pins placement, order or
// looks never blocks it. It is a runner file like the repair prompts (prompt.mjs), read from the
// runner's own code; inside the job it keeps the name test-guardian, so the hook passes it.
export const SIDEKICK_GUARDIAN_SOURCE = join(REPO_ROOT, "runner", "agents", "sidekick-test-guardian.md");
const JOB_GUARDIAN_PATH = join(".claude", "agents", "test-guardian.md");

function agentSettingsSourcePath({ checkoutRoot, relativePath }) {
  if (relativePath === JOB_GUARDIAN_PATH) {
    return SIDEKICK_GUARDIAN_SOURCE;
  }
  return join(checkoutRoot, relativePath);
}

export function writeAgentSettings({ jobFolder, checkoutRoot }) {
  for (const relativePath of AGENT_SETTINGS_FILES) {
    const sourcePath = agentSettingsSourcePath({ checkoutRoot, relativePath });
    if (!existsSync(sourcePath)) {
      throw new Error(`checkout has no ${relativePath}; the repair agent needs the test guard`);
    }
    const targetPath = join(jobFolder, relativePath);
    mkdirSync(join(targetPath, ".."), { recursive: true });
    cpSync(sourcePath, targetPath);
  }
}
