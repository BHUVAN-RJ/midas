// One repair job, start to finish:
//   running -> copy has a schema -> build job folder -> agent -> outcome -> schema only grew -> check -> every record
//   the reporter has fits the new schema -> fix_ready -> deploy to the reporter's live copy ->
//   read back and compare -> deployed_live | failed
// (contract, settled 2026-10-13: the runner publishes the fix itself, reporter's copy only.)
// Every step's output is kept under the job's log folder; the job folder itself holds only the
// Sidekick, the report and outcome.json.
import { chmodSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { currentStoreHelper, refreshStoreHelper } from "../../backend/scripts/store-helper.mjs";
import { ASSET_NAMES } from "./backend.mjs";
import { agentEnvironment, buildClaudeArgs, linkAgentTools, runAgent } from "./agent.mjs";
import { checkSidekick, sandboxRootFor } from "./check.mjs";
import { environmentOfBackendUrl, runnerEnvironment } from "./config.mjs";
import { compareTests, fetchCopyTests, readTestsFolder, snapshotTests, writeAgentSettings, writeTestsFolder } from "./copy-tests.mjs";
import { publishFix } from "./deploy.mjs";
import { rerunPendingRequest } from "./jess-rerun.mjs";
import { buildJobFolder, diffSidekickFiles, foreignFiles, snapshotSidekickFiles } from "./job-folder.mjs";
import { macNotification } from "./notify.mjs";
import { readOutcome } from "./outcome.mjs";
import { buildSystemPrompt } from "./prompt.mjs";
import { effortFor, isSpeedTrial, speedTrialPromptText } from "./speed-trial.mjs";

// The page map for a speed-trial Sidekick (speed-trial.mjs), from the copy in the job folder.
function speedTrialMapFor(jobFolder) {
  const html = readFileSync(join(jobFolder, "sidekick", "index.html"), "utf8");
  const toolsPath = join(jobFolder, "sidekick", "tools.js");
  const toolsText = existsSync(toolsPath) ? readFileSync(toolsPath, "utf8") : null;
  return speedTrialPromptText({ html, toolsText });
}
import { sandboxProfilePathFor } from "./sandbox.mjs";
import { TOOLS_REFUSAL_REASON, agentToolRemovalProblems, breakingChangeVerdict, schemaChangeProblems, undeclaredWritePrefixes } from "./schema-change.mjs";
import { buildSummary } from "./summary.mjs";
import { checkUserRecords, loadDataModules, recordFailureDetail, storedRecordSchemaProblems } from "./user-records.mjs";

// reason and detail go to the backend; missing (what the shell or SDK lacks, for an unsupported
// request) stays on the Mac: summary.md and the notification.
export class JobFailure extends Error {
  constructor(reason, detail = null, missing = null) {
    super(reason);
    this.reason = reason;
    this.detail = detail;
    this.missing = missing;
  }
}

async function downloadReport(backend, job) {
  const html = await backend.downloadAsset(job.id, ASSET_NAMES.bundleHtml);
  const manifest = await backend.downloadAsset(job.id, ASSET_NAMES.bundleManifest);
  if (html === null || manifest === null) {
    throw new JobFailure("bundle missing", "the backend has no bundle.html or bundle.manifest.json for this report");
  }
  const assets = {};
  assets[ASSET_NAMES.screenshot] = await backend.downloadAsset(job.id, ASSET_NAMES.screenshot);
  assets[ASSET_NAMES.drawing] = await backend.downloadAsset(job.id, ASSET_NAMES.drawing);
  assets[ASSET_NAMES.strokes] = await backend.downloadAsset(job.id, ASSET_NAMES.strokes);
  if (job.transcript.trim().length === 0) {
    const transcriptBytes = await backend.downloadAsset(job.id, ASSET_NAMES.transcript);
    if (transcriptBytes !== null) {
      job.transcript = transcriptBytes.toString("utf8");
    }
  }
  if (job.transcript.trim().length === 0) {
    throw new JobFailure("transcript missing", "the report has no transcript");
  }
  // A copy without the jess router's tools has no tools.js (404 -> null)
  const tools = await backend.downloadAsset(job.id, ASSET_NAMES.bundleTools);
  const toolsText = tools === null ? null : tools.toString("utf8");
  const bundle = { html: html.toString("utf8"), manifestText: manifest.toString("utf8"), toolsText };
  return { bundle, assets };
}

// The copy's tests, fetched from the live bucket with the checkout's fetch script (the base
// Sidekick's from the checkout when the copy has none stored). Returns { files, source }.
async function copyTestsFor({ checkoutRoot, sidekickId, userId, jobFolder, runFetch, environmentName }) {
  try {
    return await fetchCopyTests({ checkoutRoot, sidekickId, userId, jobFolder, runFetch, environmentName });
  } catch (error) {
    throw new JobFailure("tests missing", error.message);
  }
}

function parseManifestOrFail(manifestText, which) {
  try {
    return JSON.parse(manifestText);
  } catch {
    throw new JobFailure("check failed", `${which} manifest.json is not JSON`);
  }
}

// Every repair starts from a copy that declares its record types (founder, 2026-10-19): without
// them the shell checks nothing and there is no schema to keep backward compatible, so such a
// copy needs the schema pass first (backend/scripts/plan-user-copies.mjs lists them).
export const NO_SCHEMA_REASON = "copy has no schema";

export function checkCopyHasSchema(manifestText) {
  const manifest = parseManifestOrFail(manifestText, "the copy's");
  const types = manifest?.types;
  if (typeof types !== "object" || types === null || Array.isArray(types)) {
    throw new JobFailure(NO_SCHEMA_REASON, "the copy's manifest.json has no types; it needs the schema pass first");
  }
}

// The copy's schema may only grow (founder, 2026-10-15), and every record type the page writes
// must be declared, or the shell refuses the write on the phone. Throws a JobFailure otherwise.
export function checkSchemaChange({ manifestBeforeText, manifestAfterText, htmlAfter }) {
  const manifestBefore = parseManifestOrFail(manifestBeforeText, "the original");
  const manifestAfter = parseManifestOrFail(manifestAfterText, "the repaired");
  const problems = schemaChangeProblems(manifestBefore.types, manifestAfter.types);
  const refusal = breakingChangeVerdict({ problems });
  if (refusal !== null) {
    throw new JobFailure(refusal.reason, refusal.detail);
  }
  const undeclared = undeclaredWritePrefixes(htmlAfter, manifestAfter.types);
  if (undeclared.length > 0) {
    throw new JobFailure("schema missing", `the page writes ${undeclared.join(", ")} but manifest.json types declares no such prefix`);
  }
  const toolsRemoved = agentToolRemovalProblems(manifestBefore, manifestAfter, htmlAfter);
  if (toolsRemoved.length > 0) {
    throw new JobFailure(TOOLS_REFUSAL_REASON, toolsRemoved.join("; "));
  }
  return manifestAfter;
}

// Every record the reporter has must pass the repaired copy's schema before it is published
// (unified data plan, section 6), and the schema change must not clash with them (a new field a
// record already holds, a key that would change type). Throws a JobFailure when they cannot be
// read, the change clashes (through breakingChangeVerdict, like every breaking change) or one
// does not fit. modules: the checkout's validator.
async function checkReporterRecords({ backend, job, manifestBefore, manifestAfter, logFolder, modules }) {
  let records;
  try {
    records = await backend.listRecords(job.id);
  } catch (error) {
    throw new JobFailure("records unreadable", error.message);
  }
  const clashProblems = storedRecordSchemaProblems({ sidekickId: job.sidekickId, records, manifestBefore, manifest: manifestAfter, modules });
  const refusal = breakingChangeVerdict({ problems: clashProblems });
  if (refusal !== null) {
    throw new JobFailure(refusal.reason, refusal.detail);
  }
  const result = checkUserRecords({ sidekickId: job.sidekickId, records, manifest: manifestAfter, modules });
  writeFileSync(join(logFolder, "records-check.json"), JSON.stringify(result, null, 2));
  if (result.failures.length > 0) {
    throw new JobFailure("records do not fit schema", recordFailureDetail(result.failures));
  }
  return result;
}

// The copy's page gets the current store helper before the agent starts, so the copy's own tests
// (which pin the checkout's shell/sdk/midas-store.js) pass on today's SDK; a copy made before an
// SDK change holds an older helper (unified data plan, section 6). Only the checkout's helper is
// used: it is the one its tests compare with and the one the deploy ships.
export function refreshJobStoreHelper({ jobFolder, checkoutRoot }) {
  const checkoutHelperPath = join(checkoutRoot, "shell", "sdk", "midas-store.js");
  if (!existsSync(checkoutHelperPath)) {
    throw new JobFailure("runner error", `the checkout ${checkoutRoot} has no shell/sdk/midas-store.js`);
  }
  const helperText = currentStoreHelper(checkoutHelperPath);
  const pagePath = join(jobFolder, "sidekick", "index.html");
  const refresh = refreshStoreHelper(readFileSync(pagePath, "utf8"), helperText);
  if (refresh.status === "refreshed") {
    writeFileSync(pagePath, refresh.html);
  }
  return refresh.status;
}

function startHeartbeat(backend, job, intervalMs, setIntervalImplementation = setInterval) {
  const timer = setIntervalImplementation(function sendHeartbeat() {
    backend.postStatus(job.id, "running").catch(function ignoreHeartbeatError() {});
  }, intervalMs);
  if (typeof timer.unref === "function") {
    timer.unref();
  }
  return timer;
}

// The baseline the schema check compares against, for the agent's check tool: a read-only file in
// the log folder, outside the job folder. The runner itself compares against the text it holds
// in memory, so nothing the agent writes can move the baseline.
function writeBaselineForCheckTool(logFolder, manifestText) {
  const baselinePath = join(logFolder, "manifest-baseline.json");
  rmSync(baselinePath, { force: true });
  writeFileSync(baselinePath, manifestText);
  chmodSync(baselinePath, 0o444);
  return baselinePath;
}

// What the agent may not touch outside the job folder (founder, 2026-10-22: the agents must not
// touch the sandbox), as deny rules on top of the job-folder allow rules: the checkout (the
// runner's code, sandbox.mjs among it) and the tool link are read-only; the logs (prompts,
// baselines, other jobs) and this job's sandbox checkout and profile are off limits.
export function agentPathLimits({ settings, jobFolder }) {
  const sandboxRoot = sandboxRootFor(jobFolder);
  return {
    noEditPaths: [`${settings.checkoutRoot}/**`, `${settings.toolLinkRoot}/**`],
    noReadPaths: [`${settings.logsRoot}/**`, `${sandboxRoot}/**`, sandboxProfilePathFor(sandboxRoot)],
  };
}

// The agent's two tools at a path it can type bare (agent.mjs linkAgentTools). Settings from
// config.mjs always name the link folder; settings built by hand fall back to the folder that
// holds the jobs folder.
function linkToolsForJob(settings) {
  const linkRoot = settings.toolLinkRoot ?? dirname(settings.jobsRoot);
  try {
    return linkAgentTools({ linkRoot });
  } catch (error) {
    throw new JobFailure("runner error", error.message);
  }
}

async function loadCheckoutDataModules(checkoutRoot) {
  try {
    return await loadDataModules(checkoutRoot);
  } catch (error) {
    throw new JobFailure("runner error", error.message);
  }
}

// jess grows the Sidekick (founder 2026-10-21): the pending jess request linked to this report, if
// any, runs again now against the published tools.js. The repair is live whatever happens here;
// a failure is kept in the log folder and the backend fails the request (the phone shows Not Done).
async function rerunAfterPublish({ backend, job, jobFolder, logFolder, now }) {
  // jess files every such request as a feature (backend/src/jess-route.ts fileGrowRequest)
  if (job.kind !== "feature") {
    return { status: "none" };
  }
  const toolsPath = join(jobFolder, "sidekick", "tools.js");
  const toolsText = existsSync(toolsPath) ? readFileSync(toolsPath, "utf8") : null;
  let result;
  try {
    const records = toolsText === null ? [] : await backend.listRecords(job.id);
    result = await rerunPendingRequest({ backend, job, toolsText, records, now });
  } catch (error) {
    result = { status: "error", reason: error.message };
  }
  writeFileSync(join(logFolder, "jess-rerun.json"), JSON.stringify(result, null, 2));
  return result;
}

// The one environment a job runs in (the runner serves live and staging, founder 2026-10-21):
// the settings' publish environment, which must also be the environment the job was claimed from,
// the backend client's, and the backend URL's. Throws before anything is read or posted
// otherwise: records, report and status would come from one environment and the fix would go to
// the other.
export function jobEnvironment({ job, backend, settings }) {
  const environmentName = settings.deployEnvironment ?? runnerEnvironment();
  const sources = [
    { what: "the job was claimed from", value: job.environment ?? null },
    { what: "the backend client is", value: backend.environment ?? null },
    { what: "the backend URL is", value: settings.backendUrl ? environmentOfBackendUrl(settings.backendUrl) : null },
  ];
  for (const source of sources) {
    if (source.value !== null && source.value !== environmentName) {
      throw new Error(`refusing job ${job.id}: ${source.what} ${source.value} but the job would publish to ${environmentName}`);
    }
  }
  return environmentName;
}

// deps: { backend, settings, runFetch?, runTests?, runDeploy?, readPointer?, agentCommand?, agentArgs?, notify?, now? }
// settings are the job's environment's (config.mjs settingsForEnvironment).
export async function runJob(job, deps) {
  const { backend, settings } = deps;
  const environmentName = jobEnvironment({ job, backend, settings });
  const notify = deps.notify ?? macNotification;
  const logFolder = join(settings.logsRoot, job.id);
  mkdirSync(logFolder, { recursive: true });
  mkdirSync(settings.jobsRoot, { recursive: true });
  writeFileSync(join(logFolder, "job.json"), JSON.stringify(job, null, 2));

  await backend.postStatus(job.id, "running");
  await notify({ title: `Repair request: ${job.sidekickId}`, body: `${job.kind}: ${job.transcript.slice(0, 120)}` });
  const heartbeat = startHeartbeat(backend, job, settings.heartbeatIntervalMs, deps.setInterval);

  let jobFolder = null;
  try {
    const { bundle, assets } = await downloadReport(backend, job);
    checkCopyHasSchema(bundle.manifestText);
    const dataModules = await loadCheckoutDataModules(settings.checkoutRoot);
    jobFolder = buildJobFolder({ jobsRoot: settings.jobsRoot, job, bundle, assets });
    const copyTests = await copyTestsFor({ checkoutRoot: settings.checkoutRoot, sidekickId: job.sidekickId, userId: job.userId, jobFolder, runFetch: deps.runFetch, environmentName });
    writeFileSync(join(logFolder, "fetch-output.txt"), copyTests.output ?? "");
    writeTestsFolder(jobFolder, copyTests.files);
    writeAgentSettings({ jobFolder, checkoutRoot: settings.checkoutRoot });
    const strayFiles = foreignFiles(jobFolder);
    if (strayFiles.length > 0) {
      throw new JobFailure("job folder not clean", strayFiles.join(", "));
    }
    const helperStatus = refreshJobStoreHelper({ jobFolder, checkoutRoot: settings.checkoutRoot });
    writeFileSync(join(logFolder, "store-helper.txt"), `${helperStatus}\n`);
    const snapshotFolder = join(logFolder, "before");
    snapshotSidekickFiles(jobFolder, snapshotFolder);
    const testsBefore = readTestsFolder(jobFolder);
    snapshotTests(jobFolder, join(logFolder, "tests-before"));

    const reportFiles = JSON.parse(readFileSync(join(jobFolder, "report", "report.json"), "utf8")).files;
    // The copy's manifest before the agent: the schema baseline, kept here in memory.
    const manifestText = readFileSync(join(jobFolder, "sidekick", "manifest.json"), "utf8");
    const baselinePath = writeBaselineForCheckTool(logFolder, manifestText);
    const toolPaths = linkToolsForJob(settings);
    const basePrompt = buildSystemPrompt({ job, reportFiles, manifestText, checkoutRoot: settings.checkoutRoot, ...toolPaths });
    const systemPrompt = isSpeedTrial(job.sidekickId) ? basePrompt + speedTrialMapFor(jobFolder) : basePrompt;
    const systemPromptPath = join(logFolder, "system-prompt.md");
    writeFileSync(systemPromptPath, systemPrompt);

    const effort = effortFor(job.sidekickId);
    const args = deps.agentArgs ?? buildClaudeArgs({ systemPromptPath, model: settings.model, maxTurns: settings.maxTurns, effort, ...toolPaths, ...agentPathLimits({ settings, jobFolder }) });
    const environment = agentEnvironment({
      baseEnvironment: process.env,
      claudeConfigDir: settings.claudeConfigDir,
      jobFolder,
      checkoutRoot: settings.checkoutRoot,
      sidekickId: job.sidekickId,
      manifestBeforePath: baselinePath,
    });
    const agentResult = await runAgent({
      command: deps.agentCommand ?? settings.claudeCommand,
      args,
      jobFolder,
      logPath: join(logFolder, "agent-stream.jsonl"),
      environment,
      timeoutMs: settings.jobTimeoutMs,
    });
    writeFileSync(join(logFolder, "agent-exit.json"), JSON.stringify(agentResult));
    if (agentResult.timedOut) {
      throw new JobFailure("agent timed out", `${settings.jobTimeoutMs} ms`);
    }
    if (agentResult.exitCode !== 0) {
      throw new JobFailure("agent exited with an error", `exit code ${agentResult.exitCode}`);
    }

    const strayAfterAgent = foreignFiles(jobFolder);
    if (strayAfterAgent.length > 0) {
      throw new JobFailure("agent wrote outside the Sidekick", strayAfterAgent.join(", "));
    }
    const outcomeRead = readOutcome(jobFolder);
    if (outcomeRead.problem !== undefined) {
      throw new JobFailure("bad outcome", outcomeRead.problem);
    }
    const outcome = outcomeRead.outcome;
    writeFileSync(join(logFolder, "outcome.json"), JSON.stringify(outcome, null, 2));

    const diff = diffSidekickFiles(snapshotFolder, join(jobFolder, "sidekick"));
    writeFileSync(join(logFolder, "diff.patch"), diff);

    // Existing tests may only change through test-guardian (logged); the agent may add tests.
    const testsAfter = readTestsFolder(jobFolder);
    const testReport = compareTests({ before: testsBefore, after: testsAfter });
    writeFileSync(join(logFolder, "tests-report.json"), JSON.stringify({ ...testReport, source: copyTests.source }, null, 2));
    if (testReport.problems.length > 0) {
      throw new JobFailure("test changed", testReport.problems.join("; "));
    }

    if (outcome.result === "unsupported") {
      // The founder reads what is missing (the agent's summary) in summary.md and the Mac
      // notification; the backend gets the user's own words as detail (founder, 2026-10-13).
      const unsupportedSummary = buildSummary({ job, jobFolder, outcome, diff, checkOutput: "", logFolder });
      writeFileSync(join(logFolder, "summary.md"), unsupportedSummary);
      throw new JobFailure("unsupported", outcome.unsupportedAction, outcome.summary);
    }
    if (outcome.result === "no_change") {
      // Not a failure to the user (founder, 2026-10-23): the Repair tag says Already There and a
      // tap shows this summary. The founder still hears of it on the Mac.
      const noChangeSummary = buildSummary({ job, jobFolder, outcome, diff, checkOutput: "", logFolder });
      writeFileSync(join(logFolder, "summary.md"), noChangeSummary);
      await backend.postStatus(job.id, "no_change", { summary: outcome.summary });
      await notify({ title: `Nothing to change: ${job.sidekickId}`, body: `${outcome.summary.slice(0, 100)} · ${logFolder}/summary.md` });
      return { status: "no_change", jobFolder, logFolder, summary: outcome.summary };
    }
    if (diff.length === 0) {
      throw new JobFailure("no change", "agent reported a fix but changed nothing");
    }

    const manifestAfter = checkSchemaChange({
      manifestBeforeText: manifestText,
      manifestAfterText: readFileSync(join(jobFolder, "sidekick", "manifest.json"), "utf8"),
      htmlAfter: readFileSync(join(jobFolder, "sidekick", "index.html"), "utf8"),
    });

    const check = await checkSidekick({ checkoutRoot: settings.checkoutRoot, sidekickId: job.sidekickId, jobFolder, runTests: deps.runTests });
    writeFileSync(join(logFolder, "check-output.txt"), check.testOutput ?? "");
    if (!check.ok) {
      throw new JobFailure("check failed", check.problems.join("; "));
    }

    const recordsCheck = await checkReporterRecords({ backend, job, manifestBefore: JSON.parse(manifestText), manifestAfter, logFolder, modules: dataModules });

    await backend.postStatus(job.id, "fix_ready", { summary: outcome.summary });

    // Publish to the reporter's live copy and check it landed (founder, 2026-10-13). The deploy
    // and its read-back are the runner's own code; the agent is finished by now.
    const published = await publishFix({
      checkoutRoot: settings.checkoutRoot,
      sidekickId: job.sidekickId,
      userId: job.userId,
      jobFolder,
      runDeploy: deps.runDeploy,
      readPointer: deps.readPointer,
      environmentName,
    });
    writeFileSync(join(logFolder, "deploy-output.txt"), published.output ?? "");
    if (!published.ok) {
      throw new JobFailure("deploy failed", published.problem);
    }

    // A publish whose pointer could not be read back still went out (the script said so); the
    // founder is told the read-back did not confirm it, the user gets the done notice as usual
    // (founder, 2026-10-21: a published repair is always marked done).
    const readBackNote = published.readBack === "unconfirmed"
      ? `\n\nRead-back: the user's current.json could not be read back after the deploy; the deploy script reported version ${published.version} published for this user.\n`
      : "";
    const summary = buildSummary({ job, jobFolder, outcome, diff, checkOutput: check.testOutput, logFolder, deployedVersion: published.version, testReport: { ...testReport, source: copyTests.source }, helperStatus, recordsCheck, environmentName }) + readBackNote;
    writeFileSync(join(logFolder, "summary.md"), summary);
    await backend.postStatus(job.id, "deployed_live", { summary: outcome.summary, version: published.version });
    const unconfirmedNote = published.readBack === "unconfirmed" ? " · read-back unconfirmed" : "";
    await notify({ title: `Fixed and live: ${job.sidekickId}`, body: `${outcome.summary.slice(0, 100)} · ${environmentName === "live" ? "live" : "on staging"} for ${job.userId}${unconfirmedNote} · ${logFolder}/summary.md` });
    const jessRerun = await rerunAfterPublish({ backend, job, jobFolder, logFolder, now: deps.now });
    return { status: "deployed_live", jobFolder, logFolder, summary, version: published.version, jessRerun };
  } catch (error) {
    const failure = error instanceof JobFailure ? error : new JobFailure("runner error", error.message);
    const failureRecord = { reason: failure.reason, detail: failure.detail };
    writeFileSync(join(logFolder, "failure.json"), JSON.stringify(failureRecord, null, 2));
    try {
      await backend.postStatus(job.id, "failed", failureRecord);
    } catch {
      // The backend will re-queue the job when the lease ends.
    }
    const missingNote = failure.missing === null ? "" : ` · Missing: ${failure.missing}`;
    await notify({ title: `Repair failed: ${job.sidekickId}`, body: `${failure.reason}: ${String(failure.detail ?? "").slice(0, 100)}${missingNote}` });
    return { status: "failed", jobFolder, logFolder, reason: failure.reason, detail: failure.detail, missing: failure.missing };
  } finally {
    clearInterval(heartbeat);
  }
}
