// One repair job, start to finish:
//   running -> build job folder -> agent -> outcome -> check -> fix_ready | failed
// The runner never deploys (contract, settled 2026-10-13). Every step's output is kept under the
// job's log folder; the job folder itself holds only the Sidekick, the report and outcome.json.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { ASSET_NAMES } from "./backend.mjs";
import { agentEnvironment, buildClaudeArgs, runAgent } from "./agent.mjs";
import { checkSidekick } from "./check.mjs";
import { buildJobFolder, diffSidekickFiles, foreignFiles, snapshotSidekickFiles } from "./job-folder.mjs";
import { macNotification } from "./notify.mjs";
import { readOutcome } from "./outcome.mjs";
import { buildSystemPrompt } from "./prompt.mjs";
import { buildSummary } from "./summary.mjs";

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
  const bundle = { html: html.toString("utf8"), manifestText: manifest.toString("utf8") };
  return { bundle, assets };
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

// deps: { backend, settings, runTests?, agentCommand?, agentArgs?, notify?, now? }
export async function runJob(job, deps) {
  const { backend, settings } = deps;
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
    jobFolder = buildJobFolder({ jobsRoot: settings.jobsRoot, job, bundle, assets });
    const strayFiles = foreignFiles(jobFolder);
    if (strayFiles.length > 0) {
      throw new JobFailure("job folder not clean", strayFiles.join(", "));
    }
    const snapshotFolder = join(logFolder, "before");
    snapshotSidekickFiles(jobFolder, snapshotFolder);

    const reportFiles = JSON.parse(readFileSync(join(jobFolder, "report", "report.json"), "utf8")).files;
    const systemPrompt = buildSystemPrompt({ job, reportFiles, checkoutRoot: settings.checkoutRoot });
    const systemPromptPath = join(logFolder, "system-prompt.md");
    writeFileSync(systemPromptPath, systemPrompt);

    const args = deps.agentArgs ?? buildClaudeArgs({ systemPromptPath, model: settings.model, maxTurns: settings.maxTurns });
    const environment = agentEnvironment({
      baseEnvironment: process.env,
      claudeConfigDir: settings.claudeConfigDir,
      jobFolder,
      checkoutRoot: settings.checkoutRoot,
      sidekickId: job.sidekickId,
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

    if (outcome.result === "unsupported") {
      // The founder reads what is missing (the agent's summary) in summary.md and the Mac
      // notification; the backend gets the user's own words as detail (founder, 2026-10-13).
      const unsupportedSummary = buildSummary({ job, jobFolder, outcome, diff, checkOutput: "", founderUserId: settings.founderUserId, logFolder });
      writeFileSync(join(logFolder, "summary.md"), unsupportedSummary);
      throw new JobFailure("unsupported", outcome.unsupportedAction, outcome.summary);
    }
    if (outcome.result === "no_change") {
      throw new JobFailure("no change", outcome.summary);
    }
    if (diff.length === 0) {
      throw new JobFailure("no change", "agent reported a fix but changed nothing");
    }

    const check = await checkSidekick({ checkoutRoot: settings.checkoutRoot, sidekickId: job.sidekickId, jobFolder, runTests: deps.runTests });
    writeFileSync(join(logFolder, "check-output.txt"), check.testOutput ?? "");
    if (!check.ok) {
      throw new JobFailure("check failed", check.problems.join("; "));
    }

    const summary = buildSummary({ job, jobFolder, outcome, diff, checkOutput: check.testOutput, founderUserId: settings.founderUserId, logFolder });
    writeFileSync(join(logFolder, "summary.md"), summary);
    await backend.postStatus(job.id, "fix_ready", { summary: outcome.summary });
    await notify({ title: `Fix ready: ${job.sidekickId}`, body: `${outcome.summary.slice(0, 100)} · ${logFolder}/summary.md` });
    return { status: "fix_ready", jobFolder, logFolder, summary };
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
