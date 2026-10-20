// Checks a repaired Sidekick the way a deploy would: the deploy gate (forbidden primitives,
// manifest) and the copy's own tests (tests/ in the job folder: the ones the copy came with plus
// any the agent added). The tests read sidekicks/<id>/index.html from a repo by a fixed relative
// path, so they run in a sandbox checkout: a folder of symlinks into the runner's own checkout,
// with backend/test replaced by the job's tests and sidekicks/<id> by the job's page. The
// runner's checkout is never written.
import { execFile } from "node:child_process";
import { cpSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, symlinkSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { SIDEKICK_FILES } from "./job-folder.mjs";
import { TESTS_FOLDER } from "./copy-tests.mjs";
import { codeEnvironment } from "./safe-env.mjs";

// The deploy gate from the checkout being used, so the runner and deploy-sidekick.mjs agree.
async function loadBundleTools(checkoutRoot) {
  const bundleToolsPath = join(checkoutRoot, "backend", "scripts", "bundle-tools.mjs");
  return import(pathToFileURL(bundleToolsPath).href);
}

// Deploy gate only. Returns a list of problems; empty means it would pass the gate.
export async function gateProblems({ checkoutRoot, sidekickId, html, manifestText }) {
  const bundleTools = await loadBundleTools(checkoutRoot);
  const problems = [];
  const violations = bundleTools.findForbiddenPrimitives(html);
  if (violations.length > 0) {
    problems.push(`deploy gate rejected: ${violations.join(", ")}`);
  }
  let manifest;
  try {
    manifest = JSON.parse(manifestText);
  } catch {
    problems.push("manifest.json is not JSON");
    return problems;
  }
  const manifestProblems = bundleTools.validateManifest(manifest, sidekickId);
  for (const manifestProblem of manifestProblems) {
    problems.push(`manifest.json: ${manifestProblem}`);
  }
  return problems;
}

function linkEntriesExcept(sourceFolder, targetFolder, skipNames) {
  mkdirSync(targetFolder, { recursive: true });
  for (const entry of readdirSync(sourceFolder)) {
    if (skipNames.includes(entry)) {
      continue;
    }
    symlinkSync(join(sourceFolder, entry), join(targetFolder, entry));
  }
}

// Builds the sandbox checkout at sandboxRoot (replaced if it exists). Everything is a symlink
// into checkoutRoot except: backend/test (a copy of the job's tests/) and sidekicks/<id> (a copy
// of the job's sidekick/). Returns the sandbox's backend folder.
export function buildSandboxCheckout({ checkoutRoot, sidekickId, jobFolder, sandboxRoot }) {
  rmSync(sandboxRoot, { recursive: true, force: true });
  linkEntriesExcept(checkoutRoot, sandboxRoot, ["backend", "sidekicks", ".git"]);

  const backendFolder = join(sandboxRoot, "backend");
  linkEntriesExcept(join(checkoutRoot, "backend"), backendFolder, ["test"]);
  const testFolder = join(backendFolder, "test");
  mkdirSync(testFolder, { recursive: true });
  const jobTestsFolder = join(jobFolder, TESTS_FOLDER);
  if (existsSync(jobTestsFolder)) {
    cpSync(jobTestsFolder, testFolder, { recursive: true });
  }

  const sidekicksFolder = join(sandboxRoot, "sidekicks");
  const checkoutSidekicks = join(checkoutRoot, "sidekicks");
  if (existsSync(checkoutSidekicks)) {
    linkEntriesExcept(checkoutSidekicks, sidekicksFolder, [sidekickId]);
  } else {
    mkdirSync(sidekicksFolder, { recursive: true });
  }
  const pageFolder = join(sidekicksFolder, sidekickId);
  mkdirSync(pageFolder, { recursive: true });
  for (const fileName of SIDEKICK_FILES) {
    cpSync(join(jobFolder, "sidekick", fileName), join(pageFolder, fileName));
  }
  return backendFolder;
}

// npx with --no-install: the sandbox's backend/ links the checkout's node_modules, and a missing
// vitest must fail at once, not wait on npx's hidden install prompt.
export const VITEST_NPX_ARGS = ["--no-install", "vitest", "run", "--dir", "test", "--passWithNoTests"];

// Runs vitest over the sandbox's backend/test. Resolves with { ok, output }. Injectable so the
// runner's own tests do not start vitest inside vitest. The tests are the agent's to write, so
// vitest gets only the plain process settings (safe-env.mjs codeEnvironment): no runner token,
// no Claude login, nothing from ~/.midas-runner/env, whether the runner or the check tool runs it.
export function runVitestInSandbox({ sandboxBackend }) {
  return new Promise((resolve) => {
    // NO_COLOR: the output goes to the log and to the agent, so plain text.
    const environment = { ...codeEnvironment(process.env), NO_COLOR: "1" };
    const options = { cwd: sandboxBackend, env: environment, encoding: "utf8", maxBuffer: 50 * 1024 * 1024 };
    execFile("npx", VITEST_NPX_ARGS, options, function finishVitest(error, stdout, stderr) {
      const output = `${stdout}\n${stderr}`;
      resolve({ ok: error === null, output });
    });
  });
}

// Where the sandbox lives: beside the job folder, never inside it (the job folder must hold
// nothing but the Sidekick, the report, the tests and the outcome).
export function sandboxRootFor(jobFolder) {
  return `${jobFolder}.check`;
}

// The copy's tests against the job's page. Resolves with { ok, output }.
export async function runCopyTests({ checkoutRoot, sidekickId, jobFolder, runTests = runVitestInSandbox }) {
  const sandboxRoot = sandboxRootFor(jobFolder);
  const sandboxBackend = buildSandboxCheckout({ checkoutRoot, sidekickId, jobFolder, sandboxRoot });
  try {
    return await runTests({ sandboxBackend, sandboxRoot, checkoutRoot, sidekickId, jobFolder });
  } finally {
    rmSync(sandboxRoot, { recursive: true, force: true });
  }
}

// Gate first, then tests. Returns { ok, problems, testOutput }.
export async function checkSidekick({ checkoutRoot, sidekickId, jobFolder, runTests }) {
  const html = readFileSync(join(jobFolder, "sidekick", "index.html"), "utf8");
  const manifestText = readFileSync(join(jobFolder, "sidekick", "manifest.json"), "utf8");
  const problems = await gateProblems({ checkoutRoot, sidekickId, html, manifestText });
  if (problems.length > 0) {
    return { ok: false, problems, testOutput: "" };
  }
  const testResult = await runCopyTests({ checkoutRoot, sidekickId, jobFolder, runTests });
  if (!testResult.ok) {
    return { ok: false, problems: ["Sidekick tests failed"], testOutput: testResult.output };
  }
  return { ok: true, problems: [], testOutput: testResult.output };
}
