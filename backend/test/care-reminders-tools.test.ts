// The care-reminders Sidekick's tools (jess router, founder 2026-10-21: every action a person can
// take in the page is a tool). sidekicks/care-reminders/tools.js is loaded the way the deploy gate
// and the phone load it; every tool is called on real-shaped records and every record it would
// write is checked against manifest.json, as the shell's write gate checks it. The page's own
// rules hold: a reminder lives in a list and has a day and a time; Done on a repeat marks the
// time the page shows; a list's alerts are carried by each of its reminders.
process.env.TZ = "America/Los_Angeles";

import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import { loadToolsScript, sidekickToolsProblems } from "../scripts/sidekick-tools.mjs";

const folder = new URL("../../sidekicks/care-reminders/", import.meta.url);
const toolsText = readFileSync(new URL("tools.js", folder), "utf8");
const html = readFileSync(new URL("index.html", folder), "utf8");
const manifest = JSON.parse(readFileSync(new URL("manifest.json", folder), "utf8"));

const loaded = loadToolsScript(toolsText);
if (!("tools" in loaded)) {
  throw new Error(loaded.problem);
}
const tools = loaded.tools;

const LA = "America/Los_Angeles";
// Tuesday Oct 20, 2026, 10:00 in Los Angeles
const NOW = "2026-10-20T17:00:00.000Z";
const DAY_BEFORE = { id: "r1", kind: "daysBefore", days: 1, time: "18:00" };

type Records = Array<{ key: string; value: Record<string, unknown> }>;
type Outcome = {
  ops?: Array<{ op: string; key: string; value?: Record<string, unknown> }>;
  refused?: string;
  result: { text: string; at?: string | null; allDay?: boolean };
};

function baseRecords(): Records {
  return [
    { key: "list:medicine", value: { $type: "care.list", name: "Medicine", icon: "pill", color: "butter", alerts: [], order: 1, createdAt: "2026-10-01T00:00:00.000Z" } },
    { key: "list:appointments", value: { $type: "care.list", name: "Appointments", icon: "stethoscope", color: "charcoal", alerts: [DAY_BEFORE], order: 0, createdAt: "2026-10-01T00:00:00.000Z" } },
    { key: "list:water", value: { $type: "care.list", name: "Water", icon: "drop", color: "sky", alerts: [], order: 2, createdAt: "2026-10-01T00:00:00.000Z" } },
    { key: "settings:seeded", value: { $type: "care.settings", at: "2026-10-01T00:00:00.000Z" } },
    { key: "reminder:ipills001", value: { $type: "care.item", title: "Pills", list: "medicine", at: "2026-10-01T16:00:00.000Z", timeZone: LA, done: false, repeat: { every: "day" }, createdAt: "2026-10-01T00:00:00.000Z" } },
    { key: "reminder:identist1", value: { $type: "care.item", title: "Dentist", list: "appointments", at: "2026-10-23T17:00:00.000Z", timeZone: LA, done: false, alerts: [DAY_BEFORE], createdAt: "2026-10-10T00:00:00.000Z" } },
    { key: "reminder:ieyes0001", value: { $type: "care.item", title: "Eye exam", list: "appointments", at: "2026-10-19T17:00:00.000Z", timeZone: LA, done: true, completedAt: "2026-10-19T18:00:00.000Z", alerts: [DAY_BEFORE], createdAt: "2026-10-10T00:00:00.000Z" } },
    { key: "reminder:iwater001", value: { $type: "care.item", title: "Drink water", list: "water", at: "2026-10-01T16:00:00.000Z", timeZone: LA, done: false, repeat: { every: "day" }, everyHours: 2, createdAt: "2026-10-01T00:00:00.000Z" } },
    { key: "reminder:imom00001", value: { $type: "care.item", title: "Mom's pills", list: "medicine", at: "2026-10-01T15:00:00.000Z", timeZone: LA, done: false, repeat: { every: "day" }, createdAt: "2026-10-01T00:00:00.000Z" } },
    { key: "reminder:idad00001", value: { $type: "care.item", title: "Dad's pills", list: "medicine", at: "2026-10-01T15:00:00.000Z", timeZone: LA, done: false, repeat: { every: "day" }, createdAt: "2026-10-01T00:00:00.000Z" } },
  ];
}

function deepFreeze<T>(value: T): T {
  if (value && typeof value === "object") {
    for (const field of Object.keys(value as object)) {
      deepFreeze((value as Record<string, unknown>)[field]);
    }
    Object.freeze(value);
  }
  return value;
}

