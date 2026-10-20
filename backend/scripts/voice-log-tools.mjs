// Pure helpers for voice-log.mjs (founder, 2026-10-19), kept apart from the wrangler call so they
// can be tested. The script only reads voice_logs; it never changes a row.
import { sqlLiteral } from "./db-tools.mjs";

export const DEFAULT_LIMIT = 50;
export const MAX_LIMIT = 1000;
const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;

// "--since 2026-10-19", "--since 2026-10-19T08:00:00Z", "--since 24h", "--since 7d" -> ISO time
export function sinceToIso(text, now) {
  if (typeof text !== "string" || text.length === 0) {
    return null;
  }
  const relative = /^(\d{1,4})([hd])$/.exec(text);
  if (relative !== null) {
    const amount = Number(relative[1]);
    const unitMs = relative[2] === "h" ? HOUR_MS : DAY_MS;
    return new Date(now.getTime() - amount * unitMs).toISOString();
  }
  const parsed = Date.parse(text);
  if (Number.isNaN(parsed)) {
    return null;
  }
  return new Date(parsed).toISOString();
}

// The script's options, or { problem } with what is wrong
export function parseVoiceLogArgs(argv, now) {
  const options = { failed: false, since: null, limit: DEFAULT_LIMIT };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--env") {
      index += 1;
    } else if (argument === "--failed") {
      options.failed = true;
    } else if (argument === "--since") {
      const since = sinceToIso(argv[index + 1], now);
      if (since === null) {
        return { problem: "--since takes a date (2026-10-19), a time (2026-10-19T08:00:00Z), or 24h / 7d" };
      }
      options.since = since;
      index += 1;
    } else if (argument === "--limit") {
      const limit = Number(argv[index + 1]);
      if (!Number.isInteger(limit) || limit < 1 || limit > MAX_LIMIT) {
        return { problem: `--limit takes a whole number from 1 to ${MAX_LIMIT}` };
      }
      options.limit = limit;
      index += 1;
    } else {
      return { problem: `unknown argument ${argument}` };
    }
  }
  return { options };
}

// Newest first. --failed keeps only not-done attempts; --since only attempts from then on.
export function voiceLogSql(options) {
  const conditions = [];
  if (options.failed) {
    conditions.push("status = 'not-done'");
  }
  if (options.since !== null) {
    conditions.push(`created_at >= ${sqlLiteral(options.since)}`);
  }
  const where = conditions.length > 0 ? ` WHERE ${conditions.join(" AND ")}` : "";
  const columns = "created_at, user_id, transcript, status, reason, result, raw_reply, retries, steps, total_ms, listen_ms, time_zone, app_version, app_build";
  return `SELECT ${columns} FROM voice_logs${where} ORDER BY created_at DESC LIMIT ${Number(options.limit)}`;
}

function parseJsonOrNull(text) {
  if (typeof text !== "string") {
    return null;
  }
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

// "model 812 ms, model 4001 ms (timeout), resolve 1 ms"
function stepsSummary(stepsText) {
  const steps = parseJsonOrNull(stepsText);
  if (!Array.isArray(steps)) {
    return "";
  }
  const pieces = [];
  for (const step of steps) {
    const error = step.error ? ` (${step.error})` : "";
    pieces.push(`${step.step} ${step.ms} ms${error}`);
  }
  return pieces.join(", ");
}

// "Call Mom, 2026-10-20 18:00, list work, repeat week"
function resultSummary(resultText) {
  const reminder = parseJsonOrNull(resultText);
  if (reminder === null || typeof reminder !== "object") {
    return "";
  }
  const pieces = [reminder.title];
  if (reminder.date) {
    pieces.push(reminder.time ? `${reminder.date} ${reminder.time}` : `${reminder.date} all day`);
  }
  if (reminder.list) {
    pieces.push(`list ${reminder.list}`);
  }
  if (reminder.repeat) {
    pieces.push(`repeat ${JSON.stringify(reminder.repeat)}`);
  }
  return pieces.join(", ");
}

// One block per attempt, for reading in the terminal
export function formatVoiceLogRows(rows) {
  if (rows.length === 0) {
    return "no voice log rows";
  }
  const blocks = [];
  for (const row of rows) {
    const outcome = row.status === "done" ? `done: ${resultSummary(row.result)}` : `not done: ${row.reason}`;
    const lines = [
      `${row.created_at}  ${outcome}`,
      `  said: "${row.transcript}"`,
      `  steps: ${stepsSummary(row.steps)}; total ${row.total_ms} ms; retries ${row.retries}; listened ${row.listen_ms ?? "?"} ms`,
      `  zone ${row.time_zone}; app ${row.app_version ?? "?"} (${row.app_build ?? "?"}); user ${row.user_id}`,
    ];
    if (row.status !== "done" && row.raw_reply) {
      lines.push(`  model said: ${row.raw_reply}`);
    }
    blocks.push(lines.join("\n"));
  }
  return blocks.join("\n\n");
}
