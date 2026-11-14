// Checks a repaired Sidekick the way a deploy would: the deploy gate (forbidden primitives,
// manifest), the shield (runner/core-checks/, checkRepair) and the copy's own tests (tests/ in the job folder: the ones the copy came with plus
// any the agent added). The tests read sidekicks/<id>/index.html from a repo by a fixed relative
// path, so they run in a sandbox checkout: a folder of symlinks into the runner's own checkout,
// with backend/test replaced by the job's tests and sidekicks/<id> by the job's page. The
// runner's checkout is never written.
import { execFile } from "node:child_process";
import { cpSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, symlinkSync } from "node:fs";
import { dirname, join } from "node:path";
import { pathToFileURL } from "node:url";
import { TOOLS_FILE, presentSidekickFiles } from "./job-folder.mjs";
import { TESTS_FOLDER } from "./copy-tests.mjs";
import { codeEnvironment } from "./safe-env.mjs";
import { nodeInstallFolder, prepareSandbox, sandboxProfilePathFor, sandboxedInvocation } from "./sandbox.mjs";

// The deploy gate from the checkout being used, so the runner and deploy-sidekick.mjs agree.
async function loadBundleTools(checkoutRoot) {
  const bundleToolsPath = join(checkoutRoot, "backend", "scripts", "bundle-tools.mjs");
  return import(pathToFileURL(bundleToolsPath).href);
}

