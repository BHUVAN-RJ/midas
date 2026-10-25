// The Water Sidekick's own logic (docs/briefs/hydration-sidekick.md, section 2.3): WaterLogic is
// taken out of sidekicks/hydration/index.html and run on its own, the way tools.js carries it.
// Amounts are stored in ml and shown in ml, L or oz; a day's goal stays on the day so a goal
// change never rewrites the streak; an unmet today does not break the streak until it is over;
// reminders run from the first hour to the last and skip the 45 minutes after a drink.
process.env.TZ = "America/Los_Angeles";

import { readFileSync } from "node:fs";
import vm from "node:vm";
import { describe, expect, it } from "vitest";

const html = readFileSync(new URL("../../sidekicks/hydration/index.html", import.meta.url), "utf8");

function waterLogicSource(pageHtml: string) {
  const start = pageHtml.indexOf("var WaterLogic = (function createWaterLogic() {");
  const end = pageHtml.indexOf("\n})();\n", start) + "\n})();\n".length;
  if (start === -1 || end <= start) {
    throw new Error("WaterLogic is not in index.html");
  }
  return pageHtml.slice(start, end);
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const Logic: any = vm.runInNewContext(waterLogicSource(html) + "\n;WaterLogic;", {});

type DayValue = { ml: number; goalMl?: number; entries?: Array<{ at: string; ml: number }>; $type?: string };

// Sunday Oct 25, 2026, 12:30 in Los Angeles (PDT, UTC-7)
const TODAY = "2026-10-25";
const NOON_THIRTY = Date.parse("2026-10-25T19:30:00.000Z");

function la(dateText: string, timeText: string) {
  return Logic.wallClockMs(dateText, timeText);
}

function daysBefore(count: number) {
  return Logic.addDaysToDate(TODAY, -count);
}

function met(ml: number, goalMl?: number): DayValue {
  return goalMl === undefined ? { ml } : { ml, goalMl };
}

describe("hydration: ml, L and oz", () => {
  it("turns an amount in any unit into whole ml", () => {
    expect(Logic.toMl(250, "ml")).toBe(250);
    expect(Logic.toMl(249.6, "ml")).toBe(250);
    expect(Logic.toMl(0.25, "l")).toBe(250);
    expect(Logic.toMl(1.25, "l")).toBe(1250);
    expect(Logic.toMl(2.5, "l")).toBe(2500);
    expect(Logic.toMl(0.3333, "l")).toBe(333);
    expect(Logic.toMl(8, "oz")).toBe(237);
    expect(Logic.toMl(16, "oz")).toBe(473);
    expect(Logic.toMl(24, "oz")).toBe(710);
    expect(Logic.toMl(1, "oz")).toBe(30);
  });

  it("shows ml grouped, litres to two decimals without trailing zeros, ounces whole", () => {
    expect(Logic.formatAmount(1250, "ml")).toBe("1,250 ml");
    expect(Logic.formatAmount(1250, "l")).toBe("1.25 L");
    expect(Logic.formatAmount(1250, "oz")).toBe("42 oz");
    expect(Logic.formatAmount(2500, "l")).toBe("2.5 L");
    expect(Logic.formatAmount(2000, "l")).toBe("2 L");
    expect(Logic.formatAmount(1255, "l")).toBe("1.26 L");
    expect(Logic.formatAmount(999.6, "ml")).toBe("1,000 ml");
    expect(Logic.formatAmount(12345, "ml")).toBe("12,345 ml");
    expect(Logic.formatAmount(0, "ml")).toBe("0 ml");
    expect(Logic.formatAmount(0, "l")).toBe("0 L");
    expect(Logic.formatAmount(0, "oz")).toBe("0 oz");
    expect(Logic.formatAmount(237, "oz")).toBe("8 oz");
  });

  it("gives back every whole ounce after a trip through ml", () => {
    for (let ounces = 1; ounces <= 200; ounces += 1) {
      expect(Logic.fromMl(Logic.toMl(ounces, "oz"), "oz"), String(ounces)).toBe(ounces);
    }
  });

  it("labels presets with a plus in the unit", () => {
    expect(Logic.presetLabel(250, "ml")).toBe("+250 ml");
    expect(Logic.presetLabel(250, "l")).toBe("+0.25 L");
    expect(Logic.presetLabel(473, "oz")).toBe("+16 oz");
  });

  it("swaps the default presets with the unit and keeps presets the person set", () => {
    expect(Logic.presetsForUnitChange([250, 500, 750], "ml", "oz")).toEqual([237, 473, 710]);
    expect(Logic.presetsForUnitChange([237, 473, 710], "oz", "l")).toEqual([250, 500, 750]);
    expect(Logic.presetsForUnitChange([250, 500, 750], "ml", "l")).toEqual([250, 500, 750]);
    expect(Logic.presetsForUnitChange([300, 500, 750], "ml", "oz")).toEqual([300, 500, 750]);
  });

  it("allows one drink from 1 ml to 3 L", () => {
    expect(Logic.isAmountAllowed(1)).toBe(true);
    expect(Logic.isAmountAllowed(3000)).toBe(true);
    expect(Logic.isAmountAllowed(0)).toBe(false);
    expect(Logic.isAmountAllowed(3001)).toBe(false);
    expect(Logic.isAmountAllowed(Number.NaN)).toBe(false);
  });
});

describe("hydration: the daily goal", () => {
  it("offers every 100 ml from 500 ml to 6 L, or every ounce from 20 to 200", () => {
    const millilitres = Logic.goalOptions("ml");
    expect(millilitres.length).toBe(56);
    expect(millilitres[0]).toEqual({ ml: 500, label: "500 ml" });
    expect(millilitres[55]).toEqual({ ml: 6000, label: "6,000 ml" });
    expect(Logic.goalOptions("l")[20]).toEqual({ ml: 2500, label: "2.5 L" });
    const ounces = Logic.goalOptions("oz");
    expect(ounces.length).toBe(181);
    expect(ounces[0]).toEqual({ ml: 591, label: "20 oz" });
    expect(ounces[180]).toEqual({ ml: 5915, label: "200 oz" });
  });

  it("puts a goal said in any unit on the wheel's steps, or refuses it", () => {
    expect(Logic.snapGoal(3, "l")).toBe(3000);
    expect(Logic.snapGoal(2.45, "l")).toBe(2500);
    expect(Logic.snapGoal(2550, "ml")).toBe(2600);
    expect(Logic.snapGoal(84, "oz")).toBe(2484);
    expect(Logic.snapGoal(84.4, "oz")).toBe(2484);
    expect(Logic.snapGoal(19, "oz")).toBeNull();
    expect(Logic.snapGoal(201, "oz")).toBeNull();
    expect(Logic.snapGoal(7, "l")).toBeNull();
    expect(Logic.snapGoal(0.4, "l")).toBeNull();
    expect(Logic.snapGoal(0, "ml")).toBeNull();
    expect(Logic.snapGoal("3", "l")).toBeNull();
  });

  it("selects the wheel option nearest the stored goal", () => {
    expect(Logic.nearestGoalOption(2500, "oz")).toBe(Logic.toMl(85, "oz"));
    expect(Logic.nearestGoalOption(2484, "l")).toBe(2500);
  });
});

describe("hydration: settings", () => {
  it("fills the founder's defaults: 2.5 L, reminders on 9:00 to 21:00 every 2 hours, 250/500/750 ml", () => {
    expect(Logic.settingsFrom(null)).toEqual({
      goalMl: 2500, unit: "ml", presetsMl: [250, 500, 750], remindStart: "09:00", remindEnd: "21:00", everyHours: 2, remindersOn: true,
    });
    expect(Logic.settingsFrom({ unit: "oz" }).presetsMl).toEqual([237, 473, 710]);
  });

  it("replaces anything out of range and keeps createdAt", () => {
    const settings = Logic.settingsFrom({
      goalMl: 90000, unit: "cup", presetsMl: [250, 0, 750], remindStart: "09:30", remindEnd: "21:00", everyHours: 5, remindersOn: false, createdAt: "2026-10-01T00:00:00.000Z",
    });
    expect(settings).toEqual({
      goalMl: 2500, unit: "ml", presetsMl: [250, 500, 750], remindStart: "09:00", remindEnd: "21:00", everyHours: 2, remindersOn: false, createdAt: "2026-10-01T00:00:00.000Z",
    });
  });

  it("puts back the default hours when the first is not before the last", () => {
    const settings = Logic.settingsFrom({ remindStart: "20:00", remindEnd: "08:00" });
    expect([settings.remindStart, settings.remindEnd]).toEqual(["09:00", "21:00"]);
  });

  it("writes the settings over the stored record, keeping its other fields", () => {
    const stored = { $type: "hydration.settings", goalMl: 2000, unit: "ml", note: "kept", createdAt: "2026-10-01T00:00:00.000Z" };
    const settings = Logic.settingsFrom({ ...stored, goalMl: 3000 });
    const record = Logic.settingsRecord(settings, stored, "2026-10-25T19:30:00.000Z");
    expect(record.goalMl).toBe(3000);
    expect(record.note).toBe("kept");
    expect(record.$type).toBe("hydration.settings");
    expect(record.createdAt).toBe("2026-10-01T00:00:00.000Z");
    expect(Logic.settingsRecord(Logic.settingsFrom(null), null, "2026-10-25T19:30:00.000Z").createdAt).toBe("2026-10-25T19:30:00.000Z");
  });
});

describe("hydration: days", () => {
  it("names a day by the phone's local date, not the UTC date", () => {
    // 23:30 on Oct 25 in Los Angeles is already Oct 26 in UTC
    expect(Logic.dayKey(Date.parse("2026-10-26T06:30:00.000Z"))).toBe("water:2026-10-25");
    expect(Logic.dayKey(Date.parse("2026-10-26T07:30:00.000Z"))).toBe("water:2026-10-26");
  });

  it("steps dates across months and years", () => {
    expect(Logic.addDaysToDate("2026-11-01", -1)).toBe("2026-10-31");
    expect(Logic.addDaysToDate("2026-12-31", 1)).toBe("2027-01-01");
    expect(Logic.addDaysToDate("2028-02-28", 1)).toBe("2028-02-29");
  });

  it("adds a drink: total up, an entry, and the day's goal kept on it", () => {
    const first = Logic.dayAfterLog(null, 250, "2026-10-25T16:00:00.000Z", 2500);
    expect(first).toEqual({ ml: 250, goalMl: 2500, entries: [{ at: "2026-10-25T16:00:00.000Z", ml: 250 }] });
    const second = Logic.dayAfterLog({ $type: "hydration.day", ...first, note: "kept" }, 500, "2026-10-25T17:00:00.000Z", 3000);
    expect(second.ml).toBe(750);
    expect(second.goalMl).toBe(3000);
    expect(second.entries.length).toBe(2);
    expect(second.$type).toBe("hydration.day");
    expect(second.note).toBe("kept");
  });

  it("counts widget taps (ml without entries) as From widget", () => {
    const widgetOnly = { ml: 500 };
    expect(Logic.widgetAmount(widgetOnly)).toBe(500);
    const afterLog = Logic.dayAfterLog(widgetOnly, 250, "2026-10-25T17:00:00.000Z", 2500);
    expect(afterLog.ml).toBe(750);
    expect(Logic.widgetAmount(afterLog)).toBe(500);
    expect(Logic.dayWithoutWidgetAmount(afterLog).ml).toBe(250);
    expect(Logic.widgetAmount(Logic.dayWithoutWidgetAmount(afterLog))).toBe(0);
  });

  it("removes one entry and its ml, never below zero", () => {
    const day = { ml: 750, goalMl: 2500, entries: [{ at: "2026-10-25T17:00:00.000Z", ml: 500 }, { at: "2026-10-25T16:00:00.000Z", ml: 250 }] };
    expect(Logic.latestEntryIndex(day)).toBe(0);
    expect(Logic.indexOfEntryAt(day, "2026-10-25T16:00:00.000Z")).toBe(1);
    expect(Logic.indexOfEntryAt(day, "2026-10-25T18:00:00.000Z")).toBe(-1);
    const removed = Logic.dayAfterRemove(day, 0);
    expect(removed).toEqual({ ml: 250, goalMl: 2500, entries: [{ at: "2026-10-25T16:00:00.000Z", ml: 250 }] });
    expect(Logic.dayAfterRemove({ ml: 100, entries: [{ at: "2026-10-25T16:00:00.000Z", ml: 250 }] }, 0).ml).toBe(0);
    expect(Logic.latestEntryIndex({ ml: 500 })).toBe(-1);
  });

  it("reads broken day records as empty", () => {
    expect(Logic.dayFrom(null)).toEqual({ ml: 0, entries: [] });
    expect(Logic.dayFrom({ ml: "lots", entries: [{ at: 5 }, { at: "2026-10-25T16:00:00.000Z", ml: 250 }] })).toEqual({ ml: 0, entries: [{ at: "2026-10-25T16:00:00.000Z", ml: 250 }] });
  });
});

describe("hydration: streaks", () => {
  function history(): Record<string, DayValue> {
    return {
      [daysBefore(4)]: met(2600, 2500),
      [daysBefore(3)]: met(2500, 2500),
      [daysBefore(2)]: met(2700, 2500),
      [daysBefore(1)]: met(2550, 2500),
    };
  }

  it("does not break on an unmet today", () => {
    const days = { ...history(), [TODAY]: met(1200, 2500) };
    expect(Logic.streakDays(days, TODAY, 2500)).toBe(4);
    expect(Logic.streakDays(history(), TODAY, 2500)).toBe(4);
  });

  it("counts today once met", () => {
    const days = { ...history(), [TODAY]: met(2500, 2500) };
    expect(Logic.streakDays(days, TODAY, 2500)).toBe(5);
  });

  it("breaks on a day with no record", () => {
    const days = { ...history(), [TODAY]: met(2600, 2500) };
    delete days[daysBefore(2)];
    expect(Logic.streakDays(days, TODAY, 2500)).toBe(2);
  });

  it("breaks on a day short of its goal", () => {
    const days = { ...history(), [daysBefore(1)]: met(2400, 2500) };
    expect(Logic.streakDays(days, TODAY, 2500)).toBe(0);
  });

  it("judges each day by its own goal after a goal change", () => {
    // Goal was 2 L until yesterday, 3 L from today: the 2.1 L days still count
    const days = {
      [daysBefore(3)]: met(2100, 2000),
      [daysBefore(2)]: met(2100, 2000),
      [daysBefore(1)]: met(2100, 2000),
      [TODAY]: met(2900, 3000),
    };
    expect(Logic.streakDays(days, TODAY, 3000)).toBe(3);
    days[TODAY] = met(3000, 3000);
    expect(Logic.streakDays(days, TODAY, 3000)).toBe(4);
  });

  it("judges a day made only by widget taps by the current goal", () => {
    const days = { [daysBefore(1)]: met(2600), [TODAY]: met(0) };
    expect(Logic.streakDays(days, TODAY, 2500)).toBe(1);
    expect(Logic.streakDays(days, TODAY, 3000)).toBe(0);
  });

  it("runs across a month boundary", () => {
    const days = { "2026-10-30": met(2500, 2500), "2026-10-31": met(2500, 2500), "2026-11-01": met(2500, 2500) };
    expect(Logic.streakDays(days, "2026-11-01", 2500)).toBe(3);
  });

  it("gives the week strip the last 7 days, today last, each as a share of its goal", () => {
    const days = { ...history(), [TODAY]: met(1250, 2500) };
    const week = Logic.weekDays(days, TODAY, 2500);
    const letters: string[] = [];
    for (const day of week) {
      letters.push(day.letter);
    }
    expect(letters.join("")).toBe("MTWTFSS");
    expect(week[0].date).toBe("2026-10-19");
    expect(week[0].fraction).toBe(0);
    expect(week[6]).toEqual({ date: TODAY, letter: "S", fraction: 0.5, met: false, today: true });
    expect(week[5].met).toBe(true);
  });

  it("reads day records out of the store's list", () => {
    const records = [
      { key: "settings:main", value: { goalMl: 2500 } },
      { key: "water:2026-10-24", value: { ml: 300 } },
      { key: "water:2026-10-25", value: { ml: 500 } },
    ];
    expect(Logic.daysByDateOf(records)).toEqual({ "2026-10-24": { ml: 300 }, "2026-10-25": { ml: 500 } });
  });
});

describe("hydration: reminders", () => {
  const defaults = Logic.settingsFrom(null);

  it("runs from the first hour to the last: 9:00 to 21:00 every 2 hours is 7 times", () => {
    expect(Logic.slotTimes(defaults)).toEqual(["09:00", "11:00", "13:00", "15:00", "17:00", "19:00", "21:00"]);
    expect(Logic.slotTimes({ ...defaults, remindStart: "08:00", remindEnd: "20:00", everyHours: 3 })).toEqual(["08:00", "11:00", "14:00", "17:00", "20:00"]);
    expect(Logic.slotTimes({ ...defaults, remindStart: "09:00", remindEnd: "22:00", everyHours: 4 })).toEqual(["09:00", "13:00", "17:00", "21:00"]);
  });

  it("says the next time, skipping the 45 minutes after a drink", () => {
    expect(Logic.nextReminder(defaults, null, NOON_THIRTY)).toEqual({ state: "next", at: la(TODAY, "13:00") });
    const justDrank = { ml: 250, goalMl: 2500, entries: [{ at: "2026-10-25T19:20:00.000Z", ml: 250 }] };
    expect(Logic.nextReminder(defaults, justDrank, NOON_THIRTY)).toEqual({ state: "next", at: la(TODAY, "15:00") });
    const drankEarlier = { ml: 250, goalMl: 2500, entries: [{ at: "2026-10-25T19:00:00.000Z", ml: 250 }] };
    expect(Logic.nextReminder(defaults, drankEarlier, NOON_THIRTY)).toEqual({ state: "next", at: la(TODAY, "13:00") });
  });

  it("is done for today once the goal is met, off when reminders are off", () => {
    expect(Logic.nextReminder(defaults, { ml: 2500, goalMl: 2500 }, NOON_THIRTY)).toEqual({ state: "done" });
    expect(Logic.nextReminder({ ...defaults, remindersOn: false }, null, NOON_THIRTY)).toEqual({ state: "off" });
  });

  it("gives tomorrow's first time after the last one", () => {
    const lateEvening = la(TODAY, "21:30");
    expect(Logic.nextReminder(defaults, null, lateEvening)).toEqual({ state: "next", at: la("2026-10-26", "09:00") });
  });

  it("writes reminder:water with endTime and listen exactly as the plan says (N1, N2)", () => {
    const record = Logic.reminderRecord(defaults, null, NOON_THIRTY, "America/Los_Angeles");
    expect(record).toEqual({
      at: "2026-10-25T16:00:00.000Z",
      title: "Drink Water",
      timeZone: "America/Los_Angeles",
      repeat: { every: "day" },
      everyHours: 2,
      endTime: "21:00",
      listen: { key: "water:{today}", field: "ml", goal: "settings:main.goalMl", dayGoalField: "goalMl", quietMinutes: 45 },
      done: false,
      createdAt: "2026-10-25T19:30:00.000Z",
    });
  });

  it("keeps what the engine wrote and moves at only when the first hour changes", () => {
    const stored = {
      $type: "hydration.reminder", at: "2026-10-01T16:00:00.000Z", title: "Drink Water", slotsDone: { "11:00": "2026-10-25T18:01:00.000Z" },
      createdAt: "2026-10-01T00:00:00.000Z",
    };
    const same = Logic.reminderRecord({ ...defaults, everyHours: 3 }, stored, NOON_THIRTY, "America/Los_Angeles");
    expect(same.at).toBe("2026-10-01T16:00:00.000Z");
    expect(same.slotsDone).toEqual({ "11:00": "2026-10-25T18:01:00.000Z" });
    expect(same.everyHours).toBe(3);
    expect(same.createdAt).toBe("2026-10-01T00:00:00.000Z");
    const moved = Logic.reminderRecord({ ...defaults, remindStart: "08:00" }, stored, NOON_THIRTY, "America/Los_Angeles");
    expect(moved.at).toBe("2026-10-25T15:00:00.000Z");
  });

  it("stops the reminder with done when reminders are off", () => {
    const record = Logic.reminderRecord({ ...defaults, remindersOn: false }, null, NOON_THIRTY, "America/Los_Angeles");
    expect(record.done).toBe(true);
    const back = Logic.reminderRecord(defaults, record, NOON_THIRTY, "America/Los_Angeles");
    expect(back.done).toBe(false);
  });
});
