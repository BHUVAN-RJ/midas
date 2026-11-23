import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { SETTINGS_ENGINE_IN_EVERY_SIDEKICK, baseHasSettingsCatalogue } from "../../runner/core-checks/shield.mjs";
import { checkSettingsEngine, missingEngineParts } from "../../runner/core-checks/settings-engine.mjs";
import { loadToolsScript } from "../scripts/bundle-tools.mjs";

// After W5 (repair lanes, founder D1 2026-11-13) the settings engine is in Reminders, Care, Water and
// To-Do, and since 2026-11-22 (founder) in Money, Reminder Test and Sounds too, so the shield fails a
// copy of one of them without it. A Sidekick whose base has no catalogue is only held to "never lose it".

const checkoutRoot = fileURLToPath(new URL("../../", import.meta.url));
const ENGINE_SIDEKICKS = ["reminders", "care-reminders", "hydration", "todo", "money", "reminder-test", "soundboard"];

function baseCopy(sidekickId: string) {
  const folder = new URL(`../../sidekicks/${sidekickId}/`, import.meta.url);
  const toolsText = readFileSync(new URL("tools.js", folder), "utf8");
  return {
    manifest: JSON.parse(readFileSync(new URL("manifest.json", folder), "utf8")),
    html: readFileSync(new URL("index.html", folder), "utf8"),
    loadedTools: loadToolsScript(toolsText),
  };
}

describe("the shield after W5", () => {
  it("requires the engine everywhere it was built", () => {
    expect(SETTINGS_ENGINE_IN_EVERY_SIDEKICK).toBe(true);
  });

  it("every base W5 covers has all four engine parts and a catalogue", () => {
    for (const sidekickId of ENGINE_SIDEKICKS) {
      expect(missingEngineParts({ sidekickId, copy: baseCopy(sidekickId) }), sidekickId).toEqual([]);
      expect(baseHasSettingsCatalogue(checkoutRoot, sidekickId), sidekickId).toBe(true);
    }
  });

  it("holds a Sidekick with no base catalogue only to never losing it, and Money now has one", () => {
    // No base catalogue: the engine is not required, only never lost
    expect(baseHasSettingsCatalogue(checkoutRoot, "no-such-sidekick")).toBe(false);
    // Money's base gained a catalogue on 2026-11-22 (founder), so its copies need the engine
    expect(baseHasSettingsCatalogue(checkoutRoot, "money")).toBe(true);
  });

  it("fails a W5 Sidekick's copy that has no engine (a copy made before W5)", () => {
    const boomiFolder = new URL("../../copies/reminders/boomi/sidekick/", import.meta.url);
    const boomi = {
      manifest: JSON.parse(readFileSync(new URL("manifest.json", boomiFolder), "utf8")),
      html: readFileSync(new URL("index.html", boomiFolder), "utf8"),
      loadedTools: loadToolsScript(readFileSync(new URL("tools.js", boomiFolder), "utf8")),
    };
    const everyEngine = SETTINGS_ENGINE_IN_EVERY_SIDEKICK && baseHasSettingsCatalogue(checkoutRoot, "reminders");
    const outcome = checkSettingsEngine({ sidekickId: "reminders", before: boomi, after: boomi, everyEngine });
    expect(outcome.problems.join(" ")).toContain("the settings engine is missing");
  });
});
