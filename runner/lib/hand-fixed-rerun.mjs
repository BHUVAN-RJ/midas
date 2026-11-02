// Re-runs after an edit the founder made by hand (founder 2026-11-02, build 22 small fixes, pick B).
// A jess request that needed an edit the agent could not make keeps waiting while the founder fixes
// the person's copy by hand, publishes it and marks the thread Built. The runner never published
// that copy, so it never re-ran the request. Between jobs it now asks each backend which live
// reports a request still waits on (GET /repairs/jess-reruns) and re-runs each one exactly as after
// its own publish (jess-rerun.mjs), with the person's current tools.js and records from the
// backend. The backend's claim makes a second call for the same report a no-op.
// Kept self-contained (no import from backend/): the runner folder is also run on its own.
import { ASSET_NAMES } from "./backend.mjs";
import { rerunPendingRequest } from "./jess-rerun.mjs";

// One report: the person's current tools.js (null when their copy has none) and records, then the
// re-run. Returns what rerunPendingRequest returned.
async function rerunOneReport({ backend, job, now }) {
  const toolsBytes = await backend.downloadAsset(job.id, ASSET_NAMES.bundleTools);
  const toolsText = toolsBytes === null ? null : toolsBytes.toString("utf8");
  let records = [];
  if (toolsText !== null) {
    records = await backend.listRecords(job.id);
  }
  return rerunPendingRequest({ backend, job, toolsText, records, now });
}

// deps: { backends, now?: () => Date, log?: (line) => void, onError?: (error) => void }
// Every environment is asked; one that fails, or one report that fails, does not stop the others.
// Returns [{ environment, reportId, result }] for the reports it tried.
export async function rerunHandFixed({ backends, now = () => new Date(), log = () => {}, onError = () => {} }) {
  const outcomes = [];
  for (const backend of backends) {
    let jobs = [];
    try {
      jobs = await backend.listJessReruns();
    } catch (error) {
      onError(new Error(`${backend.environment}: ${error.message}`));
      continue;
    }
    for (const job of jobs) {
      let result;
      try {
        result = await rerunOneReport({ backend, job, now });
      } catch (error) {
        result = { status: "error", reason: error.message };
        onError(new Error(`${backend.environment}: jess re-run of ${job.id}: ${error.message}`));
      }
      log(`runner: jess re-run of ${job.id} on ${backend.environment} (hand fix): ${result.status}${result.reason ? `: ${result.reason}` : ""}`);
      outcomes.push({ environment: backend.environment, reportId: job.id, result });
    }
  }
  return outcomes;
}
