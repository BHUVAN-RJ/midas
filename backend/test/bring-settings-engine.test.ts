import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { bringEngineToCopy, catalogueForCopy, checkUpgradedCopy, entryFitsCopy } from "../scripts/bring-settings-engine.mjs";
import { findEngineBlock, textOutsideEngine } from "../scripts/settings-engine-tools.mjs";
import { loadToolsScript } from "../scripts/bundle-tools.mjs";

// Existing copies (repair lanes W5, lead 2026-11-13): a base deploy leaves every repaired copy on
// its own version, so scripts/bring-settings-engine.mjs adds the engine to each one, keeping the
// person's changes, and publishes it only when the gate and the shield pass. The real repaired
// copy in the repo, Boomi's Reminders (copies/reminders/boomi, made before the engine), stands in
// for a person's copy.

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

type Upgraded = { html: string; manifestText: string; toolsText: string };

function upgradedBoomi(): Upgraded {
  const brought = bringEngineToCopy({ sidekickId: "reminders", copy: boomi, baseManifest });
  expect(brought.status).toBe("upgraded");
  return brought.upgraded as Upgraded;
}

describe("bringing the engine to a repaired copy", () => {
  it("Boomi's copy was made before the engine", () => {
    expect(findEngineBlock(boomi.html)).toBeNull();
    expect(JSON.parse(boomi.manifestText).settings).toBeUndefined();
  });

  it("adds the engine, the catalogue, set_setting and the schema, and keeps everything of the copy", () => {
    const upgraded = upgradedBoomi();
    const manifest = JSON.parse(upgraded.manifestText);
    const toolNames = manifest.agent.tools.map(function nameOf(tool: { name: string }) {
      return tool.name;
    });
    expect(toolNames).toContain("reminders.set_setting");
    expect(manifest.settings.entries.length).toBeGreaterThan(5);
    for (const entry of manifest.settings.entries) {
      expect(manifest.types["settings:"].schema.properties[entry.key], entry.key).toBeDefined();
    }
    // The person's own changes: every line of their page, tools and tools list is still there
    const originalTools = JSON.parse(boomi.manifestText).agent.tools;
    expect(manifest.agent.tools.slice(0, originalTools.length)).toEqual(originalTools);
    const pageWithoutEngine = textOutsideEngine(upgraded.html);
    const wiringStart = pageWithoutEngine.indexOf("// The person's settings, drawn now");
    const wiringEnd = pageWithoutEngine.indexOf("\n", pageWithoutEngine.indexOf("var settingsWatch", wiringStart)) + 1;
    expect(pageWithoutEngine.slice(0, wiringStart) + pageWithoutEngine.slice(wiringEnd)).toBe(boomi.html);
    const loaded = loadToolsScript(upgraded.toolsText) as { tools?: { handlers: Record<string, unknown> } };
    expect(typeof loaded.tools?.handlers.set_setting).toBe("function");
  });

  it("keeps only the catalogue entries the copy can still honour", () => {
    const { catalogue, dropped } = catalogueForCopy(baseManifest.settings, boomi.html);
    expect(catalogue.entries.length + dropped.length).toBe(baseManifest.settings.entries.length);
    // A copy made before the engine has no date-format code: the page could not honour it
    expect(dropped).toContain("dates.format");
    expect(entryFitsCopy({ key: "x.show", selector: ".gone-part", type: "show" }, "<div class=\"here\">")).toBe(false);
    expect(entryFitsCopy({ key: "x.show", selector: ".here", type: "show" }, "<div class=\"here\">")).toBe(true);
    expect(entryFitsCopy({ key: "accent", type: "colour" }, "settings.accent = x")).toBe(true);
    expect(entryFitsCopy({ key: "accent", type: "colour" }, "nothing")).toBe(false);
  });

  it("does nothing to a copy that has the engine already", () => {
    const upgraded = upgradedBoomi();
    const again = bringEngineToCopy({ sidekickId: "reminders", copy: upgraded, baseManifest });
    expect(again.status).toBe("current");
  });

  it("leaves a copy it cannot work on untouched, with the reason", () => {
    const noHelper = { ...boomi, html: "<html><script>var page = 1;</script></html>" };
    expect(bringEngineToCopy({ sidekickId: "reminders", copy: noHelper, baseManifest })).toMatchObject({ status: "cannot", problem: expect.stringContaining("store helper") });
    const noTools = { ...boomi, toolsText: null };
    expect(bringEngineToCopy({ sidekickId: "reminders", copy: noTools, baseManifest }).status).toBe("cannot");
    const noBaseCatalogue = { ...baseManifest, settings: undefined };
    expect(bringEngineToCopy({ sidekickId: "reminders", copy: boomi, baseManifest: noBaseCatalogue }).status).toBe("cannot");
  });
});

describe("the checks before publishing", () => {
  const records = [
    { key: "list:inbox", value: { $type: "reminders.list", name: "Reminders", color: "#007AFF", createdAt: "2026-10-01T00:00:00.000Z" } },
  ];

  it("passes the deploy gate and the shield (WebKit, Boomi's records) on the upgraded copy", async () => {
    const upgraded = upgradedBoomi();
    const check = await checkUpgradedCopy({ sidekickId: "reminders", before: boomi, after: upgraded, records });
    expect(check.problems).toEqual([]);
    expect(check.ok).toBe(true);
  }, 120000);

  it("refuses an upgrade that breaks the page, so it is never published", async () => {
    const upgraded = upgradedBoomi();
    const wiring = "var settingsWatch = MidasSettings.watch(";
    expect(upgraded.html).toContain(wiring);
    const broken = { ...upgraded, html: upgraded.html.replace(wiring, "throw new Error('engine broke the page');\n" + wiring) };
    const check = await checkUpgradedCopy({ sidekickId: "reminders", before: boomi, after: broken, records });
    expect(check.ok).toBe(false);
    expect(check.problems.length).toBeGreaterThan(0);
  }, 120000);
});
