// The To-Do Sidekick's tools (docs/briefs/todo-sidekick.md, step 3; jess router, founder
// 2026-10-21: every action a person can take on the page is a tool). sidekicks/todo/tools.js is
// loaded the way the deploy gate and the phone load it; every tool is called on real-shaped
// records and every record it would write is checked against manifest.json, as the shell's write
// gate checks it.
process.env.TZ = "America/Los_Angeles";

import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import { checkBundleFiles } from "../scripts/bundle-tools.mjs";
import { copiedBlocks, loadToolsScript, sidekickToolsProblems } from "../scripts/sidekick-tools.mjs";

const folder = new URL("../../sidekicks/todo/", import.meta.url);
const toolsText = readFileSync(new URL("tools.js", folder), "utf8");
const html = readFileSync(new URL("index.html", folder), "utf8");
const manifestText = readFileSync(new URL("manifest.json", folder), "utf8");
const manifest = JSON.parse(manifestText);

const loaded = loadToolsScript(toolsText);
if (!("tools" in loaded)) {
  throw new Error(loaded.problem);
}
const tools = loaded.tools;

const LA = "America/Los_Angeles";
// Saturday Oct 31, 2026, 10:00 in Los Angeles
const NOW = "2026-10-31T17:00:00.000Z";

type Value = Record<string, unknown>;
type Records = Array<{ key: string; value: Value }>;
type Op = { op: string; key: string; value?: Value };
type Outcome = { ops?: Op[]; refused?: string; result: { text: string; [field: string]: unknown } };

function item(title: string, fields: Value = {}): Value {
  return { $type: "todo.item", title, list: "inbox", subtasks: [], done: false, order: 1, someday: false, createdAt: "2026-10-30T17:00:00.000Z", ...fields };
}

// A person's to-dos as the page writes them, with what the shell wrote on a timed one
function baseRecords(): Records {
  return [
    { key: "list:groceries", value: { $type: "todo.list", name: "Groceries", emoji: "🛒", color: "#FFB224", wallpaper: "sand", order: 1 } },
    { key: "reminder:laundry", value: item("Laundry", { when: "2026-10-28", order: 1 }) },
    { key: "reminder:gym", value: item("Gym", { when: "2026-10-31", recur: { every: "weekday", from: "schedule" }, order: 2 }) },
    {
      key: "reminder:call", value: item("Call dad", {
        when: "2026-10-31", time: "17:00", at: "2026-11-01T00:00:00.000Z", timeZone: LA, alerts: [{ before: 10 }],
        reminderType: "timeSensitive", snoozedUntil: "2026-11-01T00:10:00.000Z", order: 3,
      }),
    },
    { key: "reminder:eggs", value: item("Eggs", { list: "groceries", order: 4 }) },
    { key: "reminder:read", value: item("Read", { when: "2026-10-30", done: true, completedAt: "2026-10-30T20:00:00.000Z", order: 5 }) },
    { key: "reminder:old", value: item("Dentist", { deletedAt: "2026-10-29T17:00:00.000Z", order: 6 }) },
    { key: "settings:self", value: { $type: "todo.settings", preset: "mine", look: "notebook", theme: "auto", accent: "#2F6FEB", textSize: "m", density: "comfy", font: "system", checkbox: "end", showMeta: true, dateColors: true, tickSound: "chimes", haptic: true, celebrate: "allDone", doneGoes: "stay", add: "row", parse: true, swipeRight: "complete", swipeLeft: "delete", home: "tabs", todayModel: "carry", dayParts: false } },
  ];
}

// What Midas hands a tool for a when (the shell resolves the words; the tool never does dates)
function when(date: string, time: string | null = null, repeat: Value | null = null): Value {
  return { date, time, allDay: time === null, at: null, repeat, timeZone: LA };
}

function call(verb: string, input: Value, records: Records = baseRecords()): Outcome {
  return tools.handlers[verb](input, records, NOW) as Outcome;
}

// Every op a tool returns must pass the schema, as the shell's write gate checks it
function written(outcome: Outcome): Map<string, Value> {
  expect(outcome.refused, outcome.result.text).toBeUndefined();
  const values = new Map<string, Value>();
  for (const op of outcome.ops || []) {
    expect(op.op).toBe("set");
    const stamped = MidasRecordSchema.stampType(manifest.types, op.key, op.value as Value);
    expect(MidasRecordSchema.checkRecord(manifest.types, op.key, stamped), op.key).toBeNull();
    values.set(op.key, op.value as Value);
  }
  return values;
}

function refusedWith(outcome: Outcome, reason: string) {
  expect(outcome.refused).toBe(reason);
  expect(outcome.ops).toBeUndefined();
}

