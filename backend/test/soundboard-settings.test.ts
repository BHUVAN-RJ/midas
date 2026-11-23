// The settings engine in the Sounds Sidekick (soundboard; D1 2026-11-13: the settings engine and
// set_setting are core in every Sidekick; founder 2026-11-22: extend it to Money, Reminder Test and
// Sounds). A person changes a part's colour or size, hides a part or picks light or dark by saying
// it; the values live in settings:self next to the page's own fields (seeded starters, overlap).
// These checks hold the catalogue in manifest.json, the page and tools.js together, check every
// selector names a part the page really draws, and run set_setting and "turned off" on
// real-shaped records.
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import MidasSettings from "../../shell/sdk/midas-settings.js";
import { missingEngineParts } from "../../runner/core-checks/settings-engine.mjs";
import { checkBundleFiles } from "../scripts/bundle-tools.mjs";
import { findEngineBlock, textOutsideEngine } from "../scripts/settings-engine-tools.mjs";
import { loadToolsScript, sidekickToolsProblems } from "../scripts/sidekick-tools.mjs";

const folder = new URL("../../sidekicks/soundboard/", import.meta.url);
const html = readFileSync(new URL("index.html", folder), "utf8");
const toolsText = readFileSync(new URL("tools.js", folder), "utf8");
const manifestText = readFileSync(new URL("manifest.json", folder), "utf8");
const manifest = JSON.parse(manifestText);
const catalogue = manifest.settings;

const loaded = loadToolsScript(toolsText);
if (!("tools" in loaded)) {
  throw new Error(loaded.problem);
}
const tools = loaded.tools;

const NOW = "2026-11-07T20:00:00.000Z";

type Entry = { key: string; type: string; label: string; selector?: string; css?: string | string[]; default: unknown; tools?: string[]; values?: unknown[] };
type Value = Record<string, unknown>;
type Records = Array<{ key: string; value: Value }>;
type Outcome = { ops?: Array<{ op: string; key: string; value?: Value }>; refused?: string; result: { text: string; names?: string[] } };

/* ---------- The page's parts ---------- */

const styleMatch = html.match(/<style>([\s\S]*?)<\/style>/);
if (!styleMatch) {
  throw new Error("index.html has no style block");
}
const pageCss = styleMatch[1];
// The markup and the render code: the page without its style sheet and without the engine (whose
// comments and catalogue name the same classes)
const renderText = textOutsideEngine(html.replace(styleMatch[0], ""));