function call(verb: string, input: Record<string, unknown>, records: Records = baseRecords()): Outcome {
  const outcome = tools.handlers[verb](input, deepFreeze(records), NOW);
  return JSON.parse(JSON.stringify(outcome));
}

function writtenValue(outcome: Outcome, key: string) {
  const op = (outcome.ops || []).find(function isKey(candidate) {
    return candidate.key === key;
  });
  return op ? op.value : undefined;
}

function opKeys(outcome: Outcome) {
  const keys: string[] = [];
  for (const op of outcome.ops || []) {
    keys.push(op.op + " " + op.key);
  }
  return keys;
}

function expectSchemaValid(outcome: Outcome) {
  expect(outcome.refused).toBeUndefined();
  expect(Array.isArray(outcome.ops)).toBe(true);
  for (const op of outcome.ops || []) {
    expect(["set", "delete"]).toContain(op.op);
    if (op.op === "set") {
      const stamped = MidasRecordSchema.stampType(manifest.types, op.key, op.value);
      expect(MidasRecordSchema.checkRecord(manifest.types, op.key, stamped), op.key).toBeNull();
    }
  }
}

function expectRefused(outcome: Outcome, reason: string) {
  expect(outcome.refused).toBe(reason);
  expect(outcome.ops).toBeUndefined();
  expect(typeof outcome.result.text).toBe("string");
}

function when(fields: Record<string, unknown>) {
  return { date: null, time: null, allDay: false, at: null, repeat: null, timeZone: LA, ...fields };
}

describe("care-reminders tools: the files agree", () => {
  it("passes the deploy gate's tools check (agent block, handlers, copied page code)", () => {
    expect(sidekickToolsProblems(manifest, toolsText, html, "care-reminders")).toEqual([]);
  });

  it("has one handler per tool, covering every page action", () => {
    const verbs: string[] = [];
    for (const tool of manifest.agent.tools) {
      verbs.push(tool.name.slice("care-reminders.".length));
    }
    expect(Object.keys(tools.handlers).sort()).toEqual(verbs.sort());
    expect(verbs.sort()).toEqual(["add", "add_list_alert", "complete", "create_list", "delete", "delete_list", "edit", "edit_list", "remove_list_alert", "uncomplete"]);
  });

  it("carries the page's CareLogic character for character", () => {
    const start = html.indexOf("var CareLogic = (function createCareLogic() {");
    const end = html.indexOf("\n})();\n", start);
    const pageLogic = html.slice(start, end + "\n})();\n".length);
    expect(pageLogic.length).toBeGreaterThan(10000);
    expect(toolsText.includes(pageLogic)).toBe(true);
  });
});

describe("care-reminders.add", () => {
  it("adds to the list named, today at the next whole hour when no time was said (the page's Add sheet)", () => {
    const outcome = call("add", { title: "Insulin", list: "medicine", when: null, everyHours: null });
    expectSchemaValid(outcome);
    const op = outcome.ops![0];
    expect(op.key).toMatch(/^reminder:i[0-9a-z]{8}$/);
    expect(op.value).toEqual({ $type: "care.item", title: "Insulin", list: "medicine", at: "2026-10-20T18:00:00.000Z", timeZone: LA, done: false, createdAt: NOW });
    expect(outcome.result).toEqual({ text: "Added Insulin", at: "2026-10-20T18:00:00.000Z", allDay: false });
  });

  it("carries the list's alerts and the said time and repeat", () => {
    const outcome = call("add", { title: "Physio", list: "Appointments", when: when({ date: "2026-10-26", time: "10:00", repeat: { every: "week" } }), everyHours: null });
    expectSchemaValid(outcome);
    const value = outcome.ops![0].value!;
    expect(value.at).toBe("2026-10-26T17:00:00.000Z");
    expect(value.repeat).toEqual({ every: "week" });
    expect(value.alerts).toEqual([DAY_BEFORE]);
  });

  it("stores every N hours as the page does: a daily repeat plus everyHours, no alerts", () => {
    const outcome = call("add", { title: "Sip water", list: "water", when: when({ date: "2026-10-20", time: "09:00" }), everyHours: 3 });
    expectSchemaValid(outcome);
    const value = outcome.ops![0].value!;
    expect(value.repeat).toEqual({ every: "day" });
    expect(value.everyHours).toBe(3);
    expect(value.alerts).toBeUndefined();
  });

  it("refuses a list the user does not have, and an empty title", () => {
    expectRefused(call("add", { title: "Pills", list: "Vitamins", when: null, everyHours: null }), "unknown-list");
    expectRefused(call("add", { title: "", list: "medicine", when: null, everyHours: null }), "no-title");
  });
});

