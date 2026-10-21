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

// What deploy-sidekick.mjs --dir reads: index.html, manifest.json, tools.js when the copy has one,
// and tests/ (the copy's tests and its TEST_CHANGES.md; contract, "Tests move every copy
// forward"). The runner stages them
// in one folder beside the job folder and removes it afterwards.
export function deployFolderFor(jobFolder) {
  return `${jobFolder}.deploy`;
}

export function stageDeployFolder({ jobFolder, deployFolder }) {
  rmSync(deployFolder, { recursive: true, force: true });
  mkdirSync(deployFolder, { recursive: true });
  for (const fileName of ["index.html", "manifest.json", "tools.js"]) {
    const sourcePath = join(jobFolder, "sidekick", fileName);
    // tools.js is optional (jess router, 2026-10-21); the other two always exist
    if (fileName === "tools.js" && !existsSync(sourcePath)) {
      continue;
    }
    cpSync(sourcePath, join(deployFolder, fileName));
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
// environmentName is the job's environment; without one, MIDAS_RUNNER_ENV as before.
export function deployArgs({ sidekickId, userId, deployFolder, environmentName = runnerEnvironment() }) {
  if (typeof sidekickId !== "string" || !SIDEKICK_ID_PATTERN.test(sidekickId)) {
    throw new Error(`refusing to deploy: bad Sidekick id "${sidekickId}"`);
  }
  if (typeof userId !== "string" || !USER_ID_PATTERN.test(userId)) {
    throw new Error(`refusing to deploy: no valid reporter user id ("${userId}"); the runner never deploys the base`);
  }
  if (typeof deployFolder !== "string" || deployFolder.length === 0) {
    throw new Error("refusing to deploy: no deploy folder");
  }
  return ["scripts/deploy-sidekick.mjs", sidekickId, "--env", environmentName, "--user", userId, "--dir", deployFolder];
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
  const toolsPath = join(jobFolder, "sidekick", "tools.js");
  const toolsText = existsSync(toolsPath) ? readFileSync(toolsPath, "utf8") : null;
  return bundleTools.bundleContentHash(html, manifestText, toolsText);
}

// How long the read-back may take before it counts as unreadable.
export const READ_BACK_TIMEOUT_MS = 2 * 60_000;

// Reads the reporter's current.json back from the runner environment's bucket with wrangler (the
// checkout's own helper, which runs it from the checkout's backend/, and environment table).
// Returns the parsed pointer, or null when it cannot be read.
export async function readLiveUserPointer({ checkoutRoot, sidekickId, userId, environmentName = runnerEnvironment() }) {
  const bundleTools = await loadCheckoutModule(checkoutRoot, "bundle-tools.mjs");
  const environments = await loadCheckoutModule(checkoutRoot, "environments.mjs");
  const wrangler = await loadCheckoutModule(checkoutRoot, "wrangler.mjs");
  const bucket = environments.ENVIRONMENTS[environmentName].bucket;
  const key = bundleTools.pointerKeyFor(sidekickId, userId);
  try {
    const text = wrangler.captureWrangler(["r2", "object", "get", `${bucket}/${key}`, "--pipe", "--remote"], { timeoutMs: READ_BACK_TIMEOUT_MS });
    return JSON.parse(text);
  } catch {
    return null;
  }
}

// Does the pointer read back name the files we published? Returns null when it does, else the
// reason it does not, naming the environment it was read from (staging or live).
export function verifyPointer({ pointer, expectedHash, environmentName = runnerEnvironment() }) {
  if (pointer === null || typeof pointer !== "object") {
    return `the user's current.json could not be read back from ${environmentName}`;
  }
  if (typeof pointer.version !== "string" || pointer.version.length === 0) {
    return "the user's current.json names no version";
  }
  if (pointer.contentHash !== expectedHash) {
    return `${environmentName} has content hash ${pointer.contentHash ?? "none"}, expected ${expectedHash}`;
  }
  return null;
}

// How many times the read-back is tried before it counts as unreadable.
export const READ_BACK_ATTEMPTS = 3;

// The version deploy-sidekick.mjs says it published for this user, from its closing line
// ("deployed <sidekick> <version> for user <user> to <env> ..."), or null when the output has no
// such line. The script writes the user's current.json last and prints this line after it, so the
// line on a clean exit means the pointer was written. With environmentName, the line must name
// that environment too (a job never counts a publish to the other one).
export function publishedVersionFromOutput({ output, sidekickId, userId, environmentName = null }) {
  const linePrefix = `deployed ${sidekickId} `;
  const userPart = ` for user ${userId} to `;
  const lines = String(output ?? "").split("\n");
  for (const line of lines) {
    if (!line.startsWith(linePrefix)) {
      continue;
    }
    const rest = line.slice(linePrefix.length);
    const userIndex = rest.indexOf(userPart);
    if (userIndex <= 0) {
      continue;
    }
    const version = rest.slice(0, userIndex);
    const afterUser = rest.slice(userIndex + userPart.length);
    const environmentMatches = environmentName === null || afterUser === environmentName || afterUser.startsWith(`${environmentName} `);
    if (!/\s/.test(version) && environmentMatches) {
      return version;
    }
  }
  return null;
}

async function readPointerWithRetries({ readPointer, checkoutRoot, sidekickId, userId, environmentName }) {
  for (let attempt = 1; attempt <= READ_BACK_ATTEMPTS; attempt += 1) {
    const pointer = await readPointer({ checkoutRoot, sidekickId, userId, environmentName });
    if (pointer !== null) {
      return pointer;
    }
  }
  return null;
}

// Deploy, then verify. Resolves with { ok, version, output, problem, readBack }. readBack is
// "matched" when the pointer read back names the published files, or "unconfirmed" when it could
// not be read at all but the script exited cleanly and reported publishing this user's copy: the
// copy is live then, so it counts as published (repair 13edb182, 2026-10-20, was published yet
// marked failed and the user never heard). A pointer that names other files is never a publish.
// Injectable pieces for the runner's own tests: runDeploy (the script) and readPointer (the read-back).
// environmentName: the job's environment, used for the deploy, the read-back and its message.
export async function publishFix({ checkoutRoot, sidekickId, userId, jobFolder, runDeploy = runDeployScript, readPointer = readLiveUserPointer, environmentName = runnerEnvironment() }) {
  const deployFolder = deployFolderFor(jobFolder);
  const args = deployArgs({ sidekickId, userId, deployFolder, environmentName });
  const expectedHash = await expectedContentHash({ checkoutRoot, jobFolder });
  stageDeployFolder({ jobFolder, deployFolder });
  try {
    const deployResult = await runDeploy({ checkoutRoot, args });
    if (!deployResult.ok) {
      return { ok: false, version: null, output: deployResult.output, problem: `deploy script exited with code ${deployResult.exitCode ?? "unknown"}` };
    }
    const pointer = await readPointerWithRetries({ readPointer, checkoutRoot, sidekickId, userId, environmentName });
    if (pointer === null) {
      const reportedVersion = publishedVersionFromOutput({ output: deployResult.output, sidekickId, userId, environmentName });
      if (reportedVersion !== null) {
        return { ok: true, version: reportedVersion, contentHash: expectedHash, output: deployResult.output, problem: null, readBack: "unconfirmed" };
      }
    }
    const problem = verifyPointer({ pointer, expectedHash, environmentName });
    if (problem !== null) {
      return { ok: false, version: pointer?.version ?? null, output: deployResult.output, problem };
    }
    return { ok: true, version: pointer.version, contentHash: expectedHash, output: deployResult.output, problem: null, readBack: "matched" };
  } finally {
    rmSync(deployFolder, { recursive: true, force: true });
  }
}
