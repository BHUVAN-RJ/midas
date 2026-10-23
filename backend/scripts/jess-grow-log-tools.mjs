// Pure helpers for jess-grow-log.mjs (jess grows the Sidekick, founder 2026-10-21), kept apart
// from the wrangler call so they can be tested. The script only reads; it never changes a row.
import { sqlLiteral } from "./db-tools.mjs";
import { sinceToIso } from "./voice-log-tools.mjs";

export const DEFAULT_LIMIT = 50;
export const MAX_LIMIT = 1000;

// The script's options, or { problem } with what is wrong
export function parseGrowLogArgs(argv, now) {
  const options = { since: null, limit: DEFAULT_LIMIT };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--env") {
      index += 1;
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

// Newest first: each pending request with its repair's status and the re-run's log row
export function growLogSql(options) {
  const conditions = [];
  if (options.since) {
    conditions.push(`p.created_at >= ${sqlLiteral(options.since)}`);
  }
  const where = conditions.length === 0 ? "" : `WHERE ${conditions.join(" AND ")}`;
  return [
    "SELECT p.id, p.created_at, p.user_id, p.sidekick_id, p.transcript, p.feature, p.request_now, p.time_zone, p.status, p.fail_reason, p.steps,",
    "p.report_id, r.status AS repair_status, r.fail_reason AS repair_fail_reason,",
    "v.tool AS rerun_tool, v.tool_input AS rerun_input, v.reason AS rerun_reason, v.phone_outcome AS rerun_phone_outcome",
    "FROM jess_pending_requests p JOIN repair_reports r ON r.id = p.report_id LEFT JOIN voice_logs v ON v.id = p.rerun_log_id",
    where,
    `ORDER BY p.created_at DESC LIMIT ${options.limit}`,
  ].join(" ");
}

function stepLine(step) {
  const details = [];
  for (const [name, value] of Object.entries(step)) {
    if (name !== "step" && name !== "at") {
      details.push(`${name}=${typeof value === "string" ? value : JSON.stringify(value)}`);
    }
  }
  const suffix = details.length === 0 ? "" : " " + details.join(" ");
  return `    ${step.at}  ${step.step}${suffix}`;
}

function parsedSteps(stepsText) {
  try {
    const steps = JSON.parse(stepsText);
    return Array.isArray(steps) ? steps : [];
  } catch {
    return [];
  }
}

// One block per pending request: what was said, what was missing, the repair, the re-run, every step
export function formatGrowLogRows(rows) {
  if (rows.length === 0) {
    return "No pending requests.";
  }
  const blocks = [];
  for (const row of rows) {
    const lines = [
      `${row.created_at}  ${row.status}${row.fail_reason ? " (" + row.fail_reason + ")" : ""}  ${row.sidekick_id}  user ${row.user_id}  pending ${row.id}`,
      `  said: "${row.transcript}"  at ${row.request_now} ${row.time_zone}`,
      `  missing: ${row.feature}`,
      `  repair ${row.report_id}: ${row.repair_status}${row.repair_fail_reason ? " (" + row.repair_fail_reason + ")" : ""}`,
    ];
    if (row.rerun_tool || row.rerun_reason) {
      const rerunWhat = row.rerun_tool ? `${row.rerun_tool} ${row.rerun_input ?? ""}` : `not done: ${row.rerun_reason}`;
      lines.push(`  re-run: ${rerunWhat}  phone: ${row.rerun_phone_outcome ?? "-"}`);
    }
    lines.push("  steps:");
    for (const step of parsedSteps(row.steps)) {
      lines.push(stepLine(step));
    }
    blocks.push(lines.join("\n"));
  }
  return blocks.join("\n\n");
}