describe("care-reminders.complete and uncomplete", () => {
  it("marks a repeat's shown dose done: lastDoneAt now, doneThrough today's 09:00", () => {
    const outcome = call("complete", { item: "Pills" });
    expectSchemaValid(outcome);
    const value = writtenValue(outcome, "reminder:ipills001")!;
    expect(value.done).toBe(false);
    expect(value.lastDoneAt).toBe(NOW);
    expect(value.doneThrough).toBe("2026-10-20T16:00:00.000Z");
  });

  it("marks a one-time reminder done and clears its snooze and its alerts' snoozes, keeping an hourly one", () => {
    const records = baseRecords();
    records[5].value.snoozedUntil = "2026-10-20T18:00:00.000Z";
    records[5].value.snoozes = { "~r1": "2026-10-22T02:00:00.000Z" };
    const outcome = call("complete", { item: "dentist" }, records);
    expectSchemaValid(outcome);
    const value = writtenValue(outcome, "reminder:identist1")!;
    expect(value.done).toBe(true);
    expect(value.completedAt).toBe(NOW);
    expect(value.snoozedUntil).toBeUndefined();
    expect(value.snoozes).toBeUndefined();
  });

  it("refuses two reminders that fit, naming both", () => {
    const outcome = call("complete", { item: "pills for mom and dad" });
    expect(outcome.refused).toBe("not-found");
    const both = call("complete", { item: "'s pills" });
    expectRefused(both, "ambiguous");
  });

  it("refuses a reminder already done", () => {
    expectRefused(call("complete", { item: "Eye exam" }), "already-done");
  });

  it("undoes a one-time Done", () => {
    // Done today: the page shows a done reminder, and its Not Done, only on the day it was done
    // (jess router review, founder 2026-10-21, item 7)
    const records = baseRecords();
    records[6].value.at = "2026-10-20T15:00:00.000Z";
    records[6].value.completedAt = "2026-10-20T16:00:00.000Z";
    const outcome = call("uncomplete", { item: "eye exam" }, records);
    expectSchemaValid(outcome);
    const value = writtenValue(outcome, "reminder:ieyes0001")!;
    expect(value.done).toBe(false);
    expect(value.completedAt).toBeUndefined();
  });

  it("undoes a repeat's Done: doneThrough steps back, lastDoneAt and slotsDone go", () => {
    const records = baseRecords();
    records[4].value.doneThrough = "2026-10-20T16:00:00.000Z";
    records[4].value.lastDoneAt = "2026-10-20T16:05:00.000Z";
    const outcome = call("uncomplete", { item: "Pills" }, records);
    expectSchemaValid(outcome);
    const value = writtenValue(outcome, "reminder:ipills001")!;
    expect(value.doneThrough).toBe("2026-10-19T16:00:00.000Z");
    expect(value.lastDoneAt).toBeUndefined();
    expect(value.slotsDone).toBeUndefined();
  });

  it("refuses to undo a reminder with no Done", () => {
    expectRefused(call("uncomplete", { item: "Dentist" }), "not-done");
  });
});

describe("care-reminders.edit and delete", () => {
  it("moves a reminder to a new time: it starts again, not done", () => {
    const outcome = call("edit", { item: "Eye exam", title: null, when: when({ date: "2026-10-26", time: "15:00" }), everyHours: null });
    expectSchemaValid(outcome);
    const value = writtenValue(outcome, "reminder:ieyes0001")!;
    expect(value.at).toBe("2026-10-26T22:00:00.000Z");
    expect(value.done).toBe(false);
    expect(value.completedAt).toBeUndefined();
    expect(value.alerts).toEqual([DAY_BEFORE]);
    expect(value.list).toBe("appointments");
  });

  it("renames without moving, and refuses an edit that changes nothing", () => {
    const value = writtenValue(call("edit", { item: "Dentist", title: "Dentist check-up", when: null, everyHours: null }), "reminder:identist1")!;
    expect(value.title).toBe("Dentist check-up");
    expect(value.at).toBe("2026-10-23T17:00:00.000Z");
    expectRefused(call("edit", { item: "Dentist", title: "Dentist", when: null, everyHours: null }), "nothing-to-change");
  });

  it("deletes one reminder", () => {
    const outcome = call("delete", { item: "Drink water" });
    expect(opKeys(outcome)).toEqual(["delete reminder:iwater001"]);
  });
});

