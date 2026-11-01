// The Water Sidekick's record types and tools (docs/briefs/hydration-sidekick.md, section 2.3;
// jess router, founder 2026-10-21: every action a person can take in the page is a tool).
// sidekicks/hydration/tools.js is loaded the way the deploy gate and the phone load it; every tool
// is called on real-shaped records and every record it would write is checked against
// manifest.json, as the shell's write gate checks it.
process.env.TZ = "America/Los_Angeles";

import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import { checkBundleFiles, typesBlockProblems } from "../scripts/bundle-tools.mjs";
import { copiedBlocks, loadToolsScript, sidekickToolsProblems } from "../scripts/sidekick-tools.mjs";

const folder = new URL("../../sidekicks/hydration/", import.meta.url);
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
// Sunday Oct 25, 2026, 12:30 in Los Angeles
const NOW = "2026-10-25T19:30:00.000Z";
// Sunday Oct 25, 2026, 23:30 in Los Angeles: already Monday in UTC
const LATE = "2026-10-26T06:30:00.000Z";

type Value = Record<string, unknown>;
type Records = Array<{ key: string; value: Value }>;
type Op = { op: string; key: string; value?: Value };
type Outcome = { ops?: Op[]; refused?: string; result: { text: string; [field: string]: unknown } };

function settingsValue(fields: Value = {}): Value {
  return {
    $type: "hydration.settings", goalMl: 2500, unit: "ml", presetsMl: [250, 500, 750], remindStart: "09:00", remindEnd: "21:00",
    everyHours: 2, remindersOn: true, createdAt: "2026-10-01T00:00:00.000Z", ...fields,
  };
}

function reminderValue(fields: Value = {}): Value {
  return {
    $type: "hydration.reminder", at: "2026-10-01T16:00:00.000Z", title: "Drink Water", timeZone: LA, repeat: { every: "day" }, everyHours: 2,
    endTime: "21:00", listen: { key: "water:{today}", field: "ml", goal: "settings:main.goalMl", dayGoalField: "goalMl", quietMinutes: 45 },
    done: false, createdAt: "2026-10-01T00:00:00.000Z", slotsDone: { "11:00": "2026-10-25T18:02:00.000Z" }, ...fields,
  };
}

