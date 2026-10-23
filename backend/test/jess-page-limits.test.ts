// Tools accept only what the page offers (founder, 2026-10-21, docs/PRODUCT.md "jess router review"
// item 7): care-reminders repeats are the page's Repeat menu choices, its alerts the page's
// day range and "How Long" steps, and its undo the page's "Not Done" window (the day of the
// Done, while the row shows done); a Reminders repeat is every 1 to 99, as the page's Custom
// repeat offers. Anything else changes nothing.
process.env.TZ = "America/Los_Angeles";

import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import { outcomeFromToolCall, parseSidekick } from "../src/jess";
import type { JessContext, JessSidekick } from "../src/jess";
import { loadToolsScript } from "../scripts/sidekick-tools.mjs";

const LA = "America/Los_Angeles";
// Tuesday Oct 20, 2026, 10:00 in Los Angeles
const NOW = "2026-10-20T17:00:00.000Z";

type Records = Array<{ key: string; value: Record<string, unknown> }>;
type Outcome = {
  ops?: Array<{ op: string; key: string; value?: Record<string, unknown> }>;
  refused?: string;
  result: { text: string };
};
type Handlers = Record<string, (input: Record<string, unknown>, records: Records, now: string) => Outcome>;

function sidekickFile(sidekickId: string, fileName: string): string {
  return readFileSync(new URL(`../../sidekicks/${sidekickId}/${fileName}`, import.meta.url), "utf8");
}

function handlersOf(sidekickId: string): Handlers {
  const loaded = loadToolsScript(sidekickFile(sidekickId, "tools.js"));
  if (!("tools" in loaded)) {
    throw new Error(loaded.problem);
  }
  return loaded.tools.handlers as Handlers;
}

const careHandlers = handlersOf("care-reminders");
const remindersHandlers = handlersOf("reminders");
const careManifest = JSON.parse(sidekickFile("care-reminders", "manifest.json"));
const remindersManifest = JSON.parse(sidekickFile("reminders", "manifest.json"));

function careRecords(): Records {
  return [
    { key: "list:medicine", value: { $type: "care.list", name: "Medicine", icon: "pill", color: "butter", alerts: [], order: 1, createdAt: "2026-10-01T00:00:00.000Z" } },
    { key: "reminder:ipills001", value: { $type: "care.item", title: "Pills", list: "medicine", at: "2026-10-01T16:00:00.000Z", timeZone: LA, done: false, repeat: { every: "day" }, createdAt: "2026-10-01T00:00:00.000Z" } },
  ];
}

function withRecord(records: Records, key: string, value: Record<string, unknown>): Records {
  return [...records, { key, value: { $type: "care.item", list: "medicine", timeZone: LA, createdAt: "2026-10-01T00:00:00.000Z", ...value } }];
}

function when(fields: Record<string, unknown>) {
  return { date: null, time: null, allDay: false, at: null, repeat: null, timeZone: LA, ...fields };
}

// Friday Oct 23, 2026 at 09:00 in Los Angeles
function fridayAt9(repeat: unknown) {
  return when({ date: "2026-10-23", time: "09:00", at: "2026-10-23T16:00:00.000Z", repeat });
}

function careAdd(repeat: unknown, everyHours: number | null = null): Outcome {
  const input = { title: "Vitamins", list: "Medicine", when: fridayAt9(repeat), everyHours };
  return careHandlers.add(input, careRecords(), NOW);
}

function storedRepeat(outcome: Outcome): unknown {
  expect(outcome.refused).toBeUndefined();
  const value = outcome.ops?.[0].value as Record<string, unknown>;
  const stamped = MidasRecordSchema.stampType(careManifest.types, outcome.ops?.[0].key, value);
  expect(MidasRecordSchema.checkRecord(careManifest.types, outcome.ops?.[0].key, stamped)).toBeNull();
  return value.repeat ?? null;
}

