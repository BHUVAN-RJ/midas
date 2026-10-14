// Publishes a checked fix to the reporter's live copy (founder, 2026-10-13: the runner publishes
// the fix itself). The runner's own Node code runs deploy-sidekick.mjs from its checkout with
// --user <reporter> --dir <job>/sidekick: the reporter's copy only, never the base. Then it reads
// the user's current.json back from the live bucket and compares the content hash with the files
// it meant to publish. Only a match counts as deployed.
import { execFile } from "node:child_process";
import { cpSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { runnerEnvironment } from "./config.mjs";

export const LIVE_ENVIRONMENT = "live";

// Same rule as bundle-tools.mjs USER_ID_PATTERN: the id from the users table.
const USER_ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;
const SIDEKICK_ID_PATTERN = /^[a-z0-9-]{1,40}$/;

// What deploy-sidekick.mjs --dir reads: index.html, manifest.json and tests/ (the copy's tests
// and its TEST_CHANGES.md; contract, "Tests move every copy forward"). The runner stages them
// in one folder beside the job folder and removes it afterwards.
export function deployFolderFor(jobFolder) {
  return `${jobFolder}.deploy`;
}

export function stageDeployFolder({ jobFolder, deployFolder }) {
  rmSync(deployFolder, { recursive: true, force: true });
  mkdirSync(deployFolder, { recursive: true });
  for (const fileName of ["index.html", "manifest.json"]) {
    cpSync(join(jobFolder, "sidekick", fileName), join(deployFolder, fileName));
  }
  const testsFolder = join(jobFolder, "tests");
  mkdirSync(join(deployFolder, "tests"), { recursive: true });
  if (existsSync(testsFolder)) {
    for (const entry of readdirSync(testsFolder, { withFileTypes: true })) {
      if (entry.isFile() && entry.name !== "index.json") {
        cpSync(join(testsFolder, entry.name), join(deployFolder, "tests", entry.name));
      }
    }
  }
  return deployFolder;
}

// The deploy command's arguments, after "node", run from the checkout's backend/ folder. Throws
// instead of building a base deploy: a missing or malformed user id never becomes a command.
export function deployArgs({ sidekickId, userId, deployFolder }) {
  if (typeof sidekickId !== "string" || !SIDEKICK_ID_PATTERN.test(sidekickId)) {
    throw new Error(`refusing to deploy: bad Sidekick id "${sidekickId}"`);
  }
  if (typeof userId !== "string" || !USER_ID_PATTERN.test(userId)) {
    throw new Error(`refusing to deploy: no valid reporter user id ("${userId}"); the runner never deploys the base`);
  }
  if (typeof deployFolder !== "string" || deployFolder.length === 0) {
    throw new Error("refusing to deploy: no deploy folder");
  }
  return ["scripts/deploy-sidekick.mjs", sidekickId, "--env", runnerEnvironment(), "--user", userId, "--dir", deployFolder];
}

// Runs the deploy script in <checkout>/backend. Resolves with { ok, output }.
export function runDeployScript({ checkoutRoot, args, timeoutMs = 10 * 60_000 }) {
  return new Promise((resolve) => {
    const backendFolder = join(checkoutRoot, "backend");
    const options = { cwd: backendFolder, encoding: "utf8", maxBuffer: 20 * 1024 * 1024, timeout: timeoutMs };
    execFile(process.execPath, args, options, function finishDeploy(error, stdout, stderr) {
      const output = `${stdout}\n${stderr}`;
      resolve({ ok: error === null, output, exitCode: error === null ? 0 : error.code });
    });
  });
}

async function loadCheckoutModule(checkoutRoot, fileName) {
  const modulePath = join(checkoutRoot, "backend", "scripts", fileName);
  return import(pathToFileURL(modulePath).href);
}

// The content hash of the files the runner is about to publish, computed with the checkout's own
// bundle-tools.mjs so the runner and deploy-sidekick.mjs agree on it.
export async function expectedContentHash({ checkoutRoot, jobFolder }) {
  const bundleTools = await loadCheckoutModule(checkoutRoot, "bundle-tools.mjs");
  const html = readFileSync(join(jobFolder, "sidekick", "index.html"), "utf8");
  const manifestText = readFileSync(join(jobFolder, "sidekick", "manifest.json"), "utf8");
  return bundleTools.bundleContentHash(html, manifestText);
}

// Reads the reporter's current.json back from the live bucket with wrangler (the checkout's own
// helper and environment table). Returns the parsed pointer, or null when it cannot be read.
export async function readLiveUserPointer({ checkoutRoot, sidekickId, userId }) {
  const bundleTools = await loadCheckoutModule(checkoutRoot, "bundle-tools.mjs");
  const environments = await loadCheckoutModule(checkoutRoot, "environments.mjs");
  const wrangler = await loadCheckoutModule(checkoutRoot, "wrangler.mjs");
  const bucket = environments.ENVIRONMENTS[runnerEnvironment()].bucket;
  const key = bundleTools.pointerKeyFor(sidekickId, userId);
  try {
    const text = wrangler.captureWrangler(["r2", "object", "get", `${bucket}/${key}`, "--pipe", "--remote"]);
    return JSON.parse(text);
  } catch {
    return null;
  }
}

// Does the pointer read back name the files we published? Returns null when it does, else the
// reason it does not.
export function verifyPointer({ pointer, expectedHash }) {
  if (pointer === null || typeof pointer !== "object") {
    return "the user's current.json could not be read back from live";
  }
  if (typeof pointer.version !== "string" || pointer.version.length === 0) {
    return "the user's current.json names no version";
  }
  if (pointer.contentHash !== expectedHash) {
    return `live has content hash ${pointer.contentHash ?? "none"}, expected ${expectedHash}`;
  }
  return null;
}

// Deploy, then verify. Resolves with { ok, version, output, problem }. Injectable pieces for the
// runner's own tests: runDeploy (the script) and readPointer (the read-back).
export async function publishFix({ checkoutRoot, sidekickId, userId, jobFolder, runDeploy = runDeployScript, readPointer = readLiveUserPointer }) {
  const deployFolder = deployFolderFor(jobFolder);
  const args = deployArgs({ sidekickId, userId, deployFolder });
  const expectedHash = await expectedContentHash({ checkoutRoot, jobFolder });
  stageDeployFolder({ jobFolder, deployFolder });
  try {
    const deployResult = await runDeploy({ checkoutRoot, args });
    if (!deployResult.ok) {
      return { ok: false, version: null, output: deployResult.output, problem: `deploy script exited with code ${deployResult.exitCode ?? "unknown"}` };
    }
    const pointer = await readPointer({ checkoutRoot, sidekickId, userId });
    const problem = verifyPointer({ pointer, expectedHash });
    if (problem !== null) {
      return { ok: false, version: pointer?.version ?? null, output: deployResult.output, problem };
    }
    return { ok: true, version: pointer.version, contentHash: expectedHash, output: deployResult.output, problem: null };
  } finally {
    rmSync(deployFolder, { recursive: true, force: true });
  }
}
