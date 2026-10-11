// Next 7 Days in the reminders Sidekick (founder-approved 2026-10-11, mockup
// docs/mockups/next-7-days-2026-10-11.html). It replaces This Week, which ran Monday to Sunday,
// so on a Sunday a reminder for the next day (Monday) was missing from it. The page's single
// inline script is evaluated without a DOM and its `RemindersLogic` object is tested directly.
import { readFileSync } from "node:fs";
import vm from "node:vm";
import { describe, expect, it } from "vitest";

const bundleHtml = readFileSync(new URL("../../sidekicks/reminders/index.html", import.meta.url), "utf8");

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
// Sunday Oct 11, 2026, 12:00 in Los Angeles: the day the bug was reported.
const SUNDAY_NOON = new Date("2026-10-11T19:00:00.000Z");

function makeItem(fields: Record<string, unknown>) {
  const defaults = {
    title: "Untitled", notes: "", list: null, date: null, time: null, repeat: null, timeZone: LA,
    done: false, completedAt: null, snoozedUntil: null, lastDoneAt: null,
    createdAt: "2026-10-01T00:00:00.000Z", source: null,
  };
  return { ...defaults, ...fields };
}

function idsOf(entries: Array<{ item: { id: string } }>) {
  const ids = [];
  for (const entry of entries) {
    ids.push(entry.item.id);
  }
  return ids;
}

function dayOf(entries: Array<{ item: { id: string }; day: string }>, id: string) {
  for (const entry of entries) {
    if (entry.item.id === id) {
      return entry.day;
    }
  }
  return null;
}

describe("Next 7 Days range", () => {
  it("runs from tomorrow to a week from today, also on a Sunday", () => {
    expect({ ...logic.next7Range(SUNDAY_NOON, LA) }).toEqual({ start: "2026-10-12", end: "2026-10-18" });
    const wednesdayNoon = new Date("2026-10-14T19:00:00.000Z");
    expect({ ...logic.next7Range(wednesdayNoon, LA) }).toEqual({ start: "2026-10-15", end: "2026-10-21" });
  });

  it("crosses the end of a month", () => {
    const october28 = new Date("2026-10-28T19:00:00.000Z");
    expect({ ...logic.next7Range(october28, LA) }).toEqual({ start: "2026-10-29", end: "2026-11-04" });
  });
});

describe("what Next 7 Days shows", () => {
  const items = [
    makeItem({ id: "laterToday", title: "Call mom", date: "2026-10-11", time: "18:00" }),
    makeItem({ id: "dentistTomorrow", title: "Dentist", date: "2026-10-12", time: "10:00" }),
    makeItem({ id: "allDayTuesday", title: "Renew insurance", date: "2026-10-13" }),
    makeItem({ id: "daySeven", title: "Day seven", date: "2026-10-18", time: "21:00" }),
    makeItem({ id: "dayEight", title: "Day eight", date: "2026-10-19", time: "08:00" }),
    makeItem({ id: "lastWeek", title: "Last week", date: "2026-10-05", time: "09:00" }),
    makeItem({ id: "undated", title: "Milk" }),
    makeItem({ id: "doneTomorrow", title: "Done", date: "2026-10-12", time: "09:00", done: true, completedAt: "2026-10-10T00:00:00.000Z" }),
  ];

  it("includes tomorrow's reminder (the Sunday bug) and day 7, and leaves out today, day 8, past, undated and done", () => {
    const entries = logic.itemsInList(items, "next7", SUNDAY_NOON, LA);
    expect(idsOf(entries)).toEqual(["dentistTomorrow", "allDayTuesday", "daySeven"]);
  });

  it("is in time order, with all-day before timed on the same day", () => {
    const sameDay = [
      makeItem({ id: "evening", date: "2026-10-13", time: "19:00" }),
      makeItem({ id: "morning", date: "2026-10-13", time: "07:00" }),
      makeItem({ id: "allDay", date: "2026-10-13" }),
    ];
    expect(idsOf(logic.itemsInList(sameDay, "next7", SUNDAY_NOON, LA))).toEqual(["allDay", "morning", "evening"]);
  });
});

describe("repeating reminders in Next 7 Days", () => {
  it("shows a weekly repeat once, on its weekday", () => {
    // Started Thursday Oct 1, weekly: Thursdays.
    const weekly = makeItem({ id: "rent", date: "2026-10-01", time: "09:00", repeat: { every: "week" } });
    const entries = logic.itemsInList([weekly], "next7", SUNDAY_NOON, LA);
    expect(idsOf(entries)).toEqual(["rent"]);
    expect(dayOf(entries, "rent")).toBe("2026-10-15");
  });

  it("shows a daily repeat on tomorrow, even when today's occurrence is still to come", () => {
    const daily = makeItem({ id: "gym", date: "2026-10-01", time: "19:30", repeat: { every: "day" } });
    const entries = logic.itemsInList([daily], "next7", SUNDAY_NOON, LA);
    expect(idsOf(entries)).toEqual(["gym"]);
    expect(dayOf(entries, "gym")).toBe("2026-10-12");
  });

  it("skips occurrences already done ahead of time", () => {
    // Monday's occurrence was marked done early, so Tuesday's is next.
    const daily = makeItem({
      id: "vitamins", date: "2026-10-01", time: "08:00", repeat: { every: "day" },
      doneThrough: "2026-10-12T15:00:00.000Z",
    });
    expect(dayOf(logic.itemsInList([daily], "next7", SUNDAY_NOON, LA), "vitamins")).toBe("2026-10-13");
  });

  it("leaves out a repeat whose next occurrence is after day 7, and one that has ended", () => {
    const monthly = makeItem({ id: "bill", date: "2026-09-25", time: "09:00", repeat: { every: "month" } });
    const ended = makeItem({
      id: "course", date: "2026-09-01", time: "18:00", repeat: { every: "day", until: "2026-10-11T00:00:00.000Z" },
    });
    expect(idsOf(logic.itemsInList([monthly, ended], "next7", SUNDAY_NOON, LA))).toEqual([]);
  });
});

describe("Next 7 Days in the list order", () => {
  it("comes right after Today for new people", () => {
    expect(logic.BUILTIN_IDS[0]).toBe("today");
    expect(logic.BUILTIN_IDS[1]).toBe("next7");
  });

  it("is added right after Today to an order saved before it existed, keeping the rest as it was", () => {
    expect([...logic.orderWithLaterBuiltins(["all", "today", "groceries", "scheduled"])]).toEqual(
      ["all", "today", "next7", "groceries", "scheduled"]);
  });

  it("is not added twice or moved when the saved order has it", () => {
    expect([...logic.orderWithLaterBuiltins(["scheduled", "next7", "today"])]).toEqual(["scheduled", "next7", "today"]);
  });

  it("goes first when the saved order has no Today, and an empty order stays empty", () => {
    expect([...logic.orderWithLaterBuiltins(["groceries", "all"])]).toEqual(["next7", "groceries", "all"]);
    expect([...logic.orderWithLaterBuiltins([])]).toEqual([]);
  });
});
