// Before a repaired copy is published, every record the reporter already has must still pass the
// copy's new schema (unified data plan, section 6; founder, 2026-10-19). The records come from
// the runner-only route GET /repairs/<id>/records. Records stored before the unified data format
// are first upgraded in memory the way the page upgrades them on read (record-upgrades.mjs, the
// same functions the migration uses; what they convert is described only in
// docs/legacy/LEGACY-RECORD-FORMATS.DO-NOT-READ.md), then
// checked with the same validator the phone and the server run (shell/sdk/record-schema.js).
// The runner loads both from the checkout it tests and deploys from (settings.checkoutRoot), so
// one repo decides everything about a job; see loadDataModules. Nothing is written.
import { existsSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import { recordsAfter, upgradeSidekickRecords } from "../../backend/scripts/record-upgrades.mjs";
import { newFieldClashes } from "./schema-change.mjs";

const SHELL_PREFIXES = ["widget:", "request:"];
// How many failing records the detail names; the rest are counted.
const NAMED_FAILURES = 3;

const VALIDATOR_PATH = join("shell", "sdk", "record-schema.js");
const UPGRADES_PATH = join("backend", "scripts", "record-upgrades.mjs");

// This repo's own validator and upgrades: for scripts that run from the checkout they belong to
// (the copies planner). The runner passes the checkout's instead.
export const OWN_DATA_MODULES = { MidasRecordSchema, recordsAfter, upgradeSidekickRecords };

// The validator and the upgrades from a checkout. Throws when the checkout has neither file:
// a runner pointed at a checkout without them must not check with another repo's rules.
export async function loadDataModules(checkoutRoot) {
  const validatorPath = join(checkoutRoot, VALIDATOR_PATH);
  const upgradesPath = join(checkoutRoot, UPGRADES_PATH);
  for (const modulePath of [validatorPath, upgradesPath]) {
    if (!existsSync(modulePath)) {
      throw new Error(`the checkout ${checkoutRoot} has no ${modulePath.slice(checkoutRoot.length + 1)}`);
    }
  }
  const validatorModule = await import(pathToFileURL(validatorPath).href);
  const upgradesModule = await import(pathToFileURL(upgradesPath).href);
  return {
    MidasRecordSchema: validatorModule.default,
    recordsAfter: upgradesModule.recordsAfter,
    upgradeSidekickRecords: upgradesModule.upgradeSidekickRecords,
  };
}

function isShellKey(key) {
  return SHELL_PREFIXES.some(function startsWithShellPrefix(prefix) {
    return key.startsWith(prefix);
  });
}

function isPlainObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

// How many of the stored records the upgrade changes: rewritten in place or replaced (a record the
// upgrade moves to a new key is one record, though it is a write and a delete).
function countUpgradedRecords(pageRecords, plan) {
  const storedKeys = new Set(pageRecords.map(function keyOfRecord(record) {
    return record.key;
  }));
  const changed = new Set(plan.deletes);
  for (const write of plan.writes) {
    if (storedKeys.has(write.key)) {
      changed.add(write.key);
    }
  }
  return changed.size;
}

// The stored key(s) a checked key came from, when the upgrade gave it a new key (the record is
// checked under its new key): each replaced record is upgraded alone to see which one makes the key.
function storedKeysFor({ key, sidekickId, pageRecords, plan, manifest, modules }) {
  const isStored = pageRecords.some(function hasKey(record) {
    return record.key === key;
  });
  if (isStored) {
    return [key];
  }
  const sources = [];
  for (const deletedKey of plan.deletes) {
    const deletedRecord = pageRecords.find(function hasDeletedKey(record) {
      return record.key === deletedKey;
    });
    const alonePlan = modules.upgradeSidekickRecords(sidekickId, [deletedRecord], manifest);
    const madeKeys = [...alonePlan.writes, ...alonePlan.problems].map(function keyOfEntry(entry) {
      return entry.key;
    });
    if (madeKeys.includes(key)) {
      sources.push(deletedKey);
    }
  }
  return sources;
}

// Problems only the stored records show (founder, 2026-10-19: add only), for breakingChangeVerdict:
// a new field name a record already holds (newFieldClashes), and a key whose type would change
// or that a new prefix would claim (a new prefix next to an old one, or matching stored keys).
// The field check runs on each stored record and its upgraded form. A record whose upgrade fails
// and that moves key is in neither under a typed key, so its stored value
// is checked under the key it upgrades to; the reason is then the clash, not the misfit. Each
// text is given once. recordsToCheck: [{ key, value }], each value read under the type of key.
function storedSchemaProblems({ keys, recordsToCheck, oldTypes, newTypes, modules }) {
  const problems = [];
  for (const key of keys) {
    const oldType = modules.MidasRecordSchema.typeForKey(oldTypes, key);
    const newType = modules.MidasRecordSchema.typeForKey(newTypes, key);
    if (newType === null || (oldType !== null && oldType.prefix === newType.prefix)) {
      continue;
    }
    const wasText = oldType === null ? "had no type" : `was ${oldType.$type} (types["${oldType.prefix}"])`;
    problems.push(`the user's ${key} ${wasText} and would now be ${newType.$type} (types["${newType.prefix}"] is new)`);
  }
  for (const record of recordsToCheck) {
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
// modules: the validator and upgrades to use (loadDataModules; this repo's own by default).
// Returns { checked, upgraded, failures: [{ key, storedAs, problem }] }; storedAs (the stored
// key(s) behind an upgraded key) is filled for the failures the detail names. Shell-owned
// records (widget:, request:) are the shell's to check and are left out.
export function checkUserRecords({ sidekickId, records, manifest, modules = OWN_DATA_MODULES }) {
  const types = manifest?.types;

  const pageRecords = pageRecordsOf(records);
  const plan = modules.upgradeSidekickRecords(sidekickId, pageRecords, manifest);
  const problems = [...plan.problems];
  const failedKeys = new Set(plan.problems.map(function keyOfProblem(problem) {
    return problem.key;
  }));
  const recordsNow = modules.recordsAfter(pageRecords, plan);
  for (const record of recordsNow) {
    if (failedKeys.has(record.key)) {
      continue;
    }
    const problem = modules.MidasRecordSchema.checkRecord(types, record.key, record.value);
    if (problem !== null) {
      problems.push({ key: record.key, problem });
    }
  }
  const failures = problems.map(function withStoredKeys(failure, index) {
    if (index >= NAMED_FAILURES) {
      return { key: failure.key, problem: failure.problem };
    }
    const storedAs = storedKeysFor({ key: failure.key, sidekickId, pageRecords, plan, manifest, modules });
    return { key: failure.key, storedAs, problem: failure.problem };
  });
  return { checked: recordsNow.length, upgraded: countUpgradedRecords(pageRecords, plan), failures };
}

// What the reporter's stored records say about the schema change itself, as problem texts for
// breakingChangeVerdict (empty when either manifest has no types: that is refused elsewhere).
export function storedRecordSchemaProblems({ sidekickId, records, manifestBefore, manifest, modules = OWN_DATA_MODULES }) {
  if (!isPlainObject(manifestBefore?.types) || !isPlainObject(manifest?.types)) {
    return [];
  }
  const pageRecords = pageRecordsOf(records);
  const plan = modules.upgradeSidekickRecords(sidekickId, pageRecords, manifest);
  const recordsNow = modules.recordsAfter(pageRecords, plan);
  const keys = new Set([...pageRecords, ...recordsNow].map(function keyOfRecord(record) {
    return record.key;
  }));
  const failedUpgrades = [];
  for (const problem of plan.problems) {
    const storedKeys = storedKeysFor({ key: problem.key, sidekickId, pageRecords, plan, manifest, modules });
    for (const storedKey of storedKeys) {
      const storedRecord = pageRecords.find(function hasStoredKey(record) {
        return record.key === storedKey;
      });
      failedUpgrades.push({ key: problem.key, value: storedRecord.value });
    }
  }
  const recordsToCheck = [...pageRecords, ...recordsNow, ...failedUpgrades];
  return storedSchemaProblems({ keys, recordsToCheck, oldTypes: manifestBefore.types, newTypes: manifest.types, modules });
}

// "<key> (stored as <stored key>)" when the upgrade moved the record, else the key alone.
function describeFailureKey(failure) {
  const storedAs = failure.storedAs ?? [failure.key];
  const movedFrom = storedAs.filter(function isOtherKey(storedKey) {
    return storedKey !== failure.key;
  });
  if (movedFrom.length === 0) {
    return failure.key;
  }
  return `${failure.key} (stored as ${movedFrom.join(", ")})`;
}

// The failure detail for the job: the first few keys and why, then how many more.
export function recordFailureDetail(failures) {
  const named = failures.slice(0, NAMED_FAILURES).map(function describeFailure(failure) {
    return `${describeFailureKey(failure)}: ${failure.problem}`;
  });
  const moreCount = failures.length - named.length;
  const more = moreCount > 0 ? `; and ${moreCount} more` : "";
  return `${failures.length} of the user's records do not fit the new schema: ${named.join("; ")}${more}`;
}