describe("care-reminders repeats are the page's Repeat menu", () => {
  it("adds every choice the menu offers", () => {
    expect(storedRepeat(careAdd(null))).toBeNull();
    expect(storedRepeat(careAdd({ every: "day", interval: 1, weekdays: [] }))).toEqual({ every: "day" });
    expect(storedRepeat(careAdd({ every: "week", interval: 1, weekdays: [1, 2, 3, 4, 5] }))).toEqual({ every: "week", weekdays: [1, 2, 3, 4, 5] });
    expect(storedRepeat(careAdd({ every: "week", interval: 1, weekdays: [0, 6] }))).toEqual({ every: "week", weekdays: [0, 6] });
    expect(storedRepeat(careAdd({ every: "week", interval: 1, weekdays: [] }))).toEqual({ every: "week" });
    expect(storedRepeat(careAdd({ every: "week", interval: 2, weekdays: [] }))).toEqual({ every: "week", interval: 2 });
    expect(storedRepeat(careAdd({ every: "month", interval: 1, weekdays: [] }))).toEqual({ every: "month" });
    expect(storedRepeat(careAdd({ every: "year", interval: 1, weekdays: [] }))).toEqual({ every: "year" });
    const hourly = careAdd(null, 3);
    expect(hourly.refused).toBeUndefined();
    expect(hourly.ops?.[0].value?.everyHours).toBe(3);
  });

  it("takes 'every Friday' said for a Friday as the page's Every Week", () => {
    expect(storedRepeat(careAdd({ every: "week", interval: 1, weekdays: [5] }))).toEqual({ every: "week" });
    expect(storedRepeat(careAdd({ every: "week", interval: 2, weekdays: [5] }))).toEqual({ every: "week", interval: 2 });
  });

  it("refuses a repeat the menu does not have, and changes nothing", () => {
    const notOffered = [
      { every: "week", interval: 3, weekdays: [] },
      { every: "week", interval: 1, weekdays: [1, 4] },
      { every: "week", interval: 1, weekdays: [2] },
      { every: "day", interval: 2, weekdays: [] },
      { every: "month", interval: 2, weekdays: [] },
      { every: "day", interval: 1, weekdays: [], until: "2026-12-01" },
    ];
    for (const repeat of notOffered) {
      const outcome = careAdd(repeat);
      expect(outcome.refused, JSON.stringify(repeat)).toBe("repeat-not-offered");
      expect(outcome.ops).toBeUndefined();
    }
  });

  it("refuses an edit to such a repeat, but leaves a stored one alone when only the title changes", () => {
    const records = withRecord(careRecords(), "reminder:icustom01", { title: "Shots", at: "2026-10-23T16:00:00.000Z", done: false, repeat: { every: "week", interval: 3 } });
    const toCustom = careHandlers.edit({ item: "Pills", title: null, when: fridayAt9({ every: "day", interval: 3, weekdays: [] }), everyHours: null }, records, NOW);
    expect(toCustom.refused).toBe("repeat-not-offered");
    const toWeekly = careHandlers.edit({ item: "Pills", title: null, when: fridayAt9({ every: "week", interval: 1, weekdays: [5] }), everyHours: null }, records, NOW);
    expect(toWeekly.refused).toBeUndefined();
    expect(toWeekly.ops?.[0].value?.repeat).toEqual({ every: "week" });
    const renamed = careHandlers.edit({ item: "Shots", title: "Allergy shots", when: null, everyHours: null }, records, NOW);
    expect(renamed.refused).toBeUndefined();
    expect(renamed.ops?.[0].value?.repeat).toEqual({ every: "week", interval: 3 });
  });
});

describe("care-reminders alerts are the page's choices", () => {
  const pageSteps = /const BEFORE_STEPS = \[([0-9, ]+)\];/.exec(sidekickFile("care-reminders", "index.html"));

  function addAlert(fields: Record<string, unknown>): Outcome {
    const input = { list: "Medicine", kind: "before", days: null, minutes: null, time: null, ...fields };
    return careHandlers.add_list_alert(input, careRecords(), NOW);
  }

  it("lists the page's own steps and day range in the tool's schema", () => {
    expect(pageSteps).not.toBeNull();
    const steps: Array<number | null> = [];
    for (const step of String(pageSteps?.[1]).split(",")) {
      steps.push(Number(step.trim()));
    }
    steps.push(null);
    let addAlertTool = null;
    for (const tool of careManifest.agent.tools) {
      if (tool.name === "care-reminders.add_list_alert") {
        addAlertTool = tool;
      }
    }
    expect(addAlertTool.inputSchema.properties.minutes.enum).toEqual(steps);
    expect(addAlertTool.inputSchema.properties.days.enum).toEqual([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, null]);
  });

  it("adds a step and a day count the page offers, and refuses others", () => {
    expect(addAlert({ minutes: 30 }).refused).toBeUndefined();
    expect(addAlert({ minutes: 720 }).refused).toBeUndefined();
    expect(addAlert({ minutes: 20 }).refused).toBe("alert-not-offered");
    expect(addAlert({ minutes: 150 }).refused).toBe("alert-not-offered");
    expect(addAlert({ kind: "daysBefore", days: 14, time: "18:00" }).refused).toBeUndefined();
    expect(addAlert({ kind: "daysBefore", days: 15, time: "18:00" }).refused).toBe("alert-not-offered");
    expect(addAlert({ kind: "daysBefore", days: 0, time: "18:00" }).refused).toBe("alert-not-offered");
  });

  it("is not done on the server when the model asks for a step the page lacks", () => {
    const sidekick = parseSidekick({ id: "care-reminders", name: "Care", version: "c2", agent: careManifest.agent, context: {} }) as JessSidekick;
    const context: JessContext = { transcript: "add a 20 minute alert to medicine", now: NOW, timeZone: LA, sidekicks: [sidekick] };
    const twenty = { name: "care-reminders__add_list_alert", argumentsText: JSON.stringify({ list: "Medicine", kind: "before", days: null, minutes: 20, time: null }) };
    expect(outcomeFromToolCall(twenty, context)).toMatchObject({ status: "not-done", reason: "bad-arguments" });
    const thirty = { name: "care-reminders__add_list_alert", argumentsText: JSON.stringify({ list: "Medicine", kind: "before", days: null, minutes: 30, time: null }) };
    expect(outcomeFromToolCall(thirty, context)).toMatchObject({ status: "done", tool: "care-reminders.add_list_alert" });
  });
});

