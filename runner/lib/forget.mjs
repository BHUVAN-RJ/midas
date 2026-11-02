// Account deletion on the Mac mini (founder, 2026-11-02; docs/briefs/account-deletion-2026-11-02.md).
// After the founder deletes an account, the Worker lists the person's Edit job ids
// (GET /account-deletions/runner/pending). The runner removes, for each id, exactly:
//   jobs/<id>/  jobs/<id>.deploy/  log/<id>/          (settings.jobsRoot, settings.logsRoot)
//   <claudeConfigDir>/projects/<the job folder's path, every non-letter-or-digit as "-">/
//   and, for each session in it, file-history/<session>/ and session-env/<session>/
// then reports back (POST .../cleaned). Only names built from a job id that looks like a report id
// (a UUID); no globs, no prefixes, so another job's folders are never touched.
import { existsSync, readdirSync, rmSync } from "node:fs";
import { join } from "node:path";

const REPORT_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SESSION_FILE_PATTERN = /^([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.jsonl$/i;
export const FORGET_INTERVAL_MS = 10 * 60 * 1000;

export function isReportId(text) {
  return typeof text === "string" && REPORT_ID_PATTERN.test(text);
}

// The folder name Claude Code keeps a working folder's sessions under.
export function claudeProjectFolderName(workingFolder) {
  return workingFolder.replace(/[^a-zA-Z0-9]/g, "-");
}

function sessionIdsIn(projectFolder) {
  if (!existsSync(projectFolder)) {
    return [];
  }
  const sessionIds = [];
  for (const fileName of readdirSync(projectFolder)) {
    const match = SESSION_FILE_PATTERN.exec(fileName);
    if (match !== null) {
      sessionIds.push(match[1]);
    }
  }
  return sessionIds;
}

// Every folder the runner keeps for one job, by exact name.
export function jobPaths({ jobsRoot, logsRoot, claudeConfigDir }, reportId) {
  const jobFolder = join(jobsRoot, reportId);
  const projectFolder = join(claudeConfigDir, "projects", claudeProjectFolderName(jobFolder));
  const paths = [jobFolder, `${jobFolder}.deploy`, join(logsRoot, reportId), projectFolder];
  for (const sessionId of sessionIdsIn(projectFolder)) {
    paths.push(join(claudeConfigDir, "file-history", sessionId));
    paths.push(join(claudeConfigDir, "session-env", sessionId));
  }
  return paths;
}

// Removes the folders of the given jobs. Returns { removed, skipped } (skipped: ids that do not
// look like report ids, left alone).
export function forgetJobs(settings, reportIds) {
  let removed = 0;
  const skipped = [];
  for (const reportId of reportIds) {
    if (!isReportId(reportId)) {
      skipped.push(String(reportId));
      continue;
    }
    for (const path of jobPaths(settings, reportId)) {
      if (existsSync(path)) {
        rmSync(path, { recursive: true, force: true });
        removed += 1;
      }
    }
  }
  return { removed, skipped };
}

export function forgetResultText(reportCount, outcome) {
  const parts = [`removed ${outcome.removed} folders for ${reportCount} jobs`];
  if (outcome.skipped.length > 0) {
    parts.push(`skipped ${outcome.skipped.length} odd ids`);
  }
  return parts.join("; ");
}

// One pass over one environment: every done deletion not yet cleaned on this Mac.
export async function forgetDeletedAccounts(backend, settings) {
  const deletions = await backend.listForgets();
  const results = [];
  for (const deletion of deletions) {
    const reportIds = Array.isArray(deletion.reportIds) ? deletion.reportIds : [];
    const outcome = forgetJobs(settings, reportIds);
    const resultText = forgetResultText(reportIds.length, outcome);
    await backend.confirmForget(deletion.userId, resultText);
    results.push({ userId: deletion.userId, result: resultText });
  }
  return results;
}

// Wraps the runner's claim: before claiming, at most once per interval, each environment's
// deletions are cleaned. A failing environment is reported and the claim still runs.
export function claimAfterForgetting({ claimJob, backends, settings, onError = () => {}, intervalMs = FORGET_INTERVAL_MS, now = Date.now }) {
  let lastRunMs = -Infinity;
  return async function claimJobAfterForgetting() {
    const nowMs = now();
    if (nowMs - lastRunMs >= intervalMs) {
      lastRunMs = nowMs;
      for (const backend of backends) {
        try {
          await forgetDeletedAccounts(backend, settings);
        } catch (error) {
          onError(new Error(`${backend.environment}: account deletion clean-up: ${error.message}`));
        }
      }
    }
    return claimJob();
  };
}