function pageTodoLogic() {
  const start = html.indexOf("var TodoLogic = (function createTodoLogic() {");
  const end = html.indexOf("\n})();\n", start) + "\n})();\n".length;
  return html.slice(start, end);
}

describe("todo: the files agree", () => {
  it("passes the whole deploy gate (page, manifest, tools)", () => {
    expect(checkBundleFiles(html, manifestText, "todo", toolsText).problems).toEqual([]);
    expect(sidekickToolsProblems(manifest, toolsText, html, "todo")).toEqual([]);
  });

  it("has the ten tools the brief names, one handler each", () => {
    const verbs: string[] = [];
    for (const tool of manifest.agent.tools) {
      verbs.push(tool.name.slice("todo.".length));
    }
    verbs.sort();
    expect(verbs).toEqual(["add", "complete", "delete", "edit", "move", "restore", "search", "set_setting", "today", "uncomplete"]);
    const handlerNames = Object.keys(tools.handlers);
    handlerNames.sort();
    expect(handlerNames).toEqual(verbs);
  });

  it("carries the page's TodoLogic character for character", () => {
    const blocks = copiedBlocks(toolsText);
    expect(blocks.length).toBe(1);
    expect(blocks[0].text).toBe(pageTodoLogic());
  });

  it("would be refused if the page's logic changed without tools.js", () => {
    const changedPage = html.replace("const TRASH_DAYS = 30;", "const TRASH_DAYS = 7;");
    expect(changedPage).not.toBe(html);
    const problems = sidekickToolsProblems(manifest, toolsText, changedPage, "todo");
    expect(problems.length).toBe(1);
    expect(problems[0]).toContain("no longer matches index.html");
  });

  it("offers Make It Yours's own values for every setting, and the founder's start as Mine", () => {
    const setTool = manifest.agent.tools.find((tool: Value) => tool.name === "todo.set_setting");
    const fields = setTool.inputSchema.properties.field.enum.filter((field: unknown) => field !== null);
    const settingsFields = Object.keys(baseRecords()[7].value).filter((key) => key !== "$type" && key !== "preset");
    expect(fields.sort()).toEqual(settingsFields.sort());
    expect(setTool.inputSchema.properties.preset.enum).toEqual(["mine", "paper", "notebook", "soft", "wallpaper", "heat", null]);
  });
});

describe("todo.add", () => {
  it("adds a timed weekly to-do with the engine's at, in the person's time zone", () => {
    const outcome = call("add", { title: "Call mum", notes: null, list: null, someday: null, when: when("2026-11-01", "17:00", { every: "week", interval: 1, weekdays: [] }) });
    const values = [...written(outcome).values()];
    expect(values).toHaveLength(1);
    expect(values[0]).toMatchObject({ title: "Call mum", list: "inbox", when: "2026-11-01", time: "17:00", recur: { every: "week", from: "schedule" }, done: false, at: "2026-11-02T01:00:00.000Z", timeZone: LA });
    expect(outcome.result.text).toBe("Added Call mum");
  });

  it("adds an untimed one to a list, with no at, so it never notifies", () => {
    const values = [...written(call("add", { title: "Milk", notes: "Oat", list: "groceries", someday: null, when: null })).values()];
    expect(values[0]).toMatchObject({ title: "Milk", notes: "Oat", list: "groceries", done: false });
    expect("at" in values[0]).toBe(false);
    expect("when" in values[0]).toBe(false);
  });

  it("puts one on someday, and an all-day one on its day without a time", () => {
    const someday = [...written(call("add", { title: "Learn piano", notes: null, list: null, someday: true, when: null })).values()][0];
    expect(someday.someday).toBe(true);
    const allDay = [...written(call("add", { title: "Pay rent", notes: null, list: null, someday: null, when: when("2026-11-03") })).values()][0];
    expect(allDay.when).toBe("2026-11-03");
    expect("time" in allDay).toBe(false);
  });

  it("turns every weekday into the weekday repeat, and refuses repeats the page does not offer", () => {
    const weekday = [...written(call("add", { title: "Standup", notes: null, list: null, someday: null, when: when("2026-11-02", "09:30", { every: "week", interval: 1, weekdays: [5, 1, 2, 3, 4] }) })).values()][0];
    expect(weekday.recur).toEqual({ every: "weekday", from: "schedule" });
    refusedWith(call("add", { title: "Gym", notes: null, list: null, someday: null, when: when("2026-11-02", null, { every: "week", interval: 2, weekdays: [] }) }), "repeat-not-offered");
    refusedWith(call("add", { title: "Gym", notes: null, list: null, someday: null, when: when("2026-11-02", null, { every: "week", interval: 1, weekdays: [1, 3] }) }), "repeat-not-offered");
    refusedWith(call("add", { title: "Birthday", notes: null, list: null, someday: null, when: when("2026-11-02", null, { every: "year", interval: 1, weekdays: [] }) }), "repeat-not-offered");
  });

  it("puts one for today into Today in the Fresh Start model", () => {
    const records = baseRecords();
    (records[7].value as Value).todayModel = "fresh";
    const value = [...written(call("add", { title: "Water plants", notes: null, list: null, someday: null, when: when("2026-10-31") }, records)).values()][0];
    expect(value.inToday).toBe("2026-10-31");
  });

  it("refuses a list that is not there and an empty title", () => {
    refusedWith(call("add", { title: "Nails", notes: null, list: "Hardware", someday: null, when: null }), "no-such-list");
    refusedWith(call("add", { title: "  ", notes: null, list: null, someday: null, when: null }), "no-title");
  });
});

