// Boomi's copy has Import Apple Reminders again (founder, 2026-10-26: "it's a reminders feature"),
// in the same More menu as the base, with Import File beside it. Her copy has no lists, so Apple's
// lists are left behind: every reminder comes in with no list and lands on Today, Next 7 Days or
// Scheduled by its date alone, and the summary has no Lists line.
// Runs where the repair runner runs it: the copy's page at sidekicks/reminders/index.html.
import { readFileSync } from "node:fs";
import vm from "node:vm";
import { describe, expect, it } from "vitest";

const bundleHtml = readFileSync(new URL("../../sidekicks/reminders/index.html", import.meta.url), "utf8");
const manifest = JSON.parse(readFileSync(new URL("../../sidekicks/reminders/manifest.json", import.meta.url), "utf8"));
const LA = "America/Los_Angeles";

function inlineScript() {
  const scriptMatch = bundleHtml.match(/<script>([\s\S]*?)<\/script>/);
  if (!scriptMatch) {
    throw new Error("index.html has no inline script");
  }
  return scriptMatch[1];
}

function loadRemindersLogic() {
  const sandbox = { window: { location: { origin: "sidekick://reminders" } }, console, Intl, Date, Math, JSON };
  vm.createContext(sandbox);
  vm.runInContext(inlineScript(), sandbox);
  return (sandbox as Record<string, any>).RemindersLogic;
}

// The page's own leaveListsBehind, run on its own
function loadLeaveListsBehind() {
  const functionMatch = inlineScript().match(/function leaveListsBehind\(result\) \{[\s\S]*?\n {2}\}\n/);
  if (!functionMatch) {
    throw new Error("the page has no leaveListsBehind");
  }
  const sandbox: Record<string, any> = {};
  vm.createContext(sandbox);
  vm.runInContext(functionMatch[0] + "\nthis.leaveListsBehind = leaveListsBehind;", sandbox);
  return sandbox.leaveListsBehind as (result: any) => void;
}

function reminder(fields: Record<string, unknown>) {
  const defaults = {
    listId: "L2", title: "Untitled", notes: null, url: null, priority: 0, completed: false,
    completionDate: null, creationDate: "2026-09-01T10:00:00-07:00", lastModifiedDate: "2026-09-01T10:00:00-07:00",
    due: null, alarms: [], recurrence: [],
  };
  return { ...defaults, ...fields };
}

const appleExport = {
  source: "apple-reminders",
  exportedAt: "2026-10-26T09:00:00-07:00",
  timeZone: LA,
  lists: [
    { id: "L1", title: "Groceries", color: "#34C759" },
    { id: "L2", title: "Personal", color: "#007AFF" },
  ],
  reminders: [
    reminder({ id: "r1", externalId: "X1", listId: "L1", title: "Milk" }),
    reminder({ id: "r2", externalId: "X2", title: "Call Amma",
      due: { date: "2026-10-27", time: "18:00", allDay: false, timeZone: LA, instant: "2026-10-27T18:00:00-07:00" } }),
  ],
};

describe("Boomi's Import menu", () => {
  it("has the More button on the page's navbar", () => {
    expect(bundleHtml).toContain(`data-action="menu" aria-label="More"`);
  });

  it("offers Import Apple Reminders and Import File in the menu", () => {
    expect(bundleHtml).toContain(`'<button type="button" data-action="bring-in">Import Apple Reminders'`);
    expect(bundleHtml).toContain(`'<button type="button" data-action="bring-in-file">Import File'`);
    expect(bundleHtml).toContain('id="bring-in-file"');
    expect(bundleHtml).toMatch(/if \(action === 'bring-in'\) \{\s*requestPhoneImport\(\);/);
    expect(bundleHtml).toMatch(/action === 'bring-in-file'\) \{\s*chooseBringInFile\(\);/);
  });

  it("still has no Lists drawer button", () => {
    expect(bundleHtml).not.toContain('data-action="open-drawer"');
  });

  it("tells jess that Import runs only on the page", () => {
    expect(manifest.agent.rules).toContain("Import from Apple Reminders runs only on the page.");
  });
});

describe("Boomi's Import leaves Apple's lists behind", () => {
  const logic = loadRemindersLogic();
  const leaveListsBehind = loadLeaveListsBehind();

  it("runs on every import, right after the export is read", () => {
    expect(bundleHtml).toMatch(/const result = Logic\.mapAppleExport\([^\n]*\n\s*leaveListsBehind\(result\);/);
  });

  it("brings in the reminders with no list and no list records", () => {
    const result = logic.mapAppleExport(appleExport, { items: [], lists: [] }, LA);
    // Without the copy's step, the base would bring in both lists and file Milk under Groceries
    expect(result.lists.length).toBe(2);
    leaveListsBehind(result);
    expect(result.lists).toEqual([]);
    expect(result.summary.lists).toBe(0);
    expect(result.items.length).toBe(2);
    for (const item of result.items) {
      expect(item.list).toBeNull();
    }
  });

  it("takes the list off a reminder the phone updates too", () => {
    const result = { lists: [], items: [], updates: [{ existing: {}, item: { id: "a1", list: "l-groceries" } }], summary: { lists: 1 } };
    leaveListsBehind(result);
    expect(result.updates[0].item.list).toBeNull();
  });

  it("shows no Lists line in the summary", () => {
    expect(bundleHtml).not.toContain("summaryCell('Lists'");
  });
});