describe("care-reminders lists and their alerts", () => {
  it("creates a list after the others, with no alerts", () => {
    const outcome = call("create_list", { name: "Physio", icon: "barbell", color: "sage" });
    expectSchemaValid(outcome);
    const value = outcome.ops![0].value!;
    expect(outcome.ops![0].key).toMatch(/^list:l[0-9a-z]{8}$/);
    expect(value).toEqual({ $type: "care.list", name: "Physio", icon: "barbell", color: "sage", alerts: [], order: 3, createdAt: NOW });
    expectRefused(call("create_list", { name: "water", icon: null, color: null }), "list-exists");
  });

  it("renames a list and keeps its alerts and order", () => {
    const outcome = call("edit_list", { list: "Medicine", name: "Meds", icon: null, color: "clay" });
    expectSchemaValid(outcome);
    const value = writtenValue(outcome, "list:medicine")!;
    expect(value.name).toBe("Meds");
    expect(value.color).toBe("clay");
    expect(value.order).toBe(1);
    expect(value.createdAt).toBe("2026-10-01T00:00:00.000Z");
  });

  it("deletes a list and every reminder in it", () => {
    const outcome = call("delete_list", { list: "appointments" });
    expect(opKeys(outcome)).toEqual(["delete reminder:identist1", "delete reminder:ieyes0001", "delete list:appointments"]);
  });

  it("adds an alert to a list and to each of its reminders", () => {
    const outcome = call("add_list_alert", { list: "Appointments", kind: "before", days: null, minutes: 30, time: null });
    expectSchemaValid(outcome);
    const listAlerts = writtenValue(outcome, "list:appointments")!.alerts as Array<Record<string, unknown>>;
    expect(listAlerts).toHaveLength(2);
    expect(listAlerts[1]).toEqual({ id: expect.stringMatching(/^r[0-9a-z]{8}$/), kind: "before", minutes: 30 });
    expect(writtenValue(outcome, "reminder:identist1")!.alerts).toEqual(listAlerts);
    expect(writtenValue(outcome, "reminder:ieyes0001")!.alerts).toEqual(listAlerts);
    expect(outcome.result.text).toBe("Added alert: 30 min before");
  });

  it("refuses the same alert twice and a sixth alert", () => {
    expectRefused(call("add_list_alert", { list: "Appointments", kind: "daysBefore", days: 1, minutes: null, time: "18:00" }), "nothing-to-change");
    const records = baseRecords();
    const rules = [];
    for (let index = 1; index <= 5; index += 1) {
      rules.push({ id: "r" + index, kind: "before", minutes: index * 10 });
    }
    records[1].value.alerts = rules;
    expectRefused(call("add_list_alert", { list: "Appointments", kind: "morningOf", days: null, minutes: null, time: null }, records), "too-many-alerts");
  });

  it("removes an alert from a list and its reminders", () => {
    const outcome = call("remove_list_alert", { list: "Appointments", kind: "daysBefore", days: null, minutes: null, time: null });
    expectSchemaValid(outcome);
    expect(writtenValue(outcome, "list:appointments")!.alerts).toEqual([]);
    expect(writtenValue(outcome, "reminder:identist1")!.alerts).toBeUndefined();
    expectRefused(call("remove_list_alert", { list: "Medicine", kind: "before", days: null, minutes: null, time: null }), "not-found");
  });
});

describe("care-reminders context for jess", () => {
  it("lists the lists with their alerts and each reminder with its list, time and repeat", () => {
    const context = JSON.parse(JSON.stringify(tools.context(deepFreeze(baseRecords()), NOW)));
    expect(context.lists).toContainEqual({ name: "Appointments", alerts: ["1 day before"] });
    const dentist = context.items.find(function isDentist(item: { title: string }) { return item.title === "Dentist"; });
    expect(dentist).toEqual({ title: "Dentist", list: "Appointments", when: "2026-10-23 10:00", repeat: "never", done: false });
    const eyes = context.items.find(function isEyes(item: { title: string }) { return item.title === "Eye exam"; });
    expect(eyes.done).toBe(true);
  });
});