function escapeForRegExp(text: string) {
  return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function classNamesIn(selector: string) {
  const names: string[] = [];
  for (const match of selector.matchAll(/\.([A-Za-z][A-Za-z0-9_-]*)/g)) {
    names.push(match[1]);
  }
  return names;
}

// A class the render code writes: inside a class attribute or a quoted class string
function renderCodeWritesClass(name: string) {
  return new RegExp(`["' ]${escapeForRegExp(name)}["' ]`).test(renderText);
}

function styleSheetStylesClass(name: string) {
  return new RegExp(`\\.${escapeForRegExp(name)}(?![A-Za-z0-9_-])`).test(pageCss);
}

// The custom properties a CSS block declares: { "--bg": "#FFFFFF", ... }
function declarationsIn(block: string) {
  const declarations: Record<string, string> = {};
  for (const match of block.matchAll(/(--[a-z0-9-]+):\s*([^;]+);/g)) {
    declarations[match[1]] = match[2].trim();
  }
  return declarations;
}

function blockAfter(marker: string) {
  const start = pageCss.indexOf(marker);
  if (start === -1) {
    throw new Error(`no ${marker} in the style sheet`);
  }
  const open = pageCss.indexOf("{", start + marker.length - 1);
  const close = pageCss.indexOf("}", open);
  return pageCss.slice(open + 1, close);
}

function cssListOf(entry: Entry) {
  if (Array.isArray(entry.css)) {
    return entry.css;
  }
  return typeof entry.css === "string" ? [entry.css] : [];
}

function entry(key: string) {
  return (catalogue.entries as Entry[]).find(function hasKey(candidate) {
    return candidate.key === key;
  });
}

/* ---------- Tools ---------- */

function baseRecords(settingsFields: Value = {}): Records {
  return [
    { key: "settings:self", value: { $type: "soundboard.settings", seeded: ["fahh", "boom"], overlap: true, createdAt: "2026-11-07T18:00:00.000Z", ...settingsFields } },
    { key: "sound:boom", value: { $type: "soundboard.sound", name: "Vine Boom", tags: ["boom", "rock"], audio: "file:boomaudio001", image: "file:boomimage001", order: 2, starter: "boom", createdAt: "2026-11-07T18:00:02.000Z" } },
    { key: "sound:fahh", value: { $type: "soundboard.sound", name: "Fahh", tags: ["fah", "fail"], audio: "file:fahhaudio001", image: "file:fahhimage001", order: 1, starter: "fahh", createdAt: "2026-11-07T18:00:00.000Z" } },
  ];
}

function call(verb: string, input: Value, records: Records): Outcome {
  return JSON.parse(JSON.stringify(tools.handlers[verb](input, records, NOW)));
}

function settingsWritten(outcome: Outcome) {
  const op = (outcome.ops || []).find(function isSettingsOp(candidate) {
    return candidate.key === "settings:self";
  });
  return op ? op.value : undefined;
}

// The shell's write gate: each set must fit its key's type in manifest.json
function expectSchemaValid(outcome: Outcome) {
  expect(outcome.refused).toBeUndefined();
  for (const op of outcome.ops || []) {
    if (op.op === "set") {
      const stamped = MidasRecordSchema.stampType(manifest.types, op.key, op.value);
      expect(MidasRecordSchema.checkRecord(manifest.types, op.key, stamped), op.key).toBeNull();
    }
  }
}

describe("Sounds settings: the catalogue", () => {
  it("is a valid catalogue of 25 to 50 settings", () => {
    expect(MidasSettings.catalogueProblems(catalogue)).toEqual([]);
    expect(catalogue.entries.length).toBeGreaterThanOrEqual(25);
    expect(catalogue.entries.length).toBeLessThanOrEqual(50);
  });

  it("has a clear background, main colour and text size for vague words, first in the list", () => {
    const keys = (catalogue.entries as Entry[]).map(function keyOf(candidate) {
      return candidate.key;
    });
    expect(keys.slice(0, 6)).toEqual(expect.arrayContaining(["page.colour", "accent.colour", "text.colour", "page.size"]));
    expect(entry("page.colour")!.label).toBe("Background colour");
    expect(entry("accent.colour")!.label).toMatch(/^Main colour/);
    expect(entry("page.size")!.label).toMatch(/^Text size/);
  });

  it("offers light or dark, following the phone until set; no date format, since the page shows no dates", () => {
    expect(entry("page.theme")).toMatchObject({ type: "choice", values: ["auto", "light", "dark"], default: "auto" });
    expect(entry("dates.format")).toBeUndefined();
  });

  it("is the same in the page, in tools.js and in manifest.json", () => {
    expect(findEngineBlock(html)!.catalogue).toEqual(catalogue);
    expect(findEngineBlock(toolsText)!.catalogue).toEqual(catalogue);
    expect(findEngineBlock(html)!.engineText).toBe(readFileSync(new URL("../../shell/sdk/midas-settings.js", import.meta.url), "utf8").trim());
  });

  it("gives each setting its schema in settings:self, next to the page's own fields", () => {
    const properties = manifest.types["settings:"].schema.properties;
    for (const candidate of catalogue.entries as Entry[]) {
      expect(properties[candidate.key], candidate.key).toEqual(MidasSettings.propertySchemaFor(candidate));
    }
    expect(properties.overlap).toEqual({ type: "boolean" });
    expect(properties.seeded.type).toBe("array");
  });

  it("names only real tools as turned off by a hidden part", () => {
    const toolNames = manifest.agent.tools.map(function nameOf(tool: { name: string }) {
      return tool.name;
    });
    for (const candidate of catalogue.entries as Entry[]) {
      for (const toolName of candidate.tools || []) {
        expect(toolNames, candidate.key).toContain(toolName);
      }
    }
  });

  it("passes the deploy gate and has every engine part the shield requires", () => {
    expect(checkBundleFiles(html, manifestText, "soundboard", toolsText).problems).toEqual([]);
    expect(sidekickToolsProblems(manifest, toolsText, html, "soundboard")).toEqual([]);
    expect(typeof tools.handlers.set_setting).toBe("function");
    expect(missingEngineParts({ sidekickId: "soundboard", copy: { manifest, html, loadedTools: loaded } })).toEqual([]);
  });

  it("keeps SoundsLogic as the first copied block in tools.js, the engine after it", () => {
    const logicAt = toolsText.indexOf("var SoundsLogic = (function createSoundsLogic() {");
    expect(logicAt).toBeGreaterThan(-1);
    expect(findEngineBlock(toolsText)!.start).toBeGreaterThan(logicAt);
  });
});

describe("Sounds settings: every selector is a part the page draws", () => {
  for (const candidate of catalogue.entries as Entry[]) {
    if (typeof candidate.selector !== "string") {
      continue;
    }
    it(`${candidate.key} (${candidate.selector})`, () => {
      const isRootOnly = candidate.selector!.trim() === ":root";
      const isIdOnly = /^#[A-Za-z][A-Za-z0-9_-]*$/.test(candidate.selector!.trim());
      const names = classNamesIn(candidate.selector!);
      expect(isRootOnly || isIdOnly || names.length > 0).toBe(true);
      if (isIdOnly) {
        const id = candidate.selector!.trim().slice(1);
        expect(pageCss).toContain(`#${id} `);
        expect(html).toContain(`id="${id}"`);
      }
      for (const name of names) {
        expect(styleSheetStylesClass(name), `.${name} in the style sheet`).toBe(true);
        expect(renderCodeWritesClass(name), `.${name} written by the page`).toBe(true);
      }
    });
  }

  it("sets only custom properties the style sheet uses, with the page's own light colour as default", () => {
    const lightRoot = declarationsIn(blockAfter(":root {"));
    for (const candidate of catalogue.entries as Entry[]) {
      if (candidate.type !== "colour") {
        continue;
      }
      for (const property of cssListOf(candidate)) {
        if (!property.startsWith("--")) {
          continue;
        }
        expect(pageCss.includes(`var(${property}`), `${candidate.key}: var(${property}) used`).toBe(true);
        expect(lightRoot[property], `${candidate.key}: ${property} on :root`).toBeDefined();
        if (/^#[0-9A-Fa-f]{6}$/.test(lightRoot[property])) {
          expect(String(candidate.default).toUpperCase(), candidate.key).toBe(lightRoot[property].toUpperCase());
        }
      }
    }
  });

  it("draws nothing until a setting is changed, then a rule for that part", () => {
    expect(MidasSettings.cssFor(catalogue, { $type: "soundboard.settings", seeded: ["fahh"], overlap: true })).toBe("");
    const css = MidasSettings.cssFor(catalogue, { "accent.colour": "#FF2D55", "names.show": false });
    expect(css).toContain(":root { --playing: #FF2D55 !important; }");
    expect(css).toContain(".tile .name { display: none !important; }");
  });
});

describe("Sounds settings: the page watches settings:self", () => {
  it("starts the watch in start and applies light or dark, first read included", () => {
    const startBody = html.slice(html.indexOf("  function start() {"), html.indexOf("  function start() {") + 400);
    expect(startBody).toContain("MidasSettings.watch({ catalogue: SETTINGS_CATALOGUE, read: readSettingsRecord, onChange: applyTheme })");
    expect(startBody).toContain("settingsWatch.ready.then(applyTheme)");
    const themeBody = html.slice(html.indexOf("  function applyTheme() {"), html.indexOf("  function applyTheme() {") + 500);
    expect(themeBody).toContain("values['page.theme']");
    expect(themeBody).toContain("setAttribute('data-theme', theme)");
    expect(themeBody).toContain("removeAttribute('data-theme')");
  });

  it("has light and dark blocks that set every colour the phone's dark mode sets", () => {
    const darkMedia = declarationsIn(blockAfter("@media (prefers-color-scheme: dark) {\n  :root {"));
    const lightRoot = declarationsIn(blockAfter(":root {"));
    const lightTheme = declarationsIn(blockAfter(':root[data-theme="light"] {'));
    expect(declarationsIn(blockAfter(':root[data-theme="dark"] {'))).toEqual(darkMedia);
    for (const property of Object.keys(darkMedia)) {
      expect(lightTheme[property], property).toBe(lightRoot[property]);
    }
  });
});

describe("Sounds settings: set_setting", () => {
  it("writes the setting into settings:self and keeps the seeded starters and overlap", () => {
    const outcome = call("set_setting", { key: "accent.colour", value: "#ff2d55" }, baseRecords());
    expectSchemaValid(outcome);
    expect(outcome.ops).toHaveLength(1);
    expect(settingsWritten(outcome)).toEqual({ $type: "soundboard.settings", seeded: ["fahh", "boom"], overlap: true, createdAt: "2026-11-07T18:00:00.000Z", "accent.colour": "#FF2D55" });
  });

  it("keeps the person's settings when overlap is changed afterwards", () => {
    const outcome = call("set_overlap", { overlap: false }, baseRecords({ "page.theme": "dark", "tiles.size": "l" }));
    expectSchemaValid(outcome);
    const written = settingsWritten(outcome)!;
    expect(written.overlap).toBe(false);
    expect(written["page.theme"]).toBe("dark");
    expect(written["tiles.size"]).toBe("l");
  });

  it("refuses a value the setting does not take, and a setting that does not exist", () => {
    expect(call("set_setting", { key: "names.size", value: "huge" }, baseRecords()).refused).toBe("value-not-offered");
    expect(call("set_setting", { key: "overlap", value: "on" }, baseRecords()).refused).toBe("nothing-to-change");
  });
});

describe("Sounds settings: a hidden feature's tools answer turned off", () => {
  it("a hidden search box turns off search, and nothing else", () => {
    const records = baseRecords({ "search.show": false });
    const searched = call("search", { query: "boom" }, records);
    expect(searched.refused).toBe("turned-off");
    expect(searched.result.text).toBe("Search box is turned off");
    const listed = call("list", {}, records);
    expect(listed.refused).toBeUndefined();
    expect(listed.result.names).toEqual(["Fahh", "Vine Boom"]);
  });

  it("works again once the search box is shown", () => {
    const searched = call("search", { query: "boom" }, baseRecords({ "search.show": true }));
    expect(searched.refused).toBeUndefined();
    expect(searched.result.names).toEqual(["Vine Boom"]);
  });
});