describe("todo.complete and todo.uncomplete", () => {
  it("ticks one, keeping what the shell wrote", () => {
    const values = written(call("complete", { item: "call dad" }));
    const value = values.get("reminder:call") as Value;
    expect(value.done).toBe(true);
    expect(value.completedAt).toBe(NOW);
    expect(value.alerts).toEqual([{ before: 10 }]);
    expect(value.reminderType).toBe("timeSensitive");
    expect(values.size).toBe(1);
  });

  it("gives a repeat its next copy once", () => {
    const outcome = call("complete", { item: "Gym" });
    const values = written(outcome);
    expect(values.size).toBe(2);
    const ticked = values.get("reminder:gym") as Value;
    const nextKey = "reminder:" + ticked.nextId;
    expect((values.get(nextKey) as Value).when).toBe("2026-11-02");
    expect(outcome.result.text).toBe("Done: Gym, next one added");
    // Ticking the same again finds no open Gym but the new copy, a new day
    const after = baseRecords().filter((record) => record.key !== "reminder:gym");
    after.push({ key: "reminder:gym", value: ticked });
    after.push({ key: nextKey, value: values.get(nextKey) as Value });
    const again = written(call("complete", { item: "Gym" }, after));
    expect([...again.keys()]).toContain(nextKey);
  });

  it("unticks a done one, and refuses ones that are not there", () => {
    const value = written(call("uncomplete", { item: "Read" })).get("reminder:read") as Value;
    expect(value.done).toBe(false);
    expect("completedAt" in value).toBe(false);
    refusedWith(call("complete", { item: "Read" }), "no-such-to-do");
    refusedWith(call("uncomplete", { item: "Gym" }), "no-such-to-do");
    refusedWith(call("complete", { item: "Dentist" }), "no-such-to-do");
  });

  it("refuses two to-dos with the same title instead of guessing", () => {
    const records = baseRecords();
    records.push({ key: "reminder:eggs2", value: item("Eggs", { order: 9 }) });
    refusedWith(call("complete", { item: "Eggs" }, records), "two-match");
  });
});

describe("todo.move", () => {
  it("moves to another day and time, and the snooze goes with the old time", () => {
    const value = written(call("move", { item: "Call dad", when: when("2026-11-02", "18:00"), someday: null, clearDate: null, list: null })).get("reminder:call") as Value;
    expect(value.when).toBe("2026-11-02");
    expect(value.time).toBe("18:00");
    expect(value.at).toBe("2026-11-03T02:00:00.000Z");
    expect("snoozedUntil" in value).toBe(false);
  });

  it("moves to someday, to no date, and to another list", () => {
    const someday = written(call("move", { item: "Laundry", when: null, someday: true, clearDate: null, list: null })).get("reminder:laundry") as Value;
    expect(someday.someday).toBe(true);
    expect("when" in someday).toBe(false);
    const noDate = written(call("move", { item: "Call dad", when: null, someday: null, clearDate: true, list: null })).get("reminder:call") as Value;
    expect("when" in noDate).toBe(false);
    expect("at" in noDate).toBe(false);
    const listed = written(call("move", { item: "Laundry", when: null, someday: null, clearDate: null, list: "Groceries" })).get("reminder:laundry") as Value;
    expect(listed.list).toBe("groceries");
    expect(listed.when).toBe("2026-10-28");
  });

  it("refuses with nothing said", () => {
    refusedWith(call("move", { item: "Laundry", when: null, someday: null, clearDate: null, list: null }), "nothing-to-change");
  });
});

