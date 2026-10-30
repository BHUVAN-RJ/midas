// The Reminders Sidekick's tools (jess router, founder 2026-10-21: every action a person can take
// in the page is a tool). sidekicks/reminders/tools.js is loaded the way the deploy gate and the
// phone load it (a fresh context, no network, no store); every tool is called on real-shaped
// records and every record it would write is checked against manifest.json, the same check the
// shell's write gate makes. Matching: an exact title wins, a part of a title that fits two
// reminders refuses, and nothing is written on a refusal.
process.env.TZ = "America/Los_Angeles";

import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import { loadToolsScript, sidekickToolsProblems } from "../scripts/sidekick-tools.mjs";

const folder = new URL("../../sidekicks/reminders/", import.meta.url);
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

type Records = Array<{ key: string; value: Record<string, unknown> }>;
type Outcome = {
  ops?: Array<{ op: string; key: string; value?: Record<string, unknown> }>;
  refused?: string;
  result: { text: string; at?: string | null; allDay?: boolean };
};

function baseRecords(): Records {
  return [
    { key: "list:work", value: { $type: "reminders.list", name: "Work", color: "#007AFF", icon: "briefcase", createdAt: "2026-10-01T00:00:00.000Z" } },
    { key: "list:groceries", value: { $type: "reminders.list", name: "Groceries", color: "#34C759", icon: "cart", createdAt: "2026-10-02T00:00:00.000Z" } },
    { key: "settings:self", value: { $type: "reminders.settings", order: ["today", "next7", "scheduled", "unscheduled", "all", "pastDue", "completed", "work", "groceries"] } },
    { key: "reminder:callmom00001", value: { $type: "reminders.item", title: "Call Mom", done: false, timeZone: LA, at: "2026-10-21T01:00:00.000Z", allDay: false, createdAt: "2026-10-10T00:00:00.000Z" } },
    { key: "reminder:callmomback1", value: { $type: "reminders.item", title: "Call Mom back", done: true, completedAt: "2026-10-19T00:00:00.000Z", timeZone: LA, createdAt: "2026-10-10T00:00:00.000Z" } },
    { key: "reminder:pills0000001", value: { $type: "reminders.item", title: "Pills", done: false, timeZone: LA, at: "2026-10-01T16:00:00.000Z", allDay: false, repeat: { every: "day" }, createdAt: "2026-10-01T00:00:00.000Z" } },
    { key: "reminder:report000001", value: { $type: "reminders.item", title: "Send the report", done: false, timeZone: LA, list: "work", notes: "Q3", image: "file:abc", createdAt: "2026-10-12T00:00:00.000Z" } },
    { key: "reminder:report000002", value: { $type: "reminders.item", title: "Read the report", done: false, timeZone: LA, list: "work", createdAt: "2026-10-12T00:00:00.000Z" } },
    { key: "reminder:twins0000001", value: { $type: "reminders.item", title: "Water plants", done: false, timeZone: LA, createdAt: "2026-10-12T00:00:00.000Z" } },
    { key: "reminder:twins0000002", value: { $type: "reminders.item", title: "Water plants", done: false, timeZone: LA, list: "groceries", createdAt: "2026-10-13T00:00:00.000Z" } },
    { key: "reminder:dentist00001", value: { $type: "reminders.item", title: "Dentist", done: true, completedAt: "2026-10-15T00:00:00.000Z", timeZone: LA, createdAt: "2026-10-12T00:00:00.000Z" } },
    { key: "reminder:dentist00002", value: { $type: "reminders.item", title: "Dentist", done: false, timeZone: LA, at: "2026-10-23T17:00:00.000Z", allDay: false, createdAt: "2026-10-16T00:00:00.000Z" } },
    { key: "history:0000", value: { $type: "reminders.history", items: [
      { id: "aold1", title: "Renew passport", notes: "", list: null, date: null, time: null, repeat: null, timeZone: LA, done: true, completedAt: "2026-01-01T00:00:00.000Z", snoozedUntil: null, lastDoneAt: null, createdAt: "2025-12-01T00:00:00.000Z", source: { kind: "apple-reminders", externalId: "x1" } },
    ] } },
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

// Every call gets frozen records, so a handler that changed what it was given would throw
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

// The shell's write gate: each set must fit its key's type in manifest.json
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

// A "when" as Midas hands it over after working out the words
function when(fields: Record<string, unknown>) {
  return { date: null, time: null, allDay: false, at: null, repeat: null, timeZone: LA, ...fields };
}

describe("Reminders tools: the files agree", () => {
  it("passes the deploy gate's tools check (agent block, handlers, copied page code)", () => {
    expect(sidekickToolsProblems(manifest, toolsText, html, "reminders")).toEqual([]);
  });

  it("has a handler for every tool and a tool for every handler", () => {
    const verbs: string[] = [];
    for (const tool of manifest.agent.tools) {
      verbs.push(tool.name.slice("reminders.".length));
    }
    expect(Object.keys(tools.handlers).sort()).toEqual(verbs.sort());
    expect(verbs.sort()).toEqual(["add", "complete", "create_list", "delete", "edit", "move", "move_list", "uncomplete"]);
  });

  it("carries the page's RemindersLogic character for character", () => {
    const start = html.indexOf("var RemindersLogic = (function createRemindersLogic() {");
    const end = html.indexOf("\n})();\n", start);
    const pageLogic = html.slice(start, end + "\n})();\n".length);
    expect(pageLogic.length).toBeGreaterThan(10000);
    expect(toolsText.includes(pageLogic)).toBe(true);
  });
});

describe("reminders.add", () => {
  it("adds an undated reminder the way the page and the old voice save build it", () => {
    const outcome = call("add", { title: "Buy milk", notes: null, list: null, when: null });
    expectSchemaValid(outcome);
    expect(outcome.ops).toHaveLength(1);
    const op = outcome.ops![0];
    expect(op.key).toMatch(/^reminder:[0-9a-z]{12}$/);
    expect(op.value).toEqual({ $type: "reminders.item", title: "Buy milk", done: false, timeZone: expect.any(String), createdAt: NOW });
    expect(outcome.result).toEqual({ text: "Added Buy milk", at: null, allDay: false });
  });

  it("puts it in the list named and keeps notes", () => {
    const outcome = call("add", { title: "Bananas", notes: "ripe ones", list: "groceries", when: null });
    expectSchemaValid(outcome);
    const value = outcome.ops![0].value!;
    expect(value.list).toBe("groceries");
    expect(value.notes).toBe("ripe ones");
  });

  it("dates it from the worked-out when: at, allDay and the repeat", () => {
    const outcome = call("add", { title: "Call Dad", notes: null, list: null, when: when({ date: "2026-10-21", time: "18:00", at: "2026-10-22T01:00:00.000Z", repeat: { every: "week", weekdays: [3] } }) });
    expectSchemaValid(outcome);
    const value = outcome.ops![0].value!;
    expect(value.at).toBe("2026-10-22T01:00:00.000Z");
    expect(value.allDay).toBe(false);
    expect(value.repeat).toEqual({ every: "week", weekdays: [3] });
    expect(value.timeZone).toBe(LA);
    expect(outcome.result).toEqual({ text: "Added Call Dad", at: "2026-10-22T01:00:00.000Z", allDay: false });
  });

  it("books an all-day reminder at 09:00, as the page does", () => {
    const outcome = call("add", { title: "Bins", notes: null, list: null, when: when({ date: "2026-10-22", allDay: true, at: "2026-10-22T16:00:00.000Z" }) });
    expectSchemaValid(outcome);
    const value = outcome.ops![0].value!;
    expect(value.allDay).toBe(true);
    expect(value.at).toBe("2026-10-22T16:00:00.000Z");
  });

  it("refuses a list the user does not have, and an empty title", () => {
    expectRefused(call("add", { title: "Bananas", notes: null, list: "Holiday", when: null }), "unknown-list");
    expectRefused(call("add", { title: "  ", notes: null, list: null, when: null }), "no-title");
  });
});

describe("reminders.complete and uncomplete", () => {
  it("marks a one-time reminder done with completedAt", () => {
    const outcome = call("complete", { item: "call mom" });
    expectSchemaValid(outcome);
    const value = writtenValue(outcome, "reminder:callmom00001")!;
    expect(value.done).toBe(true);
    expect(value.completedAt).toBe(NOW);
    expect(outcome.result.text).toBe("Marked done: Call Mom");
  });

  it("marks a repeat's shown time done: lastDoneAt now, doneThrough today's 09:00, the reminder stays open", () => {
    const outcome = call("complete", { item: "Pills" });
    expectSchemaValid(outcome);
    const value = writtenValue(outcome, "reminder:pills0000001")!;
    expect(value.done).toBe(false);
    expect(value.lastDoneAt).toBe(NOW);
    expect(value.doneThrough).toBe("2026-10-20T16:00:00.000Z");
    expect(value.at).toBe("2026-10-01T16:00:00.000Z");
  });

  it("clears a snooze when marked done", () => {
    const records = baseRecords();
    records[3].value.snoozedUntil = "2026-10-20T18:00:00.000Z";
    const value = writtenValue(call("complete", { item: "Call Mom" }, records), "reminder:callmom00001")!;
    expect(value.snoozedUntil).toBeUndefined();
  });

  it("picks the open one when an open and a done reminder share the exact title", () => {
    const outcome = call("complete", { item: "Dentist" });
    expectSchemaValid(outcome);
    expect(outcome.ops![0].key).toBe("reminder:dentist00002");
  });

  it("refuses when two open reminders fit, naming both", () => {
    const outcome = call("complete", { item: "the report" });
    expectRefused(outcome, "ambiguous");
    expect(outcome.result.text).toContain("Send the report");
    expect(outcome.result.text).toContain("Read the report");
    expectRefused(call("complete", { item: "water plants" }), "ambiguous");
  });

  it("refuses a reminder that is already done, and one that does not exist", () => {
    expectRefused(call("complete", { item: "Call Mom back" }), "already-done");
    expectRefused(call("complete", { item: "feed the cat" }), "not-found");
  });

  it("marks a completed reminder not done: done false, completedAt removed", () => {
    const outcome = call("uncomplete", { item: "call mom back" });
    expectSchemaValid(outcome);
    const value = writtenValue(outcome, "reminder:callmomback1")!;
    expect(value.done).toBe(false);
    expect(value.completedAt).toBeUndefined();
  });

  it("brings a completed reminder out of history: its own record first, then history without it", () => {
    const outcome = call("uncomplete", { item: "renew passport" });
    expectSchemaValid(outcome);
    expect(outcome.ops!.map(function keyOf(op) { return op.op + " " + op.key; })).toEqual(["set reminder:aold1", "delete history:0000"]);
    expect(writtenValue(outcome, "reminder:aold1")!.title).toBe("Renew passport");
    expect(writtenValue(outcome, "reminder:aold1")!.done).toBe(false);
  });

  it("does not uncomplete an open reminder", () => {
    expectRefused(call("uncomplete", { item: "Pills" }), "not-done");
  });

  it("never takes a done reminder's exact title as part of an open one's ('Call Mom back' is not 'Call Mom')", () => {
    const outcome = call("complete", { item: "Call Mom back" });
    expectRefused(outcome, "already-done");
    expect(outcome.result.text).toBe("Already done: Call Mom back");
  });
});

describe("reminders.edit and move", () => {
  it("renames and keeps every other field, unknown ones included", () => {
    const outcome = call("edit", { item: "send the report", title: "Send the Q3 report", notes: null, when: null, clearDate: false });
    expectSchemaValid(outcome);
    const value = writtenValue(outcome, "reminder:report000001")!;
    expect(value.title).toBe("Send the Q3 report");
    expect(value.notes).toBe("Q3");
    expect(value.image).toBe("file:abc");
    expect(value.list).toBe("work");
  });

  it("moves to a new time: at changes and the old snooze goes", () => {
    const records = baseRecords();
    records[3].value.snoozedUntil = "2026-10-20T18:00:00.000Z";
    const outcome = call("edit", { item: "Call Mom", title: null, notes: null, when: when({ date: "2026-10-23", time: "17:00", at: "2026-10-24T00:00:00.000Z" }), clearDate: false }, records);
    expectSchemaValid(outcome);
    const value = writtenValue(outcome, "reminder:callmom00001")!;
    expect(value.at).toBe("2026-10-24T00:00:00.000Z");
    expect(value.snoozedUntil).toBeUndefined();
  });

  it("takes the date off", () => {
    const value = writtenValue(call("edit", { item: "Call Mom", title: null, notes: null, when: null, clearDate: true }), "reminder:callmom00001")!;
    expect(value.at).toBeUndefined();
    expect(value.allDay).toBeUndefined();
  });

  it("refuses an edit that changes nothing", () => {
    expectRefused(call("edit", { item: "Call Mom", title: "Call Mom", notes: null, when: null, clearDate: false }), "nothing-to-change");
  });

  it("moves a reminder to a list, and out of it", () => {
    const into = call("move", { item: "Call Mom", list: "Work" });
    expectSchemaValid(into);
    expect(writtenValue(into, "reminder:callmom00001")!.list).toBe("work");
    expect(into.result.text).toBe("Moved Call Mom to Work");
    const out = call("move", { item: "Send the report", list: null });
    expectSchemaValid(out);
    expect(writtenValue(out, "reminder:report000001")!.list).toBeUndefined();
    expectRefused(call("move", { item: "Send the report", list: "Work" }), "nothing-to-change");
    expectRefused(call("move", { item: "Call Mom", list: "Garden" }), "unknown-list");
  });
});

describe("reminders.delete", () => {
  it("deletes a reminder record", () => {
    const outcome = call("delete", { item: "Call Mom" });
    expectSchemaValid(outcome);
    expect(outcome.ops).toEqual([{ op: "delete", key: "reminder:callmom00001" }]);
    expect(outcome.result.text).toBe("Deleted Call Mom");
  });

  it("refuses a part of a title that fits an open and a done reminder", () => {
    expectRefused(call("delete", { item: "call" }), "ambiguous");
  });

  it("deletes a completed reminder kept in history by rewriting that history record", () => {
    const records = baseRecords();
    const history = records[records.length - 1].value as { items: unknown[] };
    history.items.push({ id: "aold2", title: "Pay tax", notes: "", list: null, date: null, time: null, repeat: null, timeZone: LA, done: true, completedAt: "2026-01-02T00:00:00.000Z", snoozedUntil: null, lastDoneAt: null, createdAt: "2025-12-01T00:00:00.000Z", source: null });
    const outcome = call("delete", { item: "renew passport" }, records);
    expectSchemaValid(outcome);
    const value = writtenValue(outcome, "history:0000") as { items: Array<{ id: string }> };
    expect(value.items.map(function idOf(item) { return item.id; })).toEqual(["aold2"]);
  });
});

// The sidebar order saved in the sample records, before any tool runs
function sampleOrder(): string[] {
  const settings = baseRecords().find(function isSettings(record) {
    return record.key === "settings:self";
  });
  return settings!.value.order as string[];
}

// The ids of `order` that are in `wanted`, in the order `order` has them
function onlyIds(order: string[], wanted: string[]): string[] {
  return order.filter(function isWanted(id) {
    return wanted.includes(id);
  });
}

// The records after the outcome's sets and deletes are applied, the way the shell stores them
function applyOps(records: Records, outcome: Outcome): Records {
  let result = records.slice();
  for (const op of outcome.ops || []) {
    result = result.filter(function isOtherKey(record) {
      return record.key !== op.key;
    });
    if (op.op === "set") {
      result.push({ key: op.key, value: op.value! });
    }
  }
  return result;
}

describe("reminders lists", () => {
  // Lists are rearrangeable, so these check relative position, not the whole sidebar of the
  // sample data (founder, 2026-10-30: docs/PRODUCT.md, "a separate test guardian for Sidekicks")
  it("creates a list and puts it last in the sidebar order", () => {
    const outcome = call("create_list", { name: "Travel", color: "orange", icon: "airplane" });
    expectSchemaValid(outcome);
    const listOp = outcome.ops![0];
    expect(listOp.key).toMatch(/^list:[0-9a-z]{12}$/);
    expect(listOp.value).toEqual({ $type: "reminders.list", name: "Travel", color: "#FF9500", icon: "airplane", createdAt: NOW });
    const order = writtenValue(outcome, "settings:self")!.order as string[];
    const newId = listOp.key.slice("list:".length);
    // The new list comes once, right after the list that was last before it
    expect(order[order.length - 1]).toBe(newId);
    expect(order.indexOf(newId)).toBe(order.length - 1);
    // The lists already there are all still there, in the same relative order
    const previousOrder = order.slice(0, -1);
    expect(new Set(previousOrder).size).toBe(previousOrder.length);
    expect(onlyIds(previousOrder, sampleOrder())).toEqual(sampleOrder());
  });

  it("refuses a list name that is already there", () => {
    expectRefused(call("create_list", { name: "work", color: null, icon: null }), "list-exists");
  });

  it("moves a list in the sidebar: first, last, before and after another", () => {
    const first = writtenValue(call("move_list", { list: "Groceries", position: "first", other: null }), "settings:self")!.order as string[];
    expect(first[0]).toBe("groceries");
    const before = writtenValue(call("move_list", { list: "Groceries", position: "before", other: "Work" }), "settings:self")!.order as string[];
    expect(before.indexOf("groceries")).toBe(before.indexOf("work") - 1);
    const after = writtenValue(call("move_list", { list: "Today", position: "after", other: "Groceries" }), "settings:self")!.order as string[];
    // Today sits right after Groceries, once, and every other list keeps its relative order
    expect(after.indexOf("today")).toBe(after.indexOf("groceries") + 1);
    expect(after.lastIndexOf("today")).toBe(after.indexOf("today"));
    const othersBefore = sampleOrder().filter(function isNotToday(id) {
      return id !== "today";
    });
    expect(onlyIds(after, othersBefore)).toEqual(othersBefore);
    // Also after a list that is not last, so "after" cannot pass by appending
    const afterWork = writtenValue(call("move_list", { list: "Today", position: "after", other: "Work" }), "settings:self")!.order as string[];
    expect(afterWork.indexOf("today")).toBe(afterWork.indexOf("work") + 1);
    // Moving whichever list is actually last to last changes nothing: the last list is read
    // from the saved order, not assumed from the sample data
    const created = call("create_list", { name: "Travel", color: null, icon: null });
    const withTravel = applyOps(baseRecords(), created);
    const savedOrder = writtenValue(created, "settings:self")!.order as string[];
    const lastId = savedOrder[savedOrder.length - 1];
    const lastList = withTravel.find(function isLastList(record) {
      return record.key === "list:" + lastId;
    });
    expectRefused(call("move_list", { list: lastList!.value.name, position: "last", other: null }, withTravel), "nothing-to-change");
    expectRefused(call("move_list", { list: "Garden", position: "first", other: null }), "unknown-list");
  });
});

describe("Reminders context for jess", () => {
  it("lists the user's lists and reminders, open ones first, with list names", () => {
    const context = JSON.parse(JSON.stringify(tools.context(deepFreeze(baseRecords()), NOW)));
    expect(context.lists).toEqual(["Work", "Groceries"]);
    const titles = context.items.map(function titleOf(item: { title: string }) { return item.title; });
    expect(titles.indexOf("Call Mom")).toBeLessThan(titles.indexOf("Call Mom back"));
    expect(titles).toContain("Renew passport");
    const report = context.items.find(function isReport(item: { title: string }) { return item.title === "Send the report"; });
    expect(report).toEqual({ title: "Send the report", list: "Work", when: null, repeats: false, done: false });
    const call = context.items.find(function isCall(item: { title: string }) { return item.title === "Call Mom"; });
    expect(call.when).toBe("2026-10-20 18:00");
  });
});