describe("care-reminders undo is the page's Not Done", () => {
  function undo(records: Records, item: string): Outcome {
    return careHandlers.uncomplete({ item }, records, NOW);
  }

  it("undoes a one-time reminder done today", () => {
    const records = withRecord(careRecords(), "reminder:ilab00001", { title: "Lab test", at: "2026-10-20T15:00:00.000Z", done: true, completedAt: "2026-10-20T16:00:00.000Z" });
    const outcome = undo(records, "Lab test");
    expect(outcome.refused).toBeUndefined();
    expect(outcome.ops?.[0].value?.done).toBe(false);
  });

  it("refuses a one-time reminder done on an earlier day, which the page no longer shows", () => {
    const records = withRecord(careRecords(), "reminder:ieyes0001", { title: "Eye exam", at: "2026-10-19T17:00:00.000Z", done: true, completedAt: "2026-10-19T18:00:00.000Z" });
    expect(undo(records, "Eye exam").refused).toBe("not-done");
  });

  it("undoes a daily dose done today, but not an hourly one now showing its next time", () => {
    const daily = careRecords();
    daily[1].value.doneThrough = "2026-10-20T16:00:00.000Z";
    daily[1].value.lastDoneAt = "2026-10-20T16:05:00.000Z";
    expect(undo(daily, "Pills").refused).toBeUndefined();

    // Every 2 hours from 08:00: 08:00 done, the row shows 12:00 next, with no Not Done button
    const hourly = withRecord(careRecords(), "reminder:iwater001", { title: "Drink water", at: "2026-10-01T15:00:00.000Z", done: false, repeat: { every: "day" }, everyHours: 2, doneThrough: "2026-10-20T15:00:00.000Z", lastDoneAt: "2026-10-20T15:05:00.000Z" });
    expect(undo(hourly, "Drink water").refused).toBe("not-done");
  });
});

describe("a Reminders repeat is every 1 to 99, as the page's Custom repeat", () => {
  const records: Records = [
    { key: "reminder:a1", value: { $type: "reminders.item", title: "Water the plants", at: "2026-10-21T16:00:00.000Z", timeZone: LA, createdAt: "2026-10-01T00:00:00.000Z" } },
  ];

  function tomorrowAt9(interval: number) {
    return when({ date: "2026-10-21", time: "09:00", at: "2026-10-21T16:00:00.000Z", repeat: { every: "week", interval, weekdays: [] } });
  }

  it("adds and edits up to every 99, and refuses more", () => {
    const add99 = remindersHandlers.add({ title: "Pay rent", notes: null, list: null, when: tomorrowAt9(99) }, records, NOW);
    expect(add99.refused).toBeUndefined();
    expect(add99.ops?.[0].value?.repeat).toEqual({ every: "week", interval: 99 });
    expect(remindersHandlers.add({ title: "Pay rent", notes: null, list: null, when: tomorrowAt9(100) }, records, NOW).refused).toBe("repeat-not-offered");
    expect(remindersHandlers.edit({ item: "Water the plants", title: null, notes: null, when: tomorrowAt9(150), clearDate: null }, records, NOW).refused).toBe("repeat-not-offered");
    expect(remindersHandlers.edit({ item: "Water the plants", title: null, notes: null, when: tomorrowAt9(2), clearDate: null }, records, NOW).refused).toBeUndefined();
  });

  it("the page's Every menu stops at 99", () => {
    expect(sidekickFile("reminders", "index.html")).toContain("for (let count = 1; count <= 99; count += 1) {");
    expect(remindersManifest.agent.tools[0].name).toBe("reminders.add");
  });
});