// Deploy gate only. Returns a list of problems; empty means it would pass the gate. toolsText is
// the copy's tools.js, or null when it has none (jess router, 2026-10-21): an agent block without
// tools.js, a tool without a handler or a copied block that no longer matches the page is refused.
export async function gateProblems({ checkoutRoot, sidekickId, html, manifestText, toolsText = null }) {
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
  // The agent block's own problems are already in validateManifest's list
  for (const toolsProblem of bundleTools.sidekickToolsProblems(manifest, toolsText, html, sidekickId)) {
    if (!toolsProblem.startsWith("manifest.json: ")) {
      problems.push(toolsProblem);
    }
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
  for (const fileName of presentSidekickFiles(jobFolder)) {
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
// It also runs under the macOS sandbox (sandbox.mjs): it reads only the node install and the
// checkout, writes only the sandbox checkout, never the checkout, the job folder (whose page gets
// deployed) or its own profile, and has no network. HOME is a private folder in the sandbox, for
// vitest's and npm's own files. homeFolder is the home the profile protects; injectable for the
// runner's own tests.
export function runVitestInSandbox({ sandboxBackend, sandboxRoot, checkoutRoot, jobFolder, homeFolder }) {
  const nodeFolder = nodeInstallFolder();
  const { profilePath, sandboxHome } = prepareSandbox({
    sandboxRoot,
    homeFolder,
    readableFolders: [nodeFolder, checkoutRoot],
    writableFolders: [],
    protectedFolders: [checkoutRoot, jobFolder],
  });
  const plainEnvironment = codeEnvironment(process.env);
  // npx from the install the profile allows, whatever else PATH holds.
  const searchPath = [dirname(process.execPath), plainEnvironment.PATH ?? "/usr/bin:/bin"].join(":");
  // NO_COLOR: the output goes to the log and to the agent, so plain text.
  const environment = { ...plainEnvironment, PATH: searchPath, HOME: sandboxHome, NO_COLOR: "1" };
  const invocation = sandboxedInvocation({ profilePath, command: "npx", args: VITEST_NPX_ARGS });
  return new Promise((resolve) => {
    const options = { cwd: sandboxBackend, env: environment, encoding: "utf8", maxBuffer: 50 * 1024 * 1024 };
    execFile(invocation.command, invocation.args, options, function finishVitest(error, stdout, stderr) {
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
    rmSync(sandboxProfilePathFor(sandboxRoot), { force: true });
  }
}

// The shield (runner/core-checks/shield.mjs), loaded from the checkout being used like the deploy
// gate: the runner's own checkout, which the agent cannot edit, never the job folder.
export async function loadShield(checkoutRoot) {
  const shieldPath = join(checkoutRoot, "runner", "core-checks", "shield.mjs");
  return import(pathToFileURL(shieldPath).href);
}

// A copy's files from a folder holding index.html, manifest.json and maybe tools.js (the job's
// sidekick/ folder, or the "before" snapshot in the log folder).
export function readCopyFolder(folder) {
  const toolsPath = join(folder, TOOLS_FILE);
  return {
    html: readFileSync(join(folder, "index.html"), "utf8"),
    manifestText: readFileSync(join(folder, "manifest.json"), "utf8"),
    toolsText: existsSync(toolsPath) ? readFileSync(toolsPath, "utf8") : null,
  };
}

// The tools whose answers the repair may change: outcome.json "changedTools", the tools the agent
// says the request names. Missing or not yet written (the agent's check runs before it finishes)
// means none. Read here, not through outcome.mjs, which keeps only the fields it knows.
export function requestedToolsFromOutcome(jobFolder) {
  const outcomePath = join(jobFolder, "outcome.json");
  if (!existsSync(outcomePath)) {
    return [];
  }
  let outcome;
  try {
    outcome = JSON.parse(readFileSync(outcomePath, "utf8"));
  } catch {
    return [];
  }
  const named = outcome?.changedTools;
  if (!Array.isArray(named)) {
    return [];
  }
  return named.filter(function isToolName(name) {
    return typeof name === "string";
  });
}

// The shield against the job's page: the copy as it was (beforeFolder) against the copy now.
// records: the person's records. Resolves with the shield's result ({ ok, checks, changedTools }).
export async function runShieldForJob({ checkoutRoot, sidekickId, jobFolder, beforeFolder, records, requestedTools, openPageImplementation, now }) {
  const shield = await loadShield(checkoutRoot);
  const options = {
    checkoutRoot,
    sidekickId,
    before: readCopyFolder(beforeFolder),
    after: readCopyFolder(join(jobFolder, "sidekick")),
    records,
    requestedTools: requestedTools ?? requestedToolsFromOutcome(jobFolder),
  };
  if (openPageImplementation !== undefined) {
    options.openPageImplementation = openPageImplementation;
  }
  if (now !== undefined) {
    options.now = now;
  }
  const result = await shield.runShield(options);
  return { ...result, problems: shield.shieldProblems(result), report: shield.shieldReport(result) };
}

// A repair's full check (docs/briefs/repair-lanes.md W1): the deploy gate, then the shield and the
// copy's own tests. Every repair goes through this; checkSidekick alone is the gate and tests.
// Returns { ok, problems, testOutput, shield } (shield null when the gate already refused).
export async function checkRepair({ checkoutRoot, sidekickId, jobFolder, beforeFolder, records, requestedTools, runTests, openPageImplementation, now }) {
  const html = readFileSync(join(jobFolder, "sidekick", "index.html"), "utf8");
  const manifestText = readFileSync(join(jobFolder, "sidekick", "manifest.json"), "utf8");
  const toolsPath = join(jobFolder, "sidekick", TOOLS_FILE);
  const toolsText = existsSync(toolsPath) ? readFileSync(toolsPath, "utf8") : null;
  const gate = await gateProblems({ checkoutRoot, sidekickId, html, manifestText, toolsText });
  if (gate.length > 0) {
    return { ok: false, problems: gate, testOutput: "", shield: null };
  }
  const shield = await runShieldForJob({ checkoutRoot, sidekickId, jobFolder, beforeFolder, records, requestedTools, openPageImplementation, now });
  // A copy the shield refuses is not published whatever its tests say: skip the slow test run
  if (!shield.ok) {
    return { ok: false, problems: shield.problems, testOutput: "", shield };
  }
  const testResult = await runCopyTests({ checkoutRoot, sidekickId, jobFolder, runTests });
  if (!testResult.ok) {
    return { ok: false, problems: ["Sidekick tests failed"], testOutput: testResult.output, shield };
  }
  return { ok: true, problems: [], testOutput: testResult.output, shield };
}

// Gate first, then tests. Returns { ok, problems, testOutput }.
export async function checkSidekick({ checkoutRoot, sidekickId, jobFolder, runTests }) {
  const html = readFileSync(join(jobFolder, "sidekick", "index.html"), "utf8");
  const manifestText = readFileSync(join(jobFolder, "sidekick", "manifest.json"), "utf8");
  const toolsPath = join(jobFolder, "sidekick", TOOLS_FILE);
  const toolsText = existsSync(toolsPath) ? readFileSync(toolsPath, "utf8") : null;
  const problems = await gateProblems({ checkoutRoot, sidekickId, html, manifestText, toolsText });
  if (problems.length > 0) {
    return { ok: false, problems, testOutput: "" };
  }
  const testResult = await runCopyTests({ checkoutRoot, sidekickId, jobFolder, runTests });
  if (!testResult.ok) {
    return { ok: false, problems: ["Sidekick tests failed"], testOutput: testResult.output };
  }
  return { ok: true, problems: [], testOutput: testResult.output };
}
