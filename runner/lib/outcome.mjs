// The agent ends by writing outcome.json at the job folder root. The runner reads it to decide
// between fix_ready and failed.
//   { "result": "fixed",       "summary": "<what changed, one or two sentences>" }
//   { "result": "unsupported", "summary": "...", "unsupportedAction": "<what the user asked for>" }
//   { "result": "no_change",   "summary": "<why nothing needed changing>" }
//   { "result": "ask",         "summary": "<what was unclear>", "question": "<short question>",
//     "options": [{ "label": "<concrete change>", "kind": "<guess id>" }, ...2 or 3] }
//     (founder, 2026-11-23: unclear code requests become a question, never a refusal)
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { OUTCOME_FILE } from "./job-folder.mjs";
import { ASK_OPTION_KINDS, ASK_RESULT } from "./prompt.mjs";

export const OUTCOME_RESULTS = ["fixed", "unsupported", "no_change", ASK_RESULT];
export const ASK_MIN_OPTIONS = 2;
export const ASK_MAX_OPTIONS = 3;
const ASK_FALLBACK_KIND = "other_layout";

// One option of an ask: { label, kind }, or null when it has no label. An unknown kind becomes
// other_layout's picture, as the sort does for Haiku's options.
function askOption(rawOption) {
  const label = typeof rawOption === "string" ? rawOption : rawOption?.label;
  if (typeof label !== "string" || label.trim().length === 0) {
    return null;
  }
  const kind = ASK_OPTION_KINDS.includes(rawOption?.kind) ? rawOption.kind : ASK_FALLBACK_KIND;
  return { label: label.trim(), kind };
}

// The question and its options from an "ask" outcome, or { problem }.
export function readAsk(parsed) {
  if (typeof parsed.question !== "string" || parsed.question.trim().length === 0) {
    return { problem: "outcome.json result ask needs a question" };
  }
  const rawOptions = Array.isArray(parsed.options) ? parsed.options : [];
  const options = [];
  for (const rawOption of rawOptions) {
    const option = askOption(rawOption);
    if (option !== null) {
      options.push(option);
    }
  }
  if (options.length < ASK_MIN_OPTIONS || options.length > ASK_MAX_OPTIONS) {
    return { problem: `outcome.json result ask needs ${ASK_MIN_OPTIONS} or ${ASK_MAX_OPTIONS} options with a label` };
  }
  return { ask: { question: parsed.question.trim(), options } };
}

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
  const outcome = {
    result: parsed.result,
    summary: parsed.summary.trim(),
    unsupportedAction: typeof parsed.unsupportedAction === "string" ? parsed.unsupportedAction.trim() : null,
  };
  if (parsed.result === ASK_RESULT) {
    const askRead = readAsk(parsed);
    if (askRead.problem !== undefined) {
      return { problem: askRead.problem };
    }
    outcome.question = askRead.ask.question;
    outcome.options = askRead.ask.options;
  }
  return { outcome };
}