function baseRecords(settingsFields: Value = {}): Records {
  return [
    { key: "reminder:water", value: reminderValue() },
    { key: "settings:main", value: settingsValue(settingsFields) },
    { key: "water:2026-10-22", value: { $type: "hydration.day", ml: 2600, goalMl: 2500, entries: [] } },
    { key: "water:2026-10-23", value: { $type: "hydration.day", ml: 2500, goalMl: 2500 } },
    { key: "water:2026-10-24", value: { $type: "hydration.day", ml: 2700 } },
    {
      key: "water:2026-10-25",
      value: {
        $type: "hydration.day", ml: 1500, goalMl: 2500,
        entries: [{ at: "2026-10-25T16:10:00.000Z", ml: 500 }, { at: "2026-10-25T18:40:00.000Z", ml: 250 }, { at: "2026-10-25T17:30:00.000Z", ml: 500 }],
      },
    },
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

function call(verb: string, input: Value, records: Records = baseRecords(), now: string = NOW): Outcome {
  const outcome = tools.handlers[verb](input, deepFreeze(records), now);
  return JSON.parse(JSON.stringify(outcome));
}

function writtenValue(outcome: Outcome, key: string): Value | undefined {
  for (const op of outcome.ops || []) {
    if (op.key === key) {
      return op.value;
    }
  }
  return undefined;
}

function opKeys(outcome: Outcome) {
  const keys: string[] = [];
  for (const op of outcome.ops || []) {
    keys.push(op.op + " " + op.key);
  }
  return keys;
}

function schemaProblem(key: string, value: Value) {
  const stamped = MidasRecordSchema.stampType(manifest.types, key, value);
  return MidasRecordSchema.checkRecord(manifest.types, key, stamped);
}

function expectSchemaValid(outcome: Outcome) {
  expect(outcome.refused).toBeUndefined();
  expect(Array.isArray(outcome.ops)).toBe(true);
  for (const op of outcome.ops || []) {
    expect(op.op).toBe("set");
    expect(schemaProblem(op.key, op.value as Value), op.key).toBeNull();
  }
}

function expectRefused(outcome: Outcome, reason: string) {
  expect(outcome.refused).toBe(reason);
  expect(outcome.ops).toBeUndefined();
  expect(typeof outcome.result.text).toBe("string");
  expect(outcome.result.text.length).toBeGreaterThan(0);
}

function withoutKey(records: Records, key: string): Records {
  const kept: Records = [];
  for (const record of records) {
    if (record.key !== key) {
      kept.push(record);
    }
  }
  return kept;
}

function pageWaterLogic() {
  const start = html.indexOf("var WaterLogic = (function createWaterLogic() {");
  const end = html.indexOf("\n})();\n", start) + "\n})();\n".length;
  return html.slice(start, end);
}

describe("hydration: the files agree", () => {
  it("passes the whole deploy gate (page, manifest, tools)", () => {
    expect(checkBundleFiles(html, manifestText, "hydration", toolsText).problems).toEqual([]);
    expect(sidekickToolsProblems(manifest, toolsText, html, "hydration")).toEqual([]);
  });

  it("is Water, drop.fill on Turquoise", () => {
    expect(manifest.id).toBe("hydration");
    expect(manifest.name).toBe("Water");
    expect(manifest.icon).toEqual({ symbol: "drop.fill", background: "#30D5C8", backgroundDark: "#1E8C84" });
  });

  it("has exactly the seven tools the plan names, one handler each", () => {
    const verbs: string[] = [];
    for (const tool of manifest.agent.tools) {
      verbs.push(tool.name.slice("hydration.".length));
    }
    verbs.sort();
    expect(verbs).toEqual(["log", "remove", "set_goal", "set_reminders", "set_unit", "today", "undo"]);
    const handlerNames = Object.keys(tools.handlers);
    handlerNames.sort();
    expect(handlerNames).toEqual(verbs);
  });

  it("carries the page's WaterLogic character for character", () => {
    const blocks = copiedBlocks(toolsText);
    expect(blocks.length).toBe(1);
    expect(blocks[0].text).toBe(pageWaterLogic());
  });

  it("would be refused if the page's logic changed without tools.js", () => {
    const changedPage = html.replace("const QUIET_MINUTES = 45;", "const QUIET_MINUTES = 30;");
    expect(changedPage).not.toBe(html);
    const problems = sidekickToolsProblems(manifest, toolsText, changedPage, "hydration");
    expect(problems.length).toBe(1);
    expect(problems[0]).toContain("no longer matches index.html");
  });

  it("pastes shell/sdk/midas-store.js unchanged, in one inline script, with nothing loaded from outside", () => {
    const storeHelper = readFileSync(new URL("../../shell/sdk/midas-store.js", import.meta.url), "utf8");
    expect(html.includes(storeHelper)).toBe(true);
    expect(html.split("<script>").length - 1).toBe(1);
    expect(html).not.toMatch(/<script\s|<link\s|https?:\/\/(?!www\.w3\.org\/2000\/svg)/);
    expect(html).not.toMatch(/localStorage|sessionStorage|indexedDB/);
  });

  it("has no purple in its colours, light or night", () => {
    const hexColours = html.match(/#[0-9A-Fa-f]{6}\b/g) || [];
    expect(hexColours.length).toBeGreaterThan(10);
    for (const hex of hexColours) {
      const red = parseInt(hex.slice(1, 3), 16);
      const green = parseInt(hex.slice(3, 5), 16);
      const blue = parseInt(hex.slice(5, 7), 16);
      // Purple: red and blue both well above green
      expect(red > green + 24 && blue > green + 24, hex).toBe(false);
    }
  });
});

describe("hydration: record types", () => {
  it("declares water:, settings: and reminder: in its namespace", () => {
    expect(typesBlockProblems(manifest.types, "hydration")).toEqual([]);
    expect(manifest.types["water:"].$type).toBe("hydration.day");
    expect(manifest.types["settings:"].$type).toBe("hydration.settings");
    expect(manifest.types["reminder:"].$type).toBe("hydration.reminder");
  });

  it("needs only ml on a day, so the first widget tap of a day passes", () => {
    expect(manifest.types["water:"].schema.required).toEqual(["ml"]);
    expect(schemaProblem("water:2026-10-25", { ml: 250 })).toBeNull();
    expect(schemaProblem("water:2026-10-25", { goalMl: 2500 })).toBe("hydration.day.ml is required");
    expect(schemaProblem("water:2026-10-25", { ml: -5 })).not.toBeNull();
    expect(schemaProblem("water:2026-10-25", { ml: 250, entries: [{ at: "2026-10-25T16:00:00.000Z", ml: 0 }] })).not.toBeNull();
    expect(schemaProblem("water:2026-10-25", { ml: 250, entries: [{ at: "yesterday", ml: 250 }] })).not.toBeNull();
  });

  it("checks settings: goal range, unit, three presets, whole hours, 2/3/4 hours", () => {
    expect(schemaProblem("settings:main", settingsValue())).toBeNull();
    expect(schemaProblem("settings:main", settingsValue({ unit: "cup" }))).not.toBeNull();
    expect(schemaProblem("settings:main", settingsValue({ goalMl: 100 }))).not.toBeNull();
    expect(schemaProblem("settings:main", settingsValue({ presetsMl: [250, 500] }))).not.toBeNull();
    expect(schemaProblem("settings:main", settingsValue({ everyHours: 5 }))).not.toBeNull();
    expect(schemaProblem("settings:main", settingsValue({ remindStart: "9am" }))).not.toBeNull();
  });

  it("keeps the engine's fields, endTime and listen on the reminder, and leaves room for more", () => {
    expect(schemaProblem("reminder:water", reminderValue())).toBeNull();
    expect(schemaProblem("reminder:water", reminderValue({ snoozes: { "@1300": "2026-10-25T20:10:00.000Z" }, lastDoneAt: NOW, doneThrough: NOW }))).toBeNull();
    expect(schemaProblem("reminder:water", reminderValue({ reminderType: "notification" }))).toBeNull();
    expect(schemaProblem("reminder:water", reminderValue({ endTime: "9pm" }))).not.toBeNull();
    expect(schemaProblem("reminder:water", reminderValue({ listen: { field: "ml" } }))).not.toBeNull();
    expect(schemaProblem("reminder:water", reminderValue({ title: "" }))).not.toBeNull();
  });
});

describe("hydration.log", () => {
  it("adds the amount said, in the unit said, to today with an entry", () => {
    const outcome = call("log", { amount: 0.5, unit: "l" });
    expectSchemaValid(outcome);
    expect(opKeys(outcome)).toEqual(["set water:2026-10-25"]);
    const day = writtenValue(outcome, "water:2026-10-25") as Value;
    expect(day.ml).toBe(2000);
    expect(day.goalMl).toBe(2500);
    expect((day.entries as unknown[]).length).toBe(4);
    expect((day.entries as Value[])[3]).toEqual({ at: NOW, ml: 500 });
    expect(day.$type).toBe("hydration.day");
    expect(outcome.result.text).toBe("Added 500 ml");
  });

  it("reads an amount without a unit in the person's unit, and a glass as the first preset", () => {
    const ounces = baseRecords({ unit: "oz", presetsMl: [237, 473, 710] });
    const sixteen = call("log", { amount: 16, unit: null }, ounces);
    expect((writtenValue(sixteen, "water:2026-10-25") as Value).ml).toBe(1500 + 473);
    expect(sixteen.result.text).toBe("Added 16 oz");
    const glass = call("log", { amount: null, unit: null }, ounces);
    expect((writtenValue(glass, "water:2026-10-25") as Value).ml).toBe(1500 + 237);
    expect(glass.result.text).toBe("Added 8 oz");
  });

  it("starts a new day, and lands late-night drinks on the local date", () => {
    const outcome = call("log", { amount: 250, unit: "ml" }, baseRecords(), LATE);
    expectSchemaValid(outcome);
    expect(opKeys(outcome)).toEqual(["set water:2026-10-25"]);
    const tomorrow = call("log", { amount: 250, unit: "ml" }, baseRecords(), "2026-10-26T16:00:00.000Z");
    expect(writtenValue(tomorrow, "water:2026-10-26")).toEqual({ ml: 250, goalMl: 2500, entries: [{ at: "2026-10-26T16:00:00.000Z", ml: 250 }] });
  });

  it("adds to a day the widget started, keeping the widget's ml", () => {
    const records = withoutKey(baseRecords(), "water:2026-10-25");
    records.push({ key: "water:2026-10-25", value: { $type: "hydration.day", ml: 500 } });
    const outcome = call("log", { amount: 250, unit: "ml" }, records);
    expectSchemaValid(outcome);
    expect(writtenValue(outcome, "water:2026-10-25")).toEqual({ $type: "hydration.day", ml: 750, goalMl: 2500, entries: [{ at: NOW, ml: 250 }] });
  });

  it("refuses amounts the page does not take", () => {
    expectRefused(call("log", { amount: 0, unit: "ml" }), "amount-not-offered");
    expectRefused(call("log", { amount: -1, unit: "ml" }), "amount-not-offered");
    expectRefused(call("log", { amount: 5, unit: "l" }), "amount-not-offered");
    expectRefused(call("log", { amount: 200, unit: "oz" }), "amount-not-offered");
  });
});

describe("hydration.undo", () => {
  it("takes back the latest drink logged today, by time", () => {
    const outcome = call("undo", {});
    expectSchemaValid(outcome);
    const day = writtenValue(outcome, "water:2026-10-25") as Value;
    expect(day.ml).toBe(1250);
    expect(day.entries).toEqual([{ at: "2026-10-25T16:10:00.000Z", ml: 500 }, { at: "2026-10-25T17:30:00.000Z", ml: 500 }]);
    expect(outcome.result.text).toBe("Removed 250 ml");
  });

  it("takes back what log just added", () => {
    const logged = call("log", { amount: 750, unit: "ml" });
    const records = withoutKey(baseRecords(), "water:2026-10-25");
    records.push({ key: "water:2026-10-25", value: writtenValue(logged, "water:2026-10-25") as Value });
    const undone = call("undo", {}, records);
    expect(writtenValue(undone, "water:2026-10-25")).toEqual(baseRecords()[5].value);
  });

  it("refuses with nothing logged today, and leaves widget taps alone", () => {
    expectRefused(call("undo", {}, withoutKey(baseRecords(), "water:2026-10-25")), "nothing-to-undo");
    const widgetOnly = withoutKey(baseRecords(), "water:2026-10-25");
    widgetOnly.push({ key: "water:2026-10-25", value: { $type: "hydration.day", ml: 500 } });
    expectRefused(call("undo", {}, widgetOnly), "nothing-to-undo");
  });
});

describe("hydration.today", () => {
  it("says today's total against the goal, with the streak, and changes nothing", () => {
    const outcome = call("today", {});
    expect(outcome.ops).toEqual([]);
    expect(outcome.result.text).toBe("1,500 ml of 2,500 ml, 3 day streak");
    expect(outcome.result.totalMl).toBe(1500);
    expect(outcome.result.streak).toBe(3);
    const litres = call("today", {}, baseRecords({ unit: "l" }));
    expect(litres.result.text).toBe("1.5 L of 2.5 L, 3 day streak");
  });

  it("works before first open, with the defaults", () => {
    const outcome = call("today", {}, []);
    expect(outcome.result.text).toBe("0 ml of 2,500 ml");
  });
});

describe("hydration.set_goal", () => {
  it("changes the goal in ml and keeps the reminder in step", () => {
    const outcome = call("set_goal", { amount: 3, unit: "l" });
    expectSchemaValid(outcome);
    expect(opKeys(outcome)).toEqual(["set settings:main"]);
    expect((writtenValue(outcome, "settings:main") as Value).goalMl).toBe(3000);
    expect((writtenValue(outcome, "settings:main") as Value).createdAt).toBe("2026-10-01T00:00:00.000Z");
    expect(outcome.result.text).toBe("Changed goal to 3,000 ml");
  });

  it("refuses goals off the wheel and the goal already set", () => {
    expectRefused(call("set_goal", { amount: 10, unit: "l" }), "goal-not-offered");
    expectRefused(call("set_goal", { amount: 10, unit: "oz" }), "goal-not-offered");
    expectRefused(call("set_goal", { amount: 2.5, unit: "l" }), "nothing-to-change");
  });

  it("before first open, writes the settings with the defaults and the reminder", () => {
    const outcome = call("set_goal", { amount: 96, unit: "oz" }, []);
    expectSchemaValid(outcome);
    expect(opKeys(outcome)).toEqual(["set settings:main", "set reminder:water"]);
    expect((writtenValue(outcome, "settings:main") as Value).goalMl).toBe(2839);
    expect((writtenValue(outcome, "reminder:water") as Value).listen).toEqual({
      key: "water:{today}", field: "ml", goal: "settings:main.goalMl", dayGoalField: "goalMl", quietMinutes: 45,
    });
  });
});

describe("hydration.set_unit", () => {
  it("changes the unit and swaps default presets", () => {
    const outcome = call("set_unit", { unit: "oz" });
    expectSchemaValid(outcome);
    const settings = writtenValue(outcome, "settings:main") as Value;
    expect(settings.unit).toBe("oz");
    expect(settings.presetsMl).toEqual([237, 473, 710]);
    expect(settings.goalMl).toBe(2500);
    expect(outcome.result.text).toBe("Changed unit to oz");
  });

  it("keeps presets the person set", () => {
    const outcome = call("set_unit", { unit: "l" }, baseRecords({ presetsMl: [330, 500, 1000] }));
    expect((writtenValue(outcome, "settings:main") as Value).presetsMl).toEqual([330, 500, 1000]);
  });

  it("refuses the unit already set and units it does not know", () => {
    expectRefused(call("set_unit", { unit: "ml" }), "nothing-to-change");
    expectRefused(call("set_unit", { unit: "cups" }), "unit-not-offered");
  });
});

describe("hydration.set_reminders", () => {
  it("turns them off with done on the reminder, keeping what the engine wrote", () => {
    const outcome = call("set_reminders", { on: false, from: null, to: null, everyHours: null });
    expectSchemaValid(outcome);
    expect((writtenValue(outcome, "settings:main") as Value).remindersOn).toBe(false);
    const reminder = writtenValue(outcome, "reminder:water") as Value;
    expect(reminder.done).toBe(true);
    expect(reminder.slotsDone).toEqual({ "11:00": "2026-10-25T18:02:00.000Z" });
    expect(reminder.at).toBe("2026-10-01T16:00:00.000Z");
    expect(outcome.result.text).toBe("Reminders off");
  });

  it("changes the window and the interval, with endTime on the reminder", () => {
    const outcome = call("set_reminders", { on: null, from: "08:00", to: "20:00", everyHours: 3 });
    expectSchemaValid(outcome);
    const settings = writtenValue(outcome, "settings:main") as Value;
    expect([settings.remindStart, settings.remindEnd, settings.everyHours]).toEqual(["08:00", "20:00", 3]);
    const reminder = writtenValue(outcome, "reminder:water") as Value;
    expect(reminder.endTime).toBe("20:00");
    expect(reminder.everyHours).toBe(3);
    expect(reminder.at).toBe("2026-10-25T15:00:00.000Z");
    expect(reminder.done).toBe(false);
    expect(outcome.result.text).toMatch(/^Reminders 8:00\sAM to 8:00\sPM, every 3 hours$/i);
  });

  it("refuses times off the hour, a window that ends first, other intervals and no change", () => {
    expectRefused(call("set_reminders", { on: null, from: "08:30", to: null, everyHours: null }), "time-not-offered");
    expectRefused(call("set_reminders", { on: null, from: null, to: "nine", everyHours: null }), "time-not-offered");
    expectRefused(call("set_reminders", { on: null, from: "22:00", to: null, everyHours: null }), "bad-window");
    expectRefused(call("set_reminders", { on: null, from: null, to: null, everyHours: 5 }), "interval-not-offered");
    expectRefused(call("set_reminders", { on: true, from: "09:00", to: null, everyHours: 2 }), "nothing-to-change");
  });
});

describe("hydration: what jess is told", () => {
  it("gives the unit, goal, today, streak, presets and reminders", () => {
    const context = JSON.parse(JSON.stringify(tools.context(baseRecords({ unit: "l" }), NOW)));
    expect(context.unit).toBe("L");
    expect(context.goal).toBe("2.5 L");
    expect(context.today).toBe("1.5 L");
    expect(context.streakDays).toBe(3);
    expect(context.presets).toEqual(["0.25 L", "0.5 L", "0.75 L"]);
    expect(context.reminders).toMatch(/^Reminders 9:00\sAM to 9:00\sPM, every 2 hours$/i);
  });
});
