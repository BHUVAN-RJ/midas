// Publish first (founder, 2026-11-13; docs/briefs/repair-lanes.md W7): the fixed copy reaches the
// person as fast as possible. Only the checks that protect the person run before it; the upload
// runs alongside them; the person's pointer flips the moment they pass. The slow checks run after,
// and when one fails the person is put back on the previous version at once.
//
//   before the person sees it   gate, shield fast part, copy tests   ┐ at the same time
//                               upload the new version (not live)   ┘
//   publish                     flip the person's pointer (the Worker checks the files' hash)
//   after                       shield slow part -> fail: roll back, mark failed, founder pushed
//                               then notes, summary, notices, jess re-run, logs (the caller's)
//
// Every step is timed (createStepTimer) and the times go to timings.json in the job's log folder.
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const TOOLS_FILE = "tools.js";
const TESTS_FOLDER = "tests";
const TESTS_INDEX_FILE = "index.json";

// ---- timing ------------------------------------------------------------------------------------

// Times named steps. clock: milliseconds (performance.now by default). time(name, run) resolves or
// rejects as run does; every step is kept with its start and end relative to the timer's start.
export function createStepTimer(clock = performance.now.bind(performance)) {
  const startedAt = clock();
  const steps = [];
  async function time(name, run) {
    const startMs = clock() - startedAt;
    const entry = { name, startMs, endMs: null, ok: null };
    steps.push(entry);
    try {
      const value = await run();
      entry.ok = true;
      return value;
    } catch (error) {
      entry.ok = false;
      throw error;
    } finally {
      entry.endMs = clock() - startedAt;
    }
  }
  function list() {
    return steps.map(function roundedStep(step) {
      const durationMs = step.endMs === null ? null : Math.round(step.endMs - step.startMs);
      return { name: step.name, startMs: Math.round(step.startMs), endMs: step.endMs === null ? null : Math.round(step.endMs), durationMs, ok: step.ok };
    });
  }
  return { time, list };
}

// The timer's steps as a small text table for the log folder and the founder
export function timingsTable(steps) {
  const lines = ["step | starts at | takes", "---|---|---"];
  for (const step of steps) {
    const takes = step.durationMs === null ? "unfinished" : `${(step.durationMs / 1000).toFixed(2)} s`;
    const mark = step.ok === false ? " (failed)" : "";
    lines.push(`${step.name}${mark} | ${(step.startMs / 1000).toFixed(2)} s | ${takes}`);
  }
  return lines.join("\n");
}

// ---- the new version ---------------------------------------------------------------------------

async function loadBundleTools(checkoutRoot) {
  const bundleToolsPath = join(checkoutRoot, "backend", "scripts", "bundle-tools.mjs");
  return import(pathToFileURL(bundleToolsPath).href);
}

// The job's tests as deploy-sidekick.mjs --dir reads them: every file in tests/ but the index
function jobTestFiles(jobFolder) {
  const testsFolder = join(jobFolder, TESTS_FOLDER);
  if (!existsSync(testsFolder)) {
    return [];
  }
  const testFiles = [];
  const names = readdirSync(testsFolder, { withFileTypes: true });
  const sortedNames = names.sort(function byName(left, right) {
    return left.name.localeCompare(right.name);
  });
  for (const entry of sortedNames) {
    if (entry.isFile() && entry.name !== TESTS_INDEX_FILE) {
      testFiles.push({ name: entry.name, body: readFileSync(join(testsFolder, entry.name), "utf8") });
    }
  }
  return testFiles;
}

// The new version of the person's copy, planned with the checkout's own bundle-tools.mjs (the same
// version name, script hashes and content hash a deploy-sidekick.mjs --user --dir deploy makes).
// Returns { version, files: [{ name, body }], pointer: { scriptHashes, contentHash, tools? } }: the
// files to upload (page, manifest, tools.js, tests) and the pointer to flip to. version.json and
// current.json are the Worker's to write at the flip. Throws when the copy has no tests (a user copy
// deploys its tests with the page, founder 2026-10-13).
export async function planVersion({ checkoutRoot, sidekickId, userId, jobFolder, deployedAt = new Date() }) {
  const bundleTools = await loadBundleTools(checkoutRoot);
  const sidekickFolder = join(jobFolder, "sidekick");
  const html = readFileSync(join(sidekickFolder, "index.html"), "utf8");
  const manifestText = readFileSync(join(sidekickFolder, "manifest.json"), "utf8");
  const toolsPath = join(sidekickFolder, TOOLS_FILE);
  const toolsText = existsSync(toolsPath) ? readFileSync(toolsPath, "utf8") : null;
  const testFiles = jobTestFiles(jobFolder);
  if (testFiles.length === 0) {
    throw new Error(`${join(jobFolder, TESTS_FOLDER)} is empty; a user copy deploys its tests with the page`);
  }
  const plan = bundleTools.planDeploy({ sidekickId, userId, html, manifestText, toolsText, testFiles, deployedAt });
  const versionPrefix = `${bundleTools.storePrefix(sidekickId, userId)}/${plan.version}/`;
  const files = [];
  for (const put of plan.puts) {
    if (!put.key.startsWith(versionPrefix)) {
      continue;
    }
    const name = put.key.slice(versionPrefix.length);
    if (name === "version.json") {
      continue;
    }
    files.push({ name, body: put.body });
  }
  const pointer = { scriptHashes: plan.pointer.scriptHashes, contentHash: plan.pointer.contentHash };
  if (plan.pointer.tools) {
    pointer.tools = plan.pointer.tools;
  }
  return { version: plan.version, files, pointer };
}

