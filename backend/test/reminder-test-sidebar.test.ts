// Reminder Test is a demo copy with a short sidebar (founder, 2026-11-02: "too many lists,
// shortlist it to six, or maybe five"): Next 7 Days, Unscheduled, Past Due and Completed are not
// shown; Today, Scheduled, All and the person's own lists are. The page's own viewExists and
// HIDDEN_BUILTINS are lifted out of index.html and run, so the check follows the shipped code.
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const bundleHtml = readFileSync(new URL("../../sidekicks/reminder-test/index.html", import.meta.url), "utf8");

const ALL_BUILTINS = ["today", "next7", "scheduled", "unscheduled", "all", "pastDue", "completed"];

// Builds the page's viewExists with a stand-in state holding one list of the person's
function loadViewExists(): (viewId: string) => boolean {
  const hiddenSource = bundleHtml.match(/const HIDDEN_BUILTINS = \[[^\]]*\];/);
  const functionSource = bundleHtml.match(/function viewExists\(viewId\) \{[\s\S]*?\n  \}/);
  expect(hiddenSource).not.toBeNull();
  expect(functionSource).not.toBeNull();
  const factorySource =
    "const state = { lists: { work: { id: 'work', name: 'Work' } } };\n" +
    "function isBuiltin(viewId) { return BUILTINS.indexOf(viewId) !== -1; }\n" +
    hiddenSource![0] + "\n" + functionSource![0] + "\nreturn viewExists;";
  const makeViewExists = new Function("BUILTINS", factorySource);
  return makeViewExists(ALL_BUILTINS);
}

describe("Reminder Test sidebar is short", () => {
  it("hides Next 7 Days, Unscheduled, Past Due and Completed", () => {
    const viewExists = loadViewExists();
    expect(viewExists("next7")).toBe(false);
    expect(viewExists("unscheduled")).toBe(false);
    expect(viewExists("pastDue")).toBe(false);
    expect(viewExists("completed")).toBe(false);
  });

  it("still shows Today, Scheduled, All and the person's own lists", () => {
    const viewExists = loadViewExists();
    expect(viewExists("today")).toBe(true);
    expect(viewExists("scheduled")).toBe(true);
    expect(viewExists("all")).toBe(true);
    expect(viewExists("work")).toBe(true);
    expect(viewExists("no-such-list")).toBe(false);
  });

  it("a saved view that is now hidden falls back to Today", () => {
    expect(bundleHtml).toMatch(/if \(!viewExists\(state\.view\)\) \{\s*state\.view = 'today';/);
  });
});
