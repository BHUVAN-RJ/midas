// Before a repaired copy is published, every record the reporter already has must still pass the
// copy's new schema (unified data plan, section 6; founder, 2026-10-19). The records come from
// the runner-only route GET /repairs/<id>/records and are checked exactly as stored, with the
// same validator the phone and the server run (shell/sdk/record-schema.js). The runner loads it
// from the checkout it tests and deploys from (settings.checkoutRoot), so one repo decides
// everything about a job; see loadDataModules. Nothing is written.
import { existsSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import { newFieldClashes } from "./schema-change.mjs";

const SHELL_PREFIXES = ["widget:", "request:"];
// How many failing records the detail names; the rest are counted.
const NAMED_FAILURES = 3;

const VALIDATOR_PATH = join("shell", "sdk", "record-schema.js");

// This repo's own validator: for scripts that run from the checkout they belong to (the copies
// planner). The runner passes the checkout's instead.
export const OWN_DATA_MODULES = { MidasRecordSchema };

// The validator from a checkout. Throws when the checkout has none: a runner pointed at a
// checkout without it must not check with another repo's rules.
export async function loadDataModules(checkoutRoot) {
  const validatorPath = join(checkoutRoot, VALIDATOR_PATH);
  if (!existsSync(validatorPath)) {
    throw new Error(`the checkout ${checkoutRoot} has no ${VALIDATOR_PATH}`);
  }
  const validatorModule = await import(pathToFileURL(validatorPath).href);
  return { MidasRecordSchema: validatorModule.default };
}

function isShellKey(key) {
  return SHELL_PREFIXES.some(function startsWithShellPrefix(prefix) {
    return key.startsWith(prefix);
  });
}

function isPlainObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

// Problems only the stored records show (founder, 2026-10-19: add only), for breakingChangeVerdict:
// a new field name a record already holds (newFieldClashes), and a key whose type would change
// or that a new prefix would claim (a new prefix next to an old one, or matching stored keys).
// A record that does not fit its schema is checked too, so the reason is then the clash, not the
// misfit. Each text is given once.
function storedSchemaProblems({ pageRecords, oldTypes, newTypes, modules }) {
  const problems = [];
  for (const record of pageRecords) {
    const oldType = modules.MidasRecordSchema.typeForKey(oldTypes, record.key);
    const newType = modules.MidasRecordSchema.typeForKey(newTypes, record.key);
    if (newType === null || (oldType !== null && oldType.prefix === newType.prefix)) {
      continue;
    }
    const wasText = oldType === null ? "had no type" : `was ${oldType.$type} (types["${oldType.prefix}"])`;
    problems.push(`the user's ${record.key} ${wasText} and would now be ${newType.$type} (types["${newType.prefix}"] is new)`);
  }
  for (const record of pageRecords) {
    const oldType = modules.MidasRecordSchema.typeForKey(oldTypes, record.key);
    const newType = modules.MidasRecordSchema.typeForKey(newTypes, record.key);
    if (oldType === null || newType === null || oldType.prefix !== newType.prefix) {
      continue;
    }
    problems.push(...newFieldClashes({ oldSchema: oldType.schema, newSchema: newType.schema, value: record.value, typeName: newType.$type, key: record.key }));
  }
  return [...new Set(problems)];
}

function pageRecordsOf(records) {
  return records.filter(function isPageRecord(record) {
    return !isShellKey(record.key);
  });
}

// records: [{ key, value }] (latest per key, no tombstones). manifest: the repaired copy's.
// modules: the validator to use (loadDataModules; this repo's own by default).
// Returns { checked, failures: [{ key, problem }] }. Shell-owned records (widget:, request:) are
// the shell's to check and are left out.
export function checkUserRecords({ records, manifest, modules = OWN_DATA_MODULES }) {
  const types = manifest?.types;
  const pageRecords = pageRecordsOf(records);
  const failures = [];
  for (const record of pageRecords) {
    const problem = modules.MidasRecordSchema.checkRecord(types, record.key, record.value);
    if (problem !== null) {
      failures.push({ key: record.key, problem });
    }
  }
  return { checked: pageRecords.length, failures };
}

// What the reporter's stored records say about the schema change itself, as problem texts for
// breakingChangeVerdict (empty when either manifest has no types: that is refused elsewhere).
export function storedRecordSchemaProblems({ records, manifestBefore, manifest, modules = OWN_DATA_MODULES }) {
  if (!isPlainObject(manifestBefore?.types) || !isPlainObject(manifest?.types)) {
    return [];
  }
  return storedSchemaProblems({ pageRecords: pageRecordsOf(records), oldTypes: manifestBefore.types, newTypes: manifest.types, modules });
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
