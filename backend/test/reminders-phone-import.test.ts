import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import vm from "node:vm";
import { describe, expect, it } from "vitest";

// The Reminders page's pure rules (RemindersLogic), run in Node without a document. Covers the
// phone import of 2026-10-10: the phone's version wins, nothing is removed, a second run changes
// nothing, a Mac file never overwrites, and the shell's parts join back together.

type AnyRecord = Record<string, any>;

const pagePath = fileURLToPath(new URL("../../sidekicks/reminders/index.html", import.meta.url));

function loadRemindersLogic(): AnyRecord {
  const html = readFileSync(pagePath, "utf8");
  const scriptStart = html.indexOf("<script>") + "<script>".length;
  const scriptEnd = html.indexOf("</script>", scriptStart);
  const scriptText = html.slice(scriptStart, scriptEnd);
  const sandbox: AnyRecord = { window: { location: { origin: "sidekick://reminders" } }, Intl, Date, Math, JSON };
  vm.createContext(sandbox);
  vm.runInContext(scriptText + "\n;globalThis.__logic = RemindersLogic;", sandbox);
  return sandbox.__logic;
}

const Logic = loadRemindersLogic();
const zone = "America/Los_Angeles";

function appleReminder(externalId: string, fields: AnyRecord = {}): AnyRecord {
  return {
    id: "device-" + externalId,
    externalId,
    listId: "phone-list",
    title: "Call the dentist",
    notes: null,
    url: null,
    completed: false,
    completionDate: null,
    creationDate: "2026-09-01T10:00:00-07:00",
    lastModifiedDate: "2026-09-01T10:00:00-07:00",
    priority: 0,
    due: { allDay: false, date: "2026-10-12", time: "09:30", timeZone: zone, instant: "2026-10-12T09:30:00-07:00" },
    alarms: [],
    recurrence: [],
    ...fields,
  };
}

function exportOf(reminders: AnyRecord[], origin: string | null): AnyRecord {
  return {
    source: "apple-reminders",
    origin,
    exportedAt: "2026-10-10T21:00:00-07:00",
    timeZone: zone,
    lists: [{ id: "phone-list", title: "Reminders", color: "#FF9500" }],
    reminders,
  };
}

// What the page holds after a first import: run the first export through the mapper
function existingAfter(firstExport: AnyRecord): AnyRecord {
  const first = Logic.mapAppleExport(firstExport, { items: [], lists: [] }, zone, { updateExisting: false });
  const items: AnyRecord[] = [];
  for (const item of first.items) {
    items.push({ ...item, recordKey: Logic.recordKey(item) });
  }
  return { items, lists: first.lists };
}

