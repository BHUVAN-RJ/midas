// Boomi's copy of Reminders (founder, 2026-10-25, mockup docs/mockups/boomi-reminders-2026-10-25.html):
// three pages only, Today -> Next 7 Days -> Scheduled, each pulled up from the one before. No Lists
// drawer, no lists, no Import, no Past Due, Unscheduled, All or Completed page. A reminder missed on
// an earlier day stays at the top of Today until done; one with no date goes at the bottom of Today.
// Runs where the repair runner runs it: the copy's page at sidekicks/reminders/index.html.
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
// Sunday Oct 25, 2026, 12:00 in Los Angeles
const SUNDAY_NOON = new Date("2026-10-25T19:00:00.000Z");

function makeItem(fields: Record<string, unknown>) {
  const defaults = {
    title: "Untitled", notes: "", list: null, date: null, time: null, repeat: null, timeZone: LA,
    done: false, completedAt: null, snoozedUntil: null, lastDoneAt: null,
    createdAt: "2026-10-01T00:00:00.000Z", source: null,
  };
  return { ...defaults, ...fields };
}

function idsOf(entries: Array<{ item: { id: string } }>) {
  const ids: string[] = [];
  for (const entry of entries) {
    ids.push(entry.item.id);
  }
  return ids;
}

describe("Boomi's Today", () => {
  const items = [
    makeItem({ id: "later", title: "Pick up dry cleaning", date: "2026-10-25", time: "19:00" }),
    makeItem({ id: "undated", title: "Read 20 pages" }),
    makeItem({ id: "missed", title: "Pay electricity bill", date: "2026-10-24", time: "18:00" }),
    makeItem({ id: "morning", title: "Water the plants", date: "2026-10-25", time: "09:00" }),
    makeItem({ id: "tomorrow", title: "Dentist", date: "2026-10-26", time: "10:00" }),
    makeItem({ id: "doneMissed", title: "Old one", date: "2026-10-20", time: "08:00", done: true, completedAt: "2026-10-20T16:00:00.000Z" }),
  ];

  it("shows missed reminders first, then today's in time order, then undated", () => {
    const shown = logic.todayWithMissed(items, SUNDAY_NOON, LA);
    expect(idsOf(shown)).toEqual(["missed", "morning", "later", "undated"]);
  });

  it("marks a missed reminder past due, on its own day", () => {
    const shown = logic.todayWithMissed(items, SUNDAY_NOON, LA);
    expect(shown[0].pastDue).toBe(true);
    expect(shown[0].day).toBe("2026-10-24");
  });

  it("leaves out reminders for later days and done ones", () => {
    const ids = idsOf(logic.todayWithMissed(items, SUNDAY_NOON, LA));
    expect(ids).not.toContain("tomorrow");
    expect(ids).not.toContain("doneMissed");
  });

  it("is what the Today page draws", () => {
    expect(bundleHtml).toContain("const shown = Logic.todayWithMissed(state.items, Date.now(), deviceZone);");
  });
});

describe("Boomi's pages and controls", () => {
  it("has exactly three pages, in order", () => {
    expect(bundleHtml).toContain("const BOOMI_PAGES = ['today', 'next7', 'scheduled'];");
    expect(bundleHtml).toMatch(/function pageOrder\(\) \{\s*return BOOMI_PAGES\.slice\(\);\s*\}/);
  });

  it("has no Lists drawer button and no Import menu button", () => {
    expect(bundleHtml).not.toContain('data-action="open-drawer"');
    expect(bundleHtml).not.toContain('data-action="menu"');
  });

  it("never offers Import Apple Reminders or Import File", () => {
    expect(bundleHtml).not.toContain('data-action="bring-in"');
    expect(bundleHtml).not.toContain('data-action="bring-in-file"');
    expect(bundleHtml).not.toContain('id="bring-in-file"');
    expect(bundleHtml).not.toMatch(/>Import Apple Reminders/);
  });

  it("has no List button on the keyboard toolbar and no List row in Details", () => {
    expect(bundleHtml).not.toContain('data-native="acc-list"');
    expect(bundleHtml).not.toContain('data-native="det-list"');
  });

  it("can pull to the next page even before the first reminder", () => {
    expect(bundleHtml).toMatch(/function canPullToNextList\(\) \{\s*return state\.loaded && !state\.editing && nextViewOf\(state\.view\) !== null;/);
  });
});
