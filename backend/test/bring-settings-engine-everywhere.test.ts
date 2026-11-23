// The copies script reaches every Sidekick with a catalogue (founder 2026-11-22, under D1
// 2026-11-13: the settings engine and set_setting are core in every Sidekick). Money, Reminder Test
// and Sounds now carry a catalogue, so bring-settings-engine.mjs walks them with the other four,
// accepts them by --sidekick, and the shield holds their copies to having the engine.
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { baseHasSettingsCatalogue } from "../../runner/core-checks/shield.mjs";
import { LIVE_REFUSAL, bringEngineToCopy, refusalForEnvironment, sidekicksWithCatalogue } from "../scripts/bring-settings-engine.mjs";

const checkoutRoot = new URL("../../", import.meta.url).pathname;
const NEW_ENGINE_SIDEKICKS = ["money", "reminder-test", "soundboard"];

function baseFiles(sidekickId: string) {
  const folder = new URL(`../../sidekicks/${sidekickId}/`, import.meta.url);
  return {
    html: readFileSync(new URL("index.html", folder), "utf8"),
    manifestText: readFileSync(new URL("manifest.json", folder), "utf8"),
    toolsText: readFileSync(new URL("tools.js", folder), "utf8"),
  };
}

describe("bring-settings-engine: every Sidekick with a catalogue", () => {
  it("walks all seven Sidekicks, Money, Reminder Test and Sounds included", () => {
    expect(sidekicksWithCatalogue()).toEqual(["care-reminders", "hydration", "money", "reminder-test", "reminders", "soundboard", "todo"]);
  });

  it("finds a copy that already has the engine current, for each of the three", () => {
    for (const sidekickId of NEW_ENGINE_SIDEKICKS) {
      const copy = baseFiles(sidekickId);
      const brought = bringEngineToCopy({ sidekickId, copy, baseManifest: JSON.parse(copy.manifestText) });
      expect(brought.status, sidekickId).toBe("current");
    }
  });

  it("cannot upgrade against a base that has no catalogue", () => {
    const copy = baseFiles("money");
    const baseManifest = JSON.parse(copy.manifestText);
    delete baseManifest.settings;
    expect(bringEngineToCopy({ sidekickId: "money", copy, baseManifest }).status).toBe("cannot");
  });

  it("holds the three Sidekicks' copies to the engine in the shield", () => {
    for (const sidekickId of NEW_ENGINE_SIDEKICKS) {
      expect(baseHasSettingsCatalogue(checkoutRoot, sidekickId), sidekickId).toBe(true);
    }
  });

  it("still refuses live", () => {
    expect(refusalForEnvironment({ name: "live" })).toBe(LIVE_REFUSAL);
    expect(refusalForEnvironment({ name: "staging" })).toBeNull();
  });
});
