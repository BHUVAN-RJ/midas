// Circle colours in the reminders Sidekick (founder, 2026-10-11). A reminder in a list takes its
// list's colour. With no list: blue when due today, the Scheduled colour (orange, no longer red,
// which now means only Past Due) when dated another day, grey when undated. All is no longer grey.
import { readFileSync } from "node:fs";
import vm from "node:vm";
import { describe, expect, it } from "vitest";

const bundleHtml = readFileSync(new URL("../../sidekicks/reminder-test/index.html", import.meta.url), "utf8");

function loadRemindersLogic() {
  const scriptMatch = bundleHtml.match(/<script>([\s\S]*?)<\/script>/);
  if (!scriptMatch) {
    throw new Error("index.html has no inline script");
  }
  const sandbox = { window: { location: { origin: "sidekick://reminders" } }, console, Intl, Date, Math, JSON };
  vm.createContext(sandbox);
  vm.runInContext(scriptMatch[1], sandbox);
  const logic = (sandbox as Record<string, any>).RemindersLogic;
  if (!logic) {
    throw new Error("the inline script defines no RemindersLogic");
  }
  return logic;
}

const logic = loadRemindersLogic();
const LA = "America/Los_Angeles";
// Sunday Oct 11, 2026, 12:00 in Los Angeles
const SUNDAY_NOON = new Date("2026-10-11T19:00:00.000Z");

function makeItem(fields: Record<string, unknown>) {
  const defaults = {
    id: "r1", title: "Untitled", notes: "", list: null, date: null, time: null, repeat: null, timeZone: LA,
    done: false, completedAt: null, snoozedUntil: null, lastDoneAt: null,
    createdAt: "2026-10-01T00:00:00.000Z", source: null,
  };
  return { ...defaults, ...fields };
}

describe("reminder circle colour", () => {
  it("uses the reminder's own list when it has one, whatever its date", () => {
    const today = makeItem({ list: "L1", date: "2026-10-11", time: "18:00" });
    const later = makeItem({ list: "L1", date: "2026-10-14" });
    expect(logic.circleKind(today, true, SUNDAY_NOON, LA)).toBe("list");
    expect(logic.circleKind(later, true, SUNDAY_NOON, LA)).toBe("list");
  });

  it("with no list: today is blue, another day is Scheduled, no date is grey", () => {
    const dueToday = makeItem({ date: "2026-10-11", time: "18:00" });
    const tomorrow = makeItem({ date: "2026-10-12", time: "10:00" });
    const undated = makeItem({});
    expect(logic.circleKind(dueToday, false, SUNDAY_NOON, LA)).toBe("today");
    expect(logic.circleKind(tomorrow, false, SUNDAY_NOON, LA)).toBe("scheduled");
    expect(logic.circleKind(undated, false, SUNDAY_NOON, LA)).toBe("unscheduled");
  });

  it("a daily repeat with no list is blue today", () => {
    const daily = makeItem({ date: "2026-10-01", time: "20:00", repeat: { every: "day" } });
    expect(logic.circleKind(daily, false, SUNDAY_NOON, LA)).toBe("today");
  });

  it("a list that was deleted falls back to the date rule", () => {
    const orphan = makeItem({ list: "gone", date: "2026-10-12" });
    expect(logic.circleKind(orphan, false, SUNDAY_NOON, LA)).toBe("scheduled");
  });

  it("Scheduled is no longer red and All is no longer grey", () => {
    expect(bundleHtml).toMatch(/scheduled: \{ name: 'Scheduled', color: 'orange'/);
    expect(bundleHtml).toMatch(/all: \{ name: 'All', color: 'green'/);
    expect(bundleHtml).toMatch(/pastDue: \{ name: 'Past Due', color: 'red'/);
  });
});