describe("phone import: the phone's version wins", () => {
  it("updates a reminder already brought in from the Mac, keeping its id", () => {
    const existing = existingAfter(exportOf([appleReminder("X1", { title: "Old title" })], null));
    const phone = exportOf([appleReminder("X1", { title: "New title" })], "iphone");

    const result = Logic.mapAppleExport(phone, existing, zone, { updateExisting: true });

    expect(result.items).toEqual([]);
    expect(result.updates).toHaveLength(1);
    expect(result.updates[0].item.title).toBe("New title");
    expect(result.updates[0].item.id).toBe(existing.items[0].id);
    expect(result.summary.updated).toBe(1);
  });

  it("adds a reminder that is only on the phone", () => {
    const existing = existingAfter(exportOf([appleReminder("X1")], null));
    const phone = exportOf([appleReminder("X1"), appleReminder("ONLY-PHONE", { title: "Buy milk" })], "iphone");

    const result = Logic.mapAppleExport(phone, existing, zone, { updateExisting: true });

    expect(result.items).toHaveLength(1);
    expect(result.items[0].title).toBe("Buy milk");
    expect(result.updates).toEqual([]);
  });

  it("never removes a reminder that is only in the Mac import", () => {
    const existing = existingAfter(exportOf([appleReminder("X1"), appleReminder("ONLY-MAC")], null));
    const phone = exportOf([appleReminder("X1")], "iphone");

    const result = Logic.mapAppleExport(phone, existing, zone, { updateExisting: true });

    expect(result.updates).toEqual([]);
    expect(result.items).toEqual([]);
    expect(Object.keys(result)).not.toContain("removals");
  });

  it("changes nothing when run again with the same reminders", () => {
    const phone = exportOf([appleReminder("X1"), appleReminder("X2", { completed: true, completionDate: "2026-10-01T08:00:00-07:00" })], "iphone");
    const existing = existingAfter(phone);

    const result = Logic.mapAppleExport(phone, existing, zone, { updateExisting: true });

    expect(result.items).toEqual([]);
    expect(result.updates).toEqual([]);
    expect(result.summary.skipped).toBe(2);
  });

  it("treats the same completion moment written with a different offset as unchanged", () => {
    const mac = exportOf([appleReminder("X1", { completed: true, completionDate: "2023-12-06T19:09:10-08:00" })], null);
    const existing = existingAfter(mac);
    const phone = exportOf([appleReminder("X1", { completed: true, completionDate: "2023-12-06T20:09:10-07:00" })], "iphone");

    const result = Logic.mapAppleExport(phone, existing, zone, { updateExisting: true });

    expect(result.updates).toEqual([]);
  });

  it("keeps a snooze the user set in Midas when the phone changes only the title", () => {
    const existing = existingAfter(exportOf([appleReminder("X1", { title: "Old" })], null));
    existing.items[0].snoozedUntil = "2026-10-12T17:00:00.000Z";
    const phone = exportOf([appleReminder("X1", { title: "New" })], "iphone");

    const result = Logic.mapAppleExport(phone, existing, zone, { updateExisting: true });

    expect(result.updates[0].item.snoozedUntil).toBe("2026-10-12T17:00:00.000Z");
    expect(result.updates[0].item.recordKey).toBeUndefined();
  });

  it("marks a reminder done when it was completed on the phone", () => {
    const existing = existingAfter(exportOf([appleReminder("X1")], null));
    const phone = exportOf([appleReminder("X1", { completed: true, completionDate: "2026-10-10T08:00:00-07:00" })], "iphone");

    const result = Logic.mapAppleExport(phone, existing, zone, { updateExisting: true });

    expect(result.updates[0].item.done).toBe(true);
    expect(result.updates[0].existing.recordKey).toBe(existing.items[0].recordKey);
  });
});

describe("a Mac export file never overwrites", () => {
  it("skips reminders already here, even when they differ", () => {
    const existing = existingAfter(exportOf([appleReminder("X1", { title: "Phone title" })], "iphone"));
    const staleMac = exportOf([appleReminder("X1", { title: "Stale Mac title" })], null);

    const result = Logic.mapAppleExport(staleMac, existing, zone, { updateExisting: false });

    expect(result.updates).toEqual([]);
    expect(result.items).toEqual([]);
    expect(result.summary.skipped).toBe(1);
  });
});

describe("joinImportParts", () => {
  function part(index: number, count: number, reminders: AnyRecord[], lists: AnyRecord[] = []): AnyRecord {
    return { key: "import:r1:" + String(index).padStart(4, "0"), value: { source: "apple-reminders", origin: "iphone", part: index, parts: count, timeZone: zone, lists, reminders } };
  }

  it("joins parts in order, whatever order they arrive in", () => {
    const lists = [{ id: "phone-list", title: "Reminders", color: "#FF9500" }];
    const records = [part(1, 2, [appleReminder("B")]), part(0, 2, [appleReminder("A")], lists)];

    const joined = Logic.joinImportParts(records);

    expect(joined.lists).toEqual(lists);
    const externalIds: string[] = [];
    for (const reminder of joined.reminders) {
      externalIds.push(reminder.externalId);
    }
    expect(externalIds).toEqual(["A", "B"]);
    expect(joined.origin).toBe("iphone");
  });

  it("refuses an import with a part missing", () => {
    const records = [part(0, 3, [appleReminder("A")]), part(2, 3, [appleReminder("C")])];

    expect(Logic.joinImportParts(records)).toBeNull();
  });

  it("returns null for no parts", () => {
    expect(Logic.joinImportParts([])).toBeNull();
  });
});