describe("todo.edit", () => {
  it("renames, notes, sets the part of day and the repeat", () => {
    const value = written(call("edit", { item: "Laundry", title: "Laundry and towels", notes: "Hot wash", part: "evening", repeat: "week", repeatFrom: "done" })).get("reminder:laundry") as Value;
    expect(value).toMatchObject({ title: "Laundry and towels", notes: "Hot wash", part: "evening", recur: { every: "week", from: "done" } });
  });

  it("gives a repeat with no day today as its first day, and stops a repeat", () => {
    const started = written(call("edit", { item: "Eggs", title: null, notes: null, part: null, repeat: "day", repeatFrom: null })).get("reminder:eggs") as Value;
    expect(started.when).toBe("2026-10-31");
    expect(started.recur).toEqual({ every: "day", from: "schedule" });
    const stopped = written(call("edit", { item: "Gym", title: null, notes: null, part: "anytime", repeat: "never", repeatFrom: null })).get("reminder:gym") as Value;
    expect("recur" in stopped).toBe(false);
    expect("part" in stopped).toBe(false);
  });

  it("refuses with nothing to change, or a repeat-from on one that does not repeat", () => {
    refusedWith(call("edit", { item: "Laundry", title: null, notes: null, part: null, repeat: null, repeatFrom: null }), "nothing-to-change");
    refusedWith(call("edit", { item: "Laundry", title: null, notes: null, part: null, repeat: null, repeatFrom: "done" }), "no-repeat");
  });
});

describe("todo.delete and todo.restore", () => {
  it("moves one to the Trash, timed ones losing their at", () => {
    const value = written(call("delete", { item: "Call dad" })).get("reminder:call") as Value;
    expect(value.deletedAt).toBe(NOW);
    expect("at" in value).toBe(false);
  });

  it("brings one back from the Trash, and only from there", () => {
    const value = written(call("restore", { item: "dentist" })).get("reminder:old") as Value;
    expect("deletedAt" in value).toBe(false);
    refusedWith(call("restore", { item: "Laundry" }), "no-such-to-do");
    refusedWith(call("delete", { item: "Dentist" }), "no-such-to-do");
  });
});

describe("todo.search and todo.today", () => {
  it("finds open and done ones and changes nothing", () => {
    const outcome = call("search", { query: "rea" });
    expect(outcome.ops).toEqual([]);
    expect(outcome.result.done).toEqual(["Read"]);
    const none = call("search", { query: "piano" });
    expect(none.result.text).toBe("No results for piano");
    refusedWith(call("search", { query: " " }), "no-query");
  });

  it("lists what Today shows, the carried-over one included", () => {
    const outcome = call("today", {});
    expect(outcome.ops).toEqual([]);
    expect(outcome.result.open).toEqual(["Laundry", "Gym", "Call dad"]);
    expect(outcome.result.text).toBe("3 to-dos today");
  });
});

describe("todo.set_setting", () => {
  it("changes one option to a value Make It Yours offers", () => {
    const value = written(call("set_setting", { preset: null, field: "tickSound", value: "off" })).get("settings:self") as Value;
    expect(value.tickSound).toBe("off");
    expect(value.preset).toBe("custom");
    const haptic = written(call("set_setting", { preset: null, field: "haptic", value: "off" })).get("settings:self") as Value;
    expect(haptic.haptic).toBe(false);
  });

  it("switches to a whole look, and Mine goes back to the founder's start", () => {
    const heat = written(call("set_setting", { preset: "heat", field: null, value: null })).get("settings:self") as Value;
    expect(heat).toMatchObject({ preset: "heat", look: "heat", accent: "#E5484D" });
    const mine = written(call("set_setting", { preset: "mine", field: null, value: null })).get("settings:self") as Value;
    expect(mine).toMatchObject({ preset: "mine", look: "notebook", add: "row", todayModel: "carry" });
  });

  it("refuses values not offered, an accent outside the eight, and no change", () => {
    refusedWith(call("set_setting", { preset: null, field: "look", value: "glass" }), "value-not-offered");
    refusedWith(call("set_setting", { preset: null, field: "accent", value: "#123456" }), "value-not-offered");
    refusedWith(call("set_setting", { preset: null, field: "look", value: "notebook" }), "nothing-to-change");
    refusedWith(call("set_setting", { preset: null, field: null, value: null }), "nothing-to-change");
  });

  it("works before first open, with no settings record", () => {
    const records = baseRecords().filter((record) => record.key !== "settings:self");
    const value = written(call("set_setting", { preset: null, field: "dayParts", value: "on" }, records)).get("settings:self") as Value;
    expect(value.dayParts).toBe(true);
    expect(value.look).toBe("notebook");
  });
});

describe("todo: context", () => {
  it("gives lists, today's, open, done today and trash titles, and the look", () => {
    const context = tools.context(baseRecords(), NOW);
    expect(context.lists).toEqual(["Inbox", "Groceries"]);
    expect(context.today).toEqual(["Laundry", "Gym", "Call dad"]);
    expect(context.open).toEqual(["Laundry", "Gym", "Call dad", "Eggs"]);
    expect(context.trash).toEqual(["Dentist"]);
    expect(context.look).toBe("Mine");
  });
});
