// A copy's own tests run its page script in Node's vm, with no document (reminders-logic and the
// like). The copies script's generic wiring starts the settings watch only when there is a page:
// unguarded, it threw "document is not defined" in 7 of the founder's Reminder Test copy's 15 test
// files when the engine was brought to it on staging (founder 2026-11-22, under D1 2026-11-13).
// Boomi's Reminders copy (copies/reminders/boomi, made before the engine) stands in for a copy.
import { readFileSync } from "node:fs";
import vm from "node:vm";
import { describe, expect, it } from "vitest";
import { bringEngineToCopy } from "../scripts/bring-settings-engine.mjs";

const repo = new URL("../../", import.meta.url);
function readRepoText(path: string): string {
  return readFileSync(new URL(path, repo), "utf8");
}

const boomi = {
  html: readRepoText("copies/reminders/boomi/sidekick/index.html"),
  manifestText: readRepoText("copies/reminders/boomi/sidekick/manifest.json"),
  toolsText: readRepoText("copies/reminders/boomi/sidekick/tools.js"),
};
const baseManifest = JSON.parse(readRepoText("sidekicks/reminders/manifest.json"));
const GUARD = "typeof document === 'undefined' ? null : ";

function upgradedHtml(): string {
  const brought = bringEngineToCopy({ sidekickId: "reminders", copy: boomi, baseManifest });
  expect(brought.status).toBe("upgraded");
  return (brought.upgraded as { html: string }).html;
}

// The page's inline script in a vm with a window but no document, as the copies' own tests run it
function runWithoutPage(html: string): Record<string, any> {
  const scriptMatch = html.match(/<script>([\s\S]*?)<\/script>/);
  if (!scriptMatch) {
    throw new Error("no inline script");
  }
  const sandbox: Record<string, any> = { window: { location: { origin: "sidekick://reminders" } }, console, Intl, Date, Math, JSON };
  vm.createContext(sandbox);
  vm.runInContext(scriptMatch[1], sandbox);
  return sandbox;
}

describe("bring-settings-engine: the upgraded page still runs without a page", () => {
  it("starts the watch only when there is a document", () => {
    const html = upgradedHtml();
    expect(html).toContain(`var settingsWatch = ${GUARD}MidasSettings.watch(`);
  });

  it("runs in a vm with no document, as the copy's own tests run it", () => {
    const sandbox = runWithoutPage(upgradedHtml());
    expect(sandbox.settingsWatch).toBeNull();
    expect(typeof sandbox.RemindersLogic).toBe("object");
  });

  it("would throw there without the guard", () => {
    const unguarded = upgradedHtml().replace(GUARD, "");
    expect(function runUnguarded() {
      runWithoutPage(unguarded);
    }).toThrow(/document is not defined/);
  });
});
