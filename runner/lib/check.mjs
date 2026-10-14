// Checks a repaired Sidekick the way a deploy would: the deploy gate (forbidden primitives,
// manifest) and the Sidekick's own tests. The tests live in backend/test/<sidekick>-*.test.ts and
// read sidekicks/<id>/index.html from the repo by a fixed path, so the job's files are copied
// into the runner's own checkout for the run and the originals are put back afterwards, always.
import { execFile } from "node:child_process";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { SIDEKICK_FILES } from "./job-folder.mjs";

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

// Runs vitest for the Sidekick's test files in the checkout's backend. Resolves with
// { ok, output }. Injectable so the runner's own tests do not start vitest inside vitest.
export function runVitestForSidekick({ checkoutRoot, sidekickId }) {
  return new Promise((resolve) => {
    const backendFolder = join(checkoutRoot, "backend");
    const vitestArgs = ["vitest", "run", `test/${sidekickId}-`, "--passWithNoTests"];
    execFile("npx", vitestArgs, { cwd: backendFolder, encoding: "utf8", maxBuffer: 50 * 1024 * 1024 }, function finishVitest(error, stdout, stderr) {
      const output = `${stdout}\n${stderr}`;
      resolve({ ok: error === null, output });
    });
  });
}

// Copies the job's Sidekick files into the checkout's sidekicks/<id>/, runs the tests, restores.
export async function runSidekickTests({ checkoutRoot, sidekickId, jobFolder, runTests = runVitestForSidekick }) {
  const checkoutSidekickFolder = join(checkoutRoot, "sidekicks", sidekickId);
  if (!existsSync(checkoutSidekickFolder)) {
    return { ok: false, output: `checkout has no sidekicks/${sidekickId}/` };
  }
  const originals = {};
  for (const fileName of SIDEKICK_FILES) {
    originals[fileName] = readFileSync(join(checkoutSidekickFolder, fileName));
  }
  try {
    for (const fileName of SIDEKICK_FILES) {
      const repairedBytes = readFileSync(join(jobFolder, "sidekick", fileName));
      writeFileSync(join(checkoutSidekickFolder, fileName), repairedBytes);
    }
    return await runTests({ checkoutRoot, sidekickId });
  } finally {
    for (const fileName of SIDEKICK_FILES) {
      writeFileSync(join(checkoutSidekickFolder, fileName), originals[fileName]);
    }
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
  const testResult = await runSidekickTests({ checkoutRoot, sidekickId, jobFolder, runTests });
  if (!testResult.ok) {
    return { ok: false, problems: ["Sidekick tests failed"], testOutput: testResult.output };
  }
  return { ok: true, problems: [], testOutput: testResult.output };
}