// ---- before the person sees it -----------------------------------------------------------------

function errorMessage(error) {
  return error && error.message ? error.message : String(error);
}

// upload: () => uploads the planned version (not yet live). checkBeforePublish: () => { ok,
// problems, ... } (check.mjs). flip: () => { version, previousVersion }. Upload and checks run at
// the same time; the flip only after both succeeded. Resolves with one of
//   { status: "published", check, flipped }
//   { status: "refused", check }                      the checks failed; nothing changed for the person
//   { status: "failed", reason, detail, check? }       a check could not run, or upload or flip failed
// A refused or failed run leaves the person's pointer where it was; an uploaded version nothing
// points at is never served.
export async function publishFirst({ timer, upload, checkBeforePublish, flip }) {
  const uploadRun = timer.time("upload (alongside the checks)", upload);
  const checkRun = timer.time("checks before publish", checkBeforePublish);
  const [uploadSettled, checkSettled] = await Promise.allSettled([uploadRun, checkRun]);
  if (checkSettled.status === "rejected") {
    return { status: "failed", reason: "check failed", detail: `a check could not run: ${errorMessage(checkSettled.reason)}` };
  }
  const check = checkSettled.value;
  if (!check.ok) {
    return { status: "refused", check };
  }
  if (uploadSettled.status === "rejected") {
    return { status: "failed", reason: "deploy failed", detail: `upload: ${errorMessage(uploadSettled.reason)}`, check };
  }
  let flipped;
  try {
    flipped = await timer.time("pointer flip", flip);
  } catch (error) {
    return { status: "failed", reason: "deploy failed", detail: `pointer flip: ${errorMessage(error)}`, check };
  }
  return { status: "published", check, flipped };
}

// ---- after publishing --------------------------------------------------------------------------

// checkAfterPublish: () => { ok, problems } (check.mjs). rollBack: (reason) => the Worker's reply.
// markRolledBack: (reason, detail) => posts the failure (founder and person told). A slow check that
// throws counts as failed: a broken check never keeps a copy it could not judge. Resolves with
//   { status: "kept", slow }
//   { status: "rolled back", slow, reason, detail, rollBack }
//   { status: "roll back failed", slow, reason, detail, error }   the founder must act by hand
export async function afterPublish({ timer, checkAfterPublish, rollBack, markRolledBack }) {
  let slow;
  try {
    slow = await timer.time("checks after publish", checkAfterPublish);
  } catch (error) {
    slow = { ok: false, problems: [`the slow checks could not run: ${errorMessage(error)}`] };
  }
  if (slow.ok) {
    return { status: "kept", slow };
  }
  const reason = "rolled back";
  const detail = slow.problems.join("; ");
  let rollBackReply;
  try {
    rollBackReply = await timer.time("roll back", function rollBackNow() {
      return rollBack(detail);
    });
  } catch (error) {
    return { status: "roll back failed", slow, reason, detail, error: errorMessage(error) };
  }
  await timer.time("mark failed", function markFailedNow() {
    return markRolledBack(reason, detail);
  });
  return { status: "rolled back", slow, reason, detail, rollBack: rollBackReply };
}

// ---- through the Worker (backend/src/repair-publish.ts) ----------------------------------------

export function uploadVersion({ backend, jobId, plan }) {
  return backend.publishFiles(jobId, { version: plan.version, files: plan.files });
}

export function flipToVersion({ backend, jobId, plan }) {
  return backend.flipPointer(jobId, { version: plan.version, pointer: plan.pointer });
}

export function rollBackVersion({ backend, jobId, plan, reason }) {
  return backend.rollBackPointer(jobId, { version: plan.version, reason });
}
