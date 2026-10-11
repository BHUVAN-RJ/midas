// The reminders Sidekick's own logic, run from the real bundle: the page's single inline script is
// evaluated in a sandbox without a DOM, and its `RemindersLogic` object is tested directly.
// Rules come from the founder's decisions of 2026-10-09 (midas-intel
// docs/prototypes/reminders-bhuvan/BRIEF.md, rounds 1 to 3) and docs/NOTIFICATIONS.md.
import { readFileSync } from "node:fs";
import vm from "node:vm";
import { describe, expect, it } from "vitest";

const bundleHtml = readFileSync(new URL("../../sidekicks/reminders/index.html", import.meta.url), "utf8");

function loadRemindersLogic() {
  const scriptMatch = bundleHtml.match(/<script>([\s\S]*?)<\/script>/);
  if (!scriptMatch) {
    throw new Error("index.html has no inline script");
  }
  const sandboxWindow = { location: { origin: "sidekick://reminders" } };
  const sandbox = { window: sandboxWindow, console, Intl, Date, Math, JSON };
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
// Friday Oct 9, 2026, 10:00 in Los Angeles.
const FRIDAY_10AM = new Date("2026-10-09T17:00:00.000Z");

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

function sortedIdsOf(entries: Array<{ item: { id: string } }>) {
  return idsOf(entries).sort();
}

describe("time", () => {
  it("formats 24-hour times as 12-hour", () => {
    expect(logic.formatTime12("18:00")).toBe("6:00 PM");
    expect(logic.formatTime12("09:30")).toBe("9:30 AM");
    expect(logic.formatTime12("12:00")).toBe("12:00 PM");
    expect(logic.formatTime12("00:05")).toBe("12:05 AM");
  });

  it("converts wall-clock time in a zone to an instant and back, across daylight saving", () => {
    expect(logic.wallClockToInstant("2026-10-09", "18:00", LA).toISOString()).toBe("2026-10-10T01:00:00.000Z");
    expect(logic.wallClockToInstant("2026-11-02", "09:00", LA).toISOString()).toBe("2026-11-02T17:00:00.000Z");
    const wallClock = logic.instantToWallClock(new Date("2026-10-10T01:00:00.000Z"), LA);
    expect({ ...wallClock }).toEqual({ date: "2026-10-09", time: "18:00", weekday: 5 });
  });

  it("starts weeks on Monday and months on the 1st", () => {
    expect({ ...logic.weekRange(FRIDAY_10AM, LA) }).toEqual({ start: "2026-10-05", end: "2026-10-11" });
    const sundayNoon = new Date("2026-10-11T19:00:00.000Z");
    expect({ ...logic.weekRange(sundayNoon, LA) }).toEqual({ start: "2026-10-05", end: "2026-10-11" });
    const mondayNoon = new Date("2026-10-12T19:00:00.000Z");
    expect({ ...logic.weekRange(mondayNoon, LA) }).toEqual({ start: "2026-10-12", end: "2026-10-18" });
    expect({ ...logic.monthRange(FRIDAY_10AM, LA) }).toEqual({ start: "2026-10-01", end: "2026-10-31" });
  });
});

describe("repeat options", () => {
  it("map to exactly the notification engine's repeat format", () => {
    expect(logic.repeatForOption("never")).toBeNull();
    expect({ ...logic.repeatForOption("daily") }).toEqual({ every: "day" });
    expect(JSON.parse(JSON.stringify(logic.repeatForOption("weekdays")))).toEqual({ every: "week", weekdays: [1, 2, 3, 4, 5] });
    expect(JSON.parse(JSON.stringify(logic.repeatForOption("weekends")))).toEqual({ every: "week", weekdays: [0, 6] });
    expect({ ...logic.repeatForOption("weekly") }).toEqual({ every: "week" });
    expect({ ...logic.repeatForOption("monthly") }).toEqual({ every: "month" });
  });

  it("read back from a repeat, with anything else shown as custom", () => {
    expect(logic.optionForRepeat(null)).toBe("never");
    expect(logic.optionForRepeat({ every: "week", weekdays: [1, 2, 3, 4, 5] })).toBe("weekdays");
    expect(logic.optionForRepeat({ every: "week", weekdays: [0, 6] })).toBe("weekends");
    expect(logic.optionForRepeat({ every: "day", interval: 2 })).toBe("custom");
    expect(logic.optionForRepeat({ every: "year" })).toBe("custom");
  });
});

describe("records", () => {
  it("keys dated items as reminder: and undated items as task:", () => {
    expect(logic.recordKey(makeItem({ id: "a1", date: "2026-10-09", time: "18:00" }))).toBe("reminder:a1");
    expect(logic.recordKey(makeItem({ id: "b2" }))).toBe("task:b2");
  });

  it("writes a timed reminder in the engine's format, with no repeat key when it does not repeat", () => {
    const item = makeItem({ id: "a1", title: "Call Amma", list: "personal", date: "2026-10-09", time: "18:00" });
    const value = logic.recordFromItem(item, null);
    expect(value.at).toBe("2026-10-10T01:00:00.000Z");
    expect(value.title).toBe("Call Amma");
    expect(value.timeZone).toBe(LA);
    expect(value.list).toBe("personal");
    expect(value.allDay).toBe(false);
    expect(value.done).toBe(false);
    expect("repeat" in value).toBe(false);
  });

  it("books an all-day reminder at 09:00 local", () => {
    const item = makeItem({ id: "a2", title: "Renew car insurance", date: "2026-10-20" });
    const value = logic.recordFromItem(item, null);
    expect(value.at).toBe("2026-10-20T16:00:00.000Z");
    expect(value.allDay).toBe(true);
  });

  it("keeps what the shell wrote (lastDoneAt, snoozedUntil) and unknown fields when editing", () => {
    const existing = {
      at: "2026-10-10T01:00:00.000Z", title: "Call Amma", timeZone: LA, list: "personal", allDay: false,
      done: false, snoozedUntil: "2026-10-10T02:00:00.000Z", lastDoneAt: "2026-10-08T03:00:00.000Z", extra: "keep",
    };
    const item = logic.itemFromRecord("reminder:a1", existing);
    item.title = "Call Amma and Appa";
    const value = logic.recordFromItem(item, existing);
    expect(value.title).toBe("Call Amma and Appa");
    expect(value.snoozedUntil).toBe("2026-10-10T02:00:00.000Z");
    expect(value.lastDoneAt).toBe("2026-10-08T03:00:00.000Z");
    expect(value.extra).toBe("keep");
  });

  it("clears an old snooze when the reminder is moved to a new time", () => {
    const existing = {
      at: "2026-10-10T01:00:00.000Z", title: "Call Amma", timeZone: LA, done: false,
      snoozedUntil: "2026-10-10T02:00:00.000Z", lastDoneAt: "2026-10-08T03:00:00.000Z",
    };
    const item = logic.itemFromRecord("reminder:a1", existing);
    item.time = "20:00";
    const value = logic.recordFromItem(item, existing);
    expect(value.at).toBe("2026-10-10T03:00:00.000Z");
    expect(value.snoozedUntil).toBeUndefined();
    expect(value.lastDoneAt).toBe("2026-10-08T03:00:00.000Z");
  });

  it("round-trips an item through its record", () => {
    const item = makeItem({
      id: "a3", title: "Gym", list: "personal", date: "2026-10-01", time: "19:30", repeat: { every: "day" },
    });
    const back = logic.itemFromRecord("reminder:a3", logic.recordFromItem(item, null));
    expect(back.id).toBe("a3");
    expect(back.title).toBe("Gym");
    expect(back.list).toBe("personal");
    expect(back.date).toBe("2026-10-01");
    expect(back.time).toBe("19:30");
    expect({ ...back.repeat }).toEqual({ every: "day" });

    const task = makeItem({ id: "t1", title: "Milk", list: "groceries" });
    const taskValue = logic.recordFromItem(task, null);
    expect("at" in taskValue).toBe(false);
    const taskBack = logic.itemFromRecord("task:t1", taskValue);
    expect(taskBack.date).toBeNull();
    expect(taskBack.list).toBe("groceries");
  });

  it("packs completed history into records of at most 200 and unpacks it unchanged", () => {
    const history = [];
    for (let index = 0; index < 450; index += 1) {
      history.push(makeItem({ id: `h${index}`, title: `Done ${index}`, done: true, completedAt: "2026-01-01T00:00:00.000Z" }));
    }
    const records = logic.packHistory(history);
    expect(records).toHaveLength(3);
    for (const record of records) {
      expect(record.key.startsWith("history:")).toBe(true);
      expect(record.value.items.length).toBeLessThanOrEqual(200);
    }
    const unpacked = logic.unpackHistory(records);
    expect(unpacked).toHaveLength(450);
    expect(unpacked[449].id).toBe("h449");
  });
});

describe("where a reminder shows", () => {
  const items = [
    makeItem({ id: "callAmma", title: "Call Amma", list: "personal", date: "2026-10-09", time: "18:00" }),
    makeItem({ id: "replyInvite", title: "Reply to a16z invite", list: "midas", date: "2026-10-09", time: "09:00" }),
    makeItem({ id: "bill", title: "Pay electricity bill", list: "personal", date: "2026-10-07", time: "09:00" }),
    makeItem({ id: "dentist", title: "Dentist", list: "personal", date: "2026-10-11", time: "10:30" }),
    makeItem({ id: "insurance", title: "Renew car insurance", list: "personal", date: "2026-10-20" }),
    makeItem({ id: "november", title: "November thing", list: "midas", date: "2026-11-03", time: "10:00" }),
    makeItem({ id: "haircut", title: "Book haircut", list: "personal" }),
    makeItem({ id: "passport", title: "Renew passport" }),
    makeItem({ id: "doneOne", title: "Done already", list: "personal", date: "2026-10-08", time: "09:00", done: true, completedAt: "2026-10-08T17:00:00.000Z" }),
    // Daily at 19:30 since Oct 1; last done on Oct 7 at 20:00, so Oct 8's occurrence was missed.
    makeItem({ id: "gym", title: "Gym", list: "personal", date: "2026-10-01", time: "19:30", repeat: { every: "day" }, lastDoneAt: "2026-10-08T03:00:00.000Z" }),
    // Due today at 08:00, snoozed until 11:00.
    makeItem({ id: "snoozed", title: "Snoozed one", list: "midas", date: "2026-10-09", time: "08:00", snoozedUntil: "2026-10-09T18:00:00.000Z" }),
  ];

  it("Today: dated today, including today's past-due ones (marked), in time order", () => {
    const today = logic.itemsInList(items, "today", FRIDAY_10AM, LA);
    expect(idsOf(today)).toEqual(["replyInvite", "snoozed", "callAmma", "gym"]);
    expect(today[0].pastDue).toBe(true);
    expect(today[1].pastDue).toBe(false);
  });

  it("Past Due: earlier days only, oldest first, and only a repeat's latest missed occurrence", () => {
    const pastDue = logic.itemsInList(items, "pastDue", FRIDAY_10AM, LA);
    expect(idsOf(pastDue)).toEqual(["bill", "gym"]);
    expect(pastDue[1].at.toISOString()).toBe("2026-10-09T02:30:00.000Z");
  });

  it("Scheduled, Unscheduled, All, Completed and an own list", () => {
    expect(sortedIdsOf(logic.itemsInList(items, "scheduled", FRIDAY_10AM, LA))).toEqual(
      ["callAmma", "dentist", "gym", "insurance", "november", "snoozed"]);
    expect(idsOf(logic.itemsInList(items, "unscheduled", FRIDAY_10AM, LA))).toEqual(["passport"]);
    expect(sortedIdsOf(logic.itemsInList(items, "all", FRIDAY_10AM, LA))).toEqual(
      ["callAmma", "dentist", "gym", "haircut", "insurance", "november", "passport", "snoozed"]);
    expect(idsOf(logic.itemsInList(items, "completed", FRIDAY_10AM, LA))).toEqual(["doneOne"]);
    expect(sortedIdsOf(logic.itemsInList(items, "personal", FRIDAY_10AM, LA))).toEqual(
      ["callAmma", "dentist", "gym", "haircut", "insurance"]);
  });

  it("keeps today's past-due reminder in Today until midnight, then moves it to Past Due", () => {
    const beforeMidnight = new Date("2026-10-10T06:59:00.000Z");
    const atMidnight = new Date("2026-10-10T07:00:00.000Z");
    expect(idsOf(logic.itemsInList(items, "today", beforeMidnight, LA))).toContain("replyInvite");
    expect(idsOf(logic.itemsInList(items, "pastDue", beforeMidnight, LA))).not.toContain("replyInvite");
    expect(idsOf(logic.itemsInList(items, "today", atMidnight, LA))).not.toContain("replyInvite");
    expect(idsOf(logic.itemsInList(items, "pastDue", atMidnight, LA))).toContain("replyInvite");
  });

  it("moves a repeat's missed occurrence today into Today and keeps the next one scheduled", () => {
    const fridayEightPm = new Date("2026-10-10T03:00:00.000Z");
    const today = logic.itemsInList(items, "today", fridayEightPm, LA);
    const gymToday = today.find((entry: { item: { id: string } }) => entry.item.id === "gym");
    expect(gymToday.pastDue).toBe(true);
    expect(idsOf(logic.itemsInList(items, "pastDue", fridayEightPm, LA))).not.toContain("gym");
    const scheduled = logic.itemsInList(items, "scheduled", fridayEightPm, LA);
    const gymScheduled = scheduled.find((entry: { item: { id: string } }) => entry.item.id === "gym");
    expect(gymScheduled.at.toISOString()).toBe("2026-10-11T02:30:00.000Z");
  });

  it("drops a repeat from Past Due once Done is tapped after the missed occurrence", () => {
    const gymDone = makeItem({
      id: "gym", title: "Gym", list: "personal", date: "2026-10-01", time: "19:30", repeat: { every: "day" },
      lastDoneAt: "2026-10-09T16:00:00.000Z",
    });
    expect(idsOf(logic.itemsInList([gymDone], "pastDue", FRIDAY_10AM, LA))).toEqual([]);
  });

  it("This Week runs from today to Sunday, This Month to the 31st; undated and earlier days excluded", () => {
    expect(sortedIdsOf(logic.itemsInScope(items, "week", FRIDAY_10AM, LA))).toEqual(
      ["callAmma", "dentist", "gym", "replyInvite", "snoozed"]);
    expect(sortedIdsOf(logic.itemsInScope(items, "month", FRIDAY_10AM, LA))).toEqual(
      ["callAmma", "dentist", "gym", "insurance", "replyInvite", "snoozed"]);
  });
});

describe("Apple Reminders import (the export file the shell import will produce later)", () => {
  function reminder(fields: Record<string, unknown>) {
    const defaults = {
      listId: "L2", title: "Untitled", notes: null, url: null, priority: 0, completed: false,
      completionDate: null, creationDate: "2026-09-01T10:00:00-07:00", lastModifiedDate: "2026-09-01T10:00:00-07:00",
      due: null, alarms: [], recurrence: [],
    };
    return { ...defaults, ...fields };
  }

  function timedDue(date: string, time: string, instant: string) {
    return { date, time, allDay: false, timeZone: LA, instant };
  }

  const appleExport = {
    source: "apple-reminders",
    exportedAt: "2026-10-09T23:48:02-07:00",
    timeZone: LA,
    lists: [
      { id: "L1", title: "Groceries", color: "#34C759" },
      { id: "L2", title: "Personal", color: "#007AFF" },
    ],
    reminders: [
      reminder({ id: "r1", externalId: "X1", listId: "L1", title: "Milk" }),
      reminder({ id: "r2", externalId: "X2", title: "Call Amma", due: timedDue("2026-10-12", "18:00", "2026-10-12T18:00:00-07:00"),
        alarms: [{ absoluteDate: "2026-10-12T18:00:00-07:00", relativeOffsetSeconds: null }] }),
      reminder({ id: "r3", externalId: "X3", title: "Insurance", due: { date: "2026-10-20", time: null, allDay: true, timeZone: null, instant: null } }),
      reminder({ id: "r4", externalId: "X4", title: "Vitamins", due: timedDue("2026-10-01", "07:00", "2026-10-01T07:00:00-07:00"),
        recurrence: [{ frequency: "daily", interval: 1, daysOfWeek: null, daysOfMonth: null, monthsOfYear: null, weeksOfYear: null, daysOfYear: null, setPositions: null, end: null }] }),
      reminder({ id: "r5", externalId: "X5", title: "Sam's birthday", due: timedDue("2027-03-14", "09:00", "2027-03-14T09:00:00-07:00"),
        recurrence: [{ frequency: "yearly", interval: 1, daysOfWeek: null, daysOfMonth: null, monthsOfYear: null, weeksOfYear: null, daysOfYear: null, setPositions: null, end: null }] }),
      reminder({ id: "r6", externalId: "X6", title: "Trash", due: timedDue("2026-10-12", "20:00", "2026-10-12T20:00:00-07:00"),
        recurrence: [{ frequency: "weekly", interval: 1, daysOfWeek: [{ weekday: 2, weekNumber: 0 }, { weekday: 4, weekNumber: 0 }], daysOfMonth: null, monthsOfYear: null, weeksOfYear: null, daysOfYear: null, setPositions: null, end: null }] }),
      reminder({ id: "r7", externalId: "X7", title: "Board meeting", due: timedDue("2026-11-02", "10:00", "2026-11-02T10:00:00-08:00"),
        recurrence: [{ frequency: "monthly", interval: 1, daysOfWeek: [{ weekday: 2, weekNumber: 0 }], daysOfMonth: null, monthsOfYear: null, weeksOfYear: null, daysOfYear: null, setPositions: [1], end: null }] }),
      reminder({ id: "r8", externalId: "X8", title: "Old task", completed: true, completionDate: "2025-05-01T10:00:00-07:00" }),
      reminder({ id: "r9", externalId: "X9", title: "Standup", due: timedDue("2026-10-13", "10:00", "2026-10-13T10:00:00-07:00"),
        alarms: [{ absoluteDate: "2026-10-13T09:45:00-07:00", relativeOffsetSeconds: null }] }),
      reminder({ id: "r10", externalId: "X10", title: "Course", due: timedDue("2026-10-14", "18:00", "2026-10-14T18:00:00-07:00"),
        recurrence: [{ frequency: "weekly", interval: 2, daysOfWeek: null, daysOfMonth: null, monthsOfYear: null, weeksOfYear: null, daysOfYear: null, setPositions: null, end: { date: "2026-12-31T23:59:59-08:00", occurrenceCount: null } }] }),
      reminder({ id: "r11", externalId: "X11", title: "" }),
    ],
  };

  function itemWithExternalId(items: Array<{ source: { externalId: string } }>, externalId: string): any {
    return items.find((item) => item.source.externalId === externalId);
  }

  const imported = logic.mapAppleExport(appleExport, { items: [], lists: [] }, LA);

  it("brings every list across with its name and colour", () => {
    expect(imported.lists).toHaveLength(2);
    const groceries = imported.lists.find((list: { name: string }) => list.name === "Groceries");
    expect(groceries.color).toBe("#34C759");
  });

  it("keeps undated items in their list, and dates and all-day as Apple had them", () => {
    const groceries = imported.lists.find((list: { name: string }) => list.name === "Groceries");
    const milk = itemWithExternalId(imported.items, "X1");
    expect(milk.date).toBeNull();
    expect(milk.list).toBe(groceries.id);
    const callAmma = itemWithExternalId(imported.items, "X2");
    expect([callAmma.date, callAmma.time]).toEqual(["2026-10-12", "18:00"]);
    const insurance = itemWithExternalId(imported.items, "X3");
    expect([insurance.date, insurance.time]).toEqual(["2026-10-20", null]);
  });

  it("maps every repeat the engine supports", () => {
    expect({ ...itemWithExternalId(imported.items, "X4").repeat }).toEqual({ every: "day" });
    expect({ ...itemWithExternalId(imported.items, "X5").repeat }).toEqual({ every: "year" });
    expect(JSON.parse(JSON.stringify(itemWithExternalId(imported.items, "X6").repeat))).toEqual({ every: "week", weekdays: [1, 3] });
    const course = JSON.parse(JSON.stringify(itemWithExternalId(imported.items, "X10").repeat));
    expect(course.every).toBe("week");
    expect(course.interval).toBe(2);
    expect(new Date(course.until).toISOString()).toBe("2027-01-01T07:59:59.000Z");
  });

  it("brings an unsupported repeat in as a one-off with a note, never silently", () => {
    const boardMeeting = itemWithExternalId(imported.items, "X7");
    expect(boardMeeting.repeat).toBeNull();
    expect(boardMeeting.notes).toMatch(/repeat/i);
    expect(imported.unsupported).toHaveLength(1);
  });

  it("uses the alert time when it differs from the due time", () => {
    expect(itemWithExternalId(imported.items, "X9").time).toBe("09:45");
  });

  it("brings completed reminders across as done, and gives untitled ones a title", () => {
    const oldTask = itemWithExternalId(imported.items, "X8");
    expect(oldTask.done).toBe(true);
    expect(new Date(oldTask.completedAt).toISOString()).toBe("2025-05-01T17:00:00.000Z");
    expect(itemWithExternalId(imported.items, "X11").title.length).toBeGreaterThan(0);
  });

  it("counts what came in", () => {
    expect(imported.summary.reminders).toBe(11);
    expect(imported.summary.completed).toBe(1);
    expect(imported.summary.active).toBe(10);
    expect(imported.summary.unsupportedRepeats).toBe(1);
  });

  it("gives the same ids every time and adds nothing on a second run", () => {
    const again = logic.mapAppleExport(appleExport, { items: [], lists: [] }, LA);
    expect(itemWithExternalId(again.items, "X2").id).toBe(itemWithExternalId(imported.items, "X2").id);
    const secondRun = logic.mapAppleExport(appleExport, { items: imported.items, lists: imported.lists }, LA);
    expect(secondRun.items).toHaveLength(0);
    expect(secondRun.lists).toHaveLength(0);
  });
});
