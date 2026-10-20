// Before a repaired copy is published, every record the reporter already has must still pass the
// copy's new schema (unified data plan, section 6; founder, 2026-10-19). The records come from
// the runner-only route GET /repairs/<id>/records. Records still in an older shape (no "$type",
// task:, body, epoch ms, care ~rule / @HHMM parts) are first upgraded in memory the way the page
// upgrades them on read (record-upgrades.mjs, the same functions the migration uses), then
// checked with the same validator the phone and the server run (shell/sdk/record-schema.js). Both
// come from the runner's own repo, which is the checkout it deploys from. Nothing is written.
import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import { recordsAfter, upgradeSidekickRecords } from "../../backend/scripts/record-upgrades.mjs";

const SHELL_PREFIXES = ["widget:", "request:"];
// How many failing records the detail names; the rest are counted.
const NAMED_FAILURES = 3;

function isShellKey(key) {
  return SHELL_PREFIXES.some(function startsWithShellPrefix(prefix) {
    return key.startsWith(prefix);
  });
}

// records: [{ key, value }] (latest per key, no tombstones). manifest: the repaired copy's.
// Returns { checked, upgraded, failures: [{ key, problem }] }. Shell-owned records (widget:,
// request:) are the shell's to check and are left out.
export function checkUserRecords({ sidekickId, records, manifest }) {
  const types = manifest?.types;

  const pageRecords = records.filter(function isPageRecord(record) {
    return !isShellKey(record.key);
  });
  const plan = upgradeSidekickRecords(sidekickId, pageRecords, manifest);
  const failures = [...plan.problems];
  const failedKeys = new Set(plan.problems.map(function keyOfProblem(problem) {
    return problem.key;
  }));
  const recordsNow = recordsAfter(pageRecords, plan);
  for (const record of recordsNow) {
    if (failedKeys.has(record.key)) {
      continue;
    }
    const problem = MidasRecordSchema.checkRecord(types, record.key, record.value);
    if (problem !== null) {
      failures.push({ key: record.key, problem });
    }
  }
  return { checked: recordsNow.length, upgraded: plan.writes.length + plan.deletes.length, failures };
}

// The failure detail for the job: the first few keys and why, then how many more.
export function recordFailureDetail(failures) {
  const named = failures.slice(0, NAMED_FAILURES).map(function describeFailure(failure) {
    return `${failure.key}: ${failure.problem}`;
  });
  const moreCount = failures.length - named.length;
  const more = moreCount > 0 ? `; and ${moreCount} more` : "";
  return `${failures.length} of the user's records do not fit the new schema: ${named.join("; ")}${more}`;
}
