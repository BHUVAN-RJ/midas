// OLD RECORD SHAPES ARE ALLOWED HERE ONLY. This file is the upgrade-on-read converter: with
// migrate-records.mjs and the tests of both, it is the only code that may still understand the
// record formats used before the unified data format (founder, 2026-10-20). Their description
// lives only in docs/legacy/LEGACY-RECORD-FORMATS.DO-NOT-READ.md. Never copy a shape from here
// into other code, tests or docs; new code writes the unified format only.
//
// Moving existing data to the unified shapes (unified data plan, section 8). Nothing is deleted:
// the migration writes new ops (a tombstone where a key is retired) and the old rows stay. The
// same functions describe the "upgrade on read" the pages do: the result of upgrading a record
// is the record a page would write today. Pure: no I/O; migrate-records.mjs does the reading
// and writing.
import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import MidasShellTypes from "../../shell/sdk/shell-types.js";

const INSTANT_FIELDS = ["at", "snoozedUntil", "lastDoneAt", "doneThrough", "completedAt", "createdAt", "finishedAt", "exportedAt", "occurrenceAt"];
const CARE_LEGACY_FIELDS = ["kind", "body", "icon", "alertRules", "seriesId"];
const CARE_HOURLY_INTERVALS = [2, 3, 4];

// Literal writes of shapes the rework retired (unified data plan, section 4), for the user-copy
// planner (user-copy-plan.mjs) to flag a page that still writes them.
export const RETIRED_WRITE_PATTERNS = [
  { pattern: /store\.(?:set|update)\(\s*['"`]task:/, what: "writes task: records" },
  { pattern: /store\.(?:set|update)\(\s*['"`]settings:sidebar['"`]/, what: "writes settings:sidebar" },
];

// ---- small helpers ---------------------------------------------------------------------------

function isObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function copyWithoutNulls(value) {
  const copy = {};
  for (const fieldName of Object.keys(value)) {
    if (value[fieldName] !== null && value[fieldName] !== undefined) {
      copy[fieldName] = value[fieldName];
    }
  }
  return copy;
}

// Epoch milliseconds (an older shape) to ISO 8601; a string is kept as it is.
export function instantText(value) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return new Date(value).toISOString();
  }
  return value;
}

function withInstantsAsText(value) {
  const copy = { ...value };
  for (const fieldName of INSTANT_FIELDS) {
    if (copy[fieldName] !== undefined) {
      copy[fieldName] = instantText(copy[fieldName]);
    }
  }
  if (isObject(copy.repeat) && copy.repeat.until !== undefined) {
    copy.repeat = { ...copy.repeat, until: instantText(copy.repeat.until) };
  }
  return copy;
}

function sameJson(first, second) {
  return JSON.stringify(sortKeys(first)) === JSON.stringify(sortKeys(second));
}

function sortKeys(value) {
  if (Array.isArray(value)) {
    return value.map(sortKeys);
  }
  if (!isObject(value)) {
    return value;
  }
  const sorted = {};
  for (const fieldName of Object.keys(value).sort()) {
    sorted[fieldName] = sortKeys(value[fieldName]);
  }
  return sorted;
}

function keyId(key) {
  const colon = key.indexOf(":");
  return colon === -1 ? key : key.slice(colon + 1);
}

// The types a record is checked against: the shell's own for its prefixes, the manifest's for the rest.
export function typesFor(manifest) {
  return { ...(manifest?.types ?? {}), ...MidasShellTypes };
}

function stamped(types, key, value) {
  return MidasRecordSchema.stampType(types, key, value);
}

// ---- reminders -------------------------------------------------------------------------------

// An item of the Reminders page as written today: no body (notes only), instants as text, no
// nulls, $type stamped.
export function upgradeRemindersItem(value, types) {
  let item = withInstantsAsText(copyWithoutNulls(value));
  if (item.notes === undefined && typeof item.body === "string" && item.body !== "") {
    item.notes = item.body;
  }
  delete item.body;
  if (item.list === null) {
    delete item.list;
  }
  item = copyWithoutNulls(item);
  return stamped(types, "reminder:x", item);
}

// ---- care-reminders --------------------------------------------------------------------------

// A rule as the care page stores it (cleanRule): only its kind's fields, no text when default.
export function cleanCareRule(rule) {
  const text = typeof rule.text === "string" && rule.text.trim() !== "" ? rule.text.trim() : null;
  let cleaned;
  if (rule.kind === "daysBefore") {
    const days = Math.min(14, Math.max(1, Math.round(Number(rule.days) || 1)));
    cleaned = { id: rule.id, kind: "daysBefore", days, time: rule.time || "18:00" };
  } else if (rule.kind === "morningOf") {
    cleaned = { id: rule.id, kind: "morningOf", time: rule.time || "08:00" };
  } else {
    const minutes = Math.max(1, Math.round(Number(rule.minutes) || 60));
    cleaned = { id: rule.id, kind: "before", minutes };
  }
  if (text !== null) {
    cleaned.text = text;
  }
  return cleaned;
}

function isCareHourly(item) {
  return CARE_HOURLY_INTERVALS.includes(Number(item.everyHours)) && isObject(item.repeat) && item.repeat.every === "day";
}

// A care item folded with its old alert (~rule) and time (@HHMM) records: Done on any alert
// completes the event (a repeat: that occurrence); a time's Done becomes slotsDone; an alert's or
// a time's own snooze becomes its entry in `snoozes` (`~rule` / `@HHMM`, founder 2026-10-15: each
// keeps its own snooze and wording). The list's rules are copied onto the item as alerts (none
// for an hourly item).
export function upgradeCareItem(value, legacyAlerts, legacySlots, list, types) {
  let item = withInstantsAsText(copyWithoutNulls(value));
  for (const fieldName of CARE_LEGACY_FIELDS) {
    delete item[fieldName];
  }
  const isRepeat = isObject(item.repeat);
  const snoozes = { ...(isObject(item.snoozes) ? item.snoozes : {}) };
  for (const alert of legacyAlerts) {
    if (!isObject(alert)) {
      continue;
    }
    const alertSuffix = typeof alert.rule === "string" ? `~${alert.rule}` : null;
    if (alert.done !== true && alertSuffix !== null && alert.snoozedUntil !== undefined && alert.snoozedUntil !== null && snoozes[alertSuffix] === undefined) {
      snoozes[alertSuffix] = instantText(alert.snoozedUntil);
    }
    if (alert.done !== true) {
      continue;
    }
    if (isRepeat) {
      const occurrence = instantText(alert.occurrenceAt);
      if (typeof occurrence === "string" && (item.doneThrough === undefined || Date.parse(occurrence) > Date.parse(item.doneThrough))) {
        item.doneThrough = occurrence;
      }
    } else if (item.done !== true) {
      item.done = true;
      item.completedAt = instantText(alert.lastDoneAt) ?? new Date().toISOString();
    }
  }
  const slotsDone = { ...(isObject(item.slotsDone) ? item.slotsDone : {}) };
  for (const slot of legacySlots) {
    if (!isObject(slot) || typeof slot.time !== "string") {
      continue;
    }
    if (slot.lastDoneAt !== undefined && slot.lastDoneAt !== null && slotsDone[slot.time] === undefined) {
      slotsDone[slot.time] = instantText(slot.lastDoneAt);
    }
    const slotSuffix = `@${slot.time.replace(":", "")}`;
    if (slot.snoozedUntil !== undefined && slot.snoozedUntil !== null && snoozes[slotSuffix] === undefined) {
      snoozes[slotSuffix] = instantText(slot.snoozedUntil);
    }
  }
  if (Object.keys(slotsDone).length > 0) {
    item.slotsDone = slotsDone;
  } else {
    delete item.slotsDone;
  }
  if (Object.keys(snoozes).length > 0) {
    item.snoozes = snoozes;
  } else {
    delete item.snoozes;
  }
  if (isCareHourly(item)) {
    delete item.alerts;
  } else {
    delete item.everyHours;
    const rules = isObject(list) && Array.isArray(list.alerts) ? list.alerts.map(cleanCareRule) : [];
    if (rules.length > 0) {
      item.alerts = rules;
    } else {
      delete item.alerts;
    }
  }
  item = copyWithoutNulls(item);
  return stamped(types, "reminder:x", item);
}

export function upgradeCareList(value, types) {
  const list = copyWithoutNulls(withInstantsAsText(value));
  if (Array.isArray(list.alerts)) {
    list.alerts = list.alerts.map(cleanCareRule);
  }
  return stamped(types, "list:x", list);
}

// ---- one Sidekick's records ------------------------------------------------------------------

function splitCareKey(key) {
  const rest = keyId(key);
  const slotSeparator = rest.indexOf("@");
  if (slotSeparator !== -1) {
    return { itemId: rest.slice(0, slotSeparator), part: "slot" };
  }
  const alertSeparator = rest.indexOf("~");
  if (alertSeparator !== -1) {
    return { itemId: rest.slice(0, alertSeparator), part: "alert" };
  }
  return { itemId: rest, part: "item" };
}

// The writes and deletes that bring one user's records of one Sidekick to today's shapes.
// `records` is the latest value per key, tombstones left out: [{ key, value }]. `manifest` is the
// Sidekick's manifest (its types decide the stamps and the check). Returns
// { writes: [{key, value}], deletes: [key], unchanged, problems: [{key, problem}] }. A write that
// does not pass its schema is reported and not written: nothing is written for that user until fixed.
export function upgradeSidekickRecords(sidekickId, records, manifest) {
  const types = typesFor(manifest);
  const byKey = new Map();
  for (const record of records) {
    byKey.set(record.key, record.value);
  }
  const plan = { writes: [], deletes: [], unchanged: 0, problems: [] };

  function propose(key, upgradedValue) {
    const currentValue = byKey.get(key);
    if (currentValue !== undefined && sameJson(currentValue, upgradedValue)) {
      plan.unchanged += 1;
      return;
    }
    const problem = MidasRecordSchema.checkRecord(types, key, upgradedValue);
    if (problem !== null) {
      plan.problems.push({ key, problem });
      return;
    }
    plan.writes.push({ key, value: upgradedValue });
  }

  if (sidekickId === "reminders") {
    upgradeRemindersRecords(records, byKey, types, propose, plan);
  } else if (sidekickId === "care-reminders") {
    upgradeCareRecords(records, byKey, types, plan, propose);
  } else {
    for (const record of records) {
      if (isObject(record.value)) {
        propose(record.key, stamped(types, record.key, copyWithoutNulls(record.value)));
      }
    }
  }
  return plan;
}

function upgradeRemindersRecords(records, byKey, types, propose, plan) {
  for (const record of records) {
    const { key, value } = record;
    if (!isObject(value)) {
      continue;
    }
    if (key.startsWith("task:")) {
      const newKey = `reminder:${keyId(key)}`;
      if (!byKey.has(newKey)) {
        propose(newKey, upgradeRemindersItem(value, types));
      }
      plan.deletes.push(key);
    } else if (key.startsWith("reminder:")) {
      propose(key, upgradeRemindersItem(value, types));
    } else if (key === "settings:sidebar") {
      if (!byKey.has("settings:self")) {
        propose("settings:self", stamped(types, "settings:self", copyWithoutNulls(value)));
      }
      plan.deletes.push(key);
    } else {
      propose(key, stamped(types, key, copyWithoutNulls(value)));
    }
  }
}

function upgradeCareRecords(records, byKey, types, plan, propose) {
  const lists = {};
  const alertsByItem = {};
  const slotsByItem = {};
  const items = [];
  for (const record of records) {
    const { key, value } = record;
    if (!isObject(value)) {
      continue;
    }
    if (key.startsWith("list:")) {
      lists[keyId(key)] = value;
      continue;
    }
    if (!key.startsWith("reminder:")) {
      continue;
    }
    const { itemId, part } = splitCareKey(key);
    if (part === "alert") {
      (alertsByItem[itemId] ??= []).push(value);
      plan.deletes.push(key);
    } else if (part === "slot") {
      (slotsByItem[itemId] ??= []).push(value);
      plan.deletes.push(key);
    } else {
      items.push({ key, value, itemId });
    }
  }
  for (const record of records) {
    const { key, value } = record;
    if (!isObject(value) || key.startsWith("reminder:")) {
      continue;
    }
    if (key.startsWith("list:")) {
      propose(key, upgradeCareList(value, types));
    } else {
      propose(key, stamped(types, key, copyWithoutNulls(value)));
    }
  }
  for (const item of items) {
    const list = lists[item.value.list] ?? null;
    propose(item.key, upgradeCareItem(item.value, alertsByItem[item.itemId] ?? [], slotsByItem[item.itemId] ?? [], list, types));
  }
}

// ---- the op log --------------------------------------------------------------------------------

// The latest record per (user, sidekick, key) from ops in seq order; a tombstone removes the key.
export function replayOps(opRows) {
  const recordsByUserAndSidekick = new Map();
  for (const row of opRows) {
    const groupKey = `${row.user_id}\u0000${row.sidekick_id}`;
    if (!recordsByUserAndSidekick.has(groupKey)) {
      recordsByUserAndSidekick.set(groupKey, { userId: row.user_id, sidekickId: row.sidekick_id, records: new Map() });
    }
    const group = recordsByUserAndSidekick.get(groupKey);
    if (Number(row.deleted) === 1) {
      group.records.delete(row.key);
      continue;
    }
    let value;
    try {
      value = typeof row.value === "string" ? JSON.parse(row.value) : row.value;
    } catch {
      continue;
    }
    group.records.set(row.key, value);
  }
  const groups = [];
  for (const group of recordsByUserAndSidekick.values()) {
    const records = [];
    for (const [key, value] of group.records) {
      records.push({ key, value });
    }
    groups.push({ userId: group.userId, sidekickId: group.sidekickId, records });
  }
  return groups;
}

// Deterministic op ids, so running the migration twice stores every op once (ON CONFLICT DO NOTHING).
export function migrationOpId(hashHex, userId, sidekickId, key, value) {
  const text = `${userId}|${sidekickId}|${key}|${value === null ? "" : JSON.stringify(sortKeys(value))}`;
  return `mig1-${hashHex(text).slice(0, 40)}`;
}

// How many items (reminders) a user has before and after: the plan loses none.
export function itemCount(records) {
  let count = 0;
  for (const record of records) {
    const isItem = record.key.startsWith("reminder:") || record.key.startsWith("task:");
    const isLegacyPart = record.key.includes("~") || record.key.includes("@");
    if (isItem && !isLegacyPart) {
      count += 1;
    }
  }
  return count;
}

export function recordsAfter(records, plan) {
  const byKey = new Map();
  for (const record of records) {
    byKey.set(record.key, record.value);
  }
  for (const key of plan.deletes) {
    byKey.delete(key);
  }
  for (const write of plan.writes) {
    byKey.set(write.key, write.value);
  }
  const after = [];
  for (const [key, value] of byKey) {
    after.push({ key, value });
  }
  return after;
}
