// The agent ends by writing outcome.json at the job folder root. The runner reads it to decide
// between fix_ready and failed.
//   { "result": "fixed",       "summary": "<what changed, one or two sentences>" }
//   { "result": "unsupported", "summary": "...", "unsupportedAction": "<what the user asked for>" }
//   { "result": "no_change",   "summary": "<why nothing needed changing>" }
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { OUTCOME_FILE } from "./job-folder.mjs";

export const OUTCOME_RESULTS = ["fixed", "unsupported", "no_change"];

// Returns { outcome } or { problem } so the caller can mark the job failed with a reason.
export function readOutcome(jobFolder) {
  const outcomePath = join(jobFolder, OUTCOME_FILE);
  if (!existsSync(outcomePath)) {
    return { problem: "agent wrote no outcome.json" };
  }
  let parsed;
  try {
    parsed = JSON.parse(readFileSync(outcomePath, "utf8"));
  } catch {
    return { problem: "outcome.json is not JSON" };
  }
  if (parsed === null || typeof parsed !== "object") {
    return { problem: "outcome.json is not an object" };
  }
  if (!OUTCOME_RESULTS.includes(parsed.result)) {
    return { problem: `outcome.json result must be one of ${OUTCOME_RESULTS.join(", ")}` };
  }
  if (typeof parsed.summary !== "string" || parsed.summary.trim().length === 0) {
    return { problem: "outcome.json needs a summary" };
  }
  if (parsed.result === "unsupported" && (typeof parsed.unsupportedAction !== "string" || parsed.unsupportedAction.trim().length === 0)) {
    return { problem: "outcome.json result unsupported needs unsupportedAction" };
  }
  return {
    outcome: {
      result: parsed.result,
      summary: parsed.summary.trim(),
      unsupportedAction: typeof parsed.unsupportedAction === "string" ? parsed.unsupportedAction.trim() : null,
    },
  };
}
