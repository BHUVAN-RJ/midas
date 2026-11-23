// The settings engine in the Money Sidekick (D1 2026-11-13: the settings engine and set_setting are
// core in every Sidekick; founder 2026-11-22: extend it to Money, Reminder Test and Sounds). A
// person changes a part's colour or size, hides a part, picks a date format or light or dark by
// saying it; the values live in settings:self. These checks hold the catalogue in manifest.json,
// the page and tools.js together, check every selector names a part the page really draws, and run
// set_setting and "turned off" on real-shaped records.
process.env.TZ = "America/Los_Angeles";

import { readFileSync } from "node:fs";
import vm from "node:vm";
import { describe, expect, it } from "vitest";
import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import MidasSettings from "../../shell/sdk/midas-settings.js";
import { missingEngineParts } from "../../runner/core-checks/settings-engine.mjs";
import { findEngineBlock, textOutsideEngine } from "../scripts/settings-engine-tools.mjs";
import { loadToolsScript, sidekickToolsProblems } from "../scripts/sidekick-tools.mjs";

const folder = new URL("../../sidekicks/money/", import.meta.url);
const html = readFileSync(new URL("index.html", folder), "utf8");
const toolsText = readFileSync(new URL("tools.js", folder), "utf8");
const manifest = JSON.parse(readFileSync(new URL("manifest.json", folder), "utf8"));
const catalogue = manifest.settings;

const loaded = loadToolsScript(toolsText);
if (!("tools" in loaded)) {
  throw new Error(loaded.problem);
}
const tools = loaded.tools;

// Saturday Nov 7, 2026, 14:00 in Los Angeles
const NOW = "2026-11-07T22:00:00.000Z";

type Entry = { key: string; type: string; label: string; selector?: string; css?: string | string[]; default: unknown; tools?: string[]; values?: unknown[] };
type Value = Record<string, unknown>;
type Records = Array<{ key: string; value: Value }>;
type Outcome = { ops?: Array<{ op: string; key: string; value?: Value }>; refused?: string; result: { text: string } };

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

function expense(fields: Value = {}): Value {
  return { $type: "money.expense", amountCents: 1200, currency: "USD", merchant: "Starbucks", date: "2026-11-06", category: "Dining", createdAt: "2026-11-06T16:00:00.000Z", ...fields };
}

function baseRecords(settings?: Value): Records {
  const records: Records = [
    { key: "expense:a1", value: expense({ merchant: "Corner Market", category: "Groceries", amountCents: 4218, date: "2026-11-02", createdAt: "2026-11-02T20:00:00.000Z" }) },
    { key: "expense:a2", value: expense() },
  ];
  if (settings) {
    records.push({ key: "settings:self", value: settings });
  }
  return records;
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

/* ---------- The page's look code, run without a screen ---------- */

function loadLookScript() {
  const engine = findEngineBlock(html);
  if (engine === null) {
    throw new Error("index.html has no settings engine");
  }
  const lookStart = html.indexOf("var MoneySettingsLook = (function createMoneySettingsLook() {");
  const lookEnd = html.indexOf("\n})();\n", lookStart) + "\n})();\n".length;
  const sandbox: Record<string, any> = { console, Date, Math, JSON };
  vm.createContext(sandbox);
  vm.runInContext(html.slice(engine.start, engine.end) + html.slice(lookStart, lookEnd) + "\nthis.MoneySettingsLook = MoneySettingsLook;", sandbox);
  return sandbox.MoneySettingsLook;
}

describe("Money settings: the catalogue", () => {
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

  it("offers light or dark and one date format, both following the page until set", () => {
    expect(entry("page.theme")).toMatchObject({ type: "choice", values: ["auto", "light", "dark"], default: "auto" });
    const dateEntries = (catalogue.entries as Entry[]).filter(function isDateFormat(candidate) {
      return candidate.type === "dateFormat";
    });
    expect(dateEntries.map(function keyOf(candidate) {
      return candidate.key;
    })).toEqual(["dates.format"]);
    expect(dateEntries[0].default).toBe("auto");
  });

  it("is the same in the page, in tools.js and in manifest.json", () => {
    expect(findEngineBlock(html)!.catalogue).toEqual(catalogue);
    expect(findEngineBlock(toolsText)!.catalogue).toEqual(catalogue);
    expect(findEngineBlock(html)!.engineText).toBe(readFileSync(new URL("../../shell/sdk/midas-settings.js", import.meta.url), "utf8").trim());
  });

  it("gives each setting its schema in settings:self", () => {
    const properties = manifest.types["settings:"].schema.properties;
    for (const candidate of catalogue.entries as Entry[]) {
      expect(properties[candidate.key], candidate.key).toEqual(MidasSettings.propertySchemaFor(candidate));
    }
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

  it("passes the deploy gate's tools check and has every engine part the shield requires", () => {
    expect(sidekickToolsProblems(manifest, toolsText, html, "money")).toEqual([]);
    expect(typeof tools.handlers.set_setting).toBe("function");
    expect(missingEngineParts({ sidekickId: "money", copy: { manifest, html, loadedTools: loaded } })).toEqual([]);
  });

  it("keeps MoneyLogic as the first copied block in tools.js, the engine after it", () => {
    const logicAt = toolsText.indexOf("var MoneyLogic = (function createMoneyLogic() {");
    const engineAt = findEngineBlock(toolsText)!.start;
    expect(logicAt).toBeGreaterThan(-1);
    expect(engineAt).toBeGreaterThan(logicAt);
  });

  it("keeps the person's repair facts", () => {
    const keep = manifest.repair.keep.join("\n");
    expect(keep).toContain("integer cents");
    expect(keep).toContain('"midas/photo": "receipt"');
    expect(keep).toContain("Nothing is written when the page opens.");
  });
});

describe("Money settings: every selector is a part the page draws", () => {
  for (const candidate of catalogue.entries as Entry[]) {
    if (typeof candidate.selector !== "string") {
      continue;
    }
    it(`${candidate.key} (${candidate.selector})`, () => {
      const names = classNamesIn(candidate.selector!);
      const isRootOnly = candidate.selector!.trim() === ":root";
      expect(isRootOnly || names.length > 0).toBe(true);
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
        const built = lightRoot[property];
        expect(built, `${candidate.key}: ${property} on :root`).toBeDefined();
        if (/^#[0-9A-Fa-f]{6}$/.test(built)) {
          expect(String(candidate.default).toUpperCase(), candidate.key).toBe(built.toUpperCase());
        }
      }
    }
  });

  it("draws nothing until a setting is changed, then a rule for that part", () => {
    expect(MidasSettings.cssFor(catalogue, {})).toBe("");
    const css = MidasSettings.cssFor(catalogue, { "accent.colour": "#2F6FEB", "bar.show": false, "page.size": "l" });
    expect(css).toContain(":root { --accent: #2F6FEB !important; }");
    expect(css).toContain(".stack { display: none !important; }");
    expect(css).toContain(".screen { zoom: 1.2 !important; }");
  });
});

describe("Money settings: the page watches settings:self", () => {
  it("starts the watch in start and redraws on a change", () => {
    const startBody = html.slice(html.indexOf("  async function start() {"), html.indexOf("\n  start();\n"));
    expect(startBody).toContain("MidasSettings.watch({ catalogue: SETTINGS_CATALOGUE, read: readSettingsRecord, onChange: handleSettingsChange })");
    expect(startBody).toContain("await settingsWatch.ready;");
    const changeBody = html.slice(html.indexOf("  function handleSettingsChange() {"), html.indexOf("  function handleSettingsChange() {") + 120);
    expect(changeBody).toContain("applyTheme();");
    expect(changeBody).toContain("render();");
  });

  it("writes the expense dates through the person's date format", () => {
    expect(renderText).toContain("shownDayLabel(value.date, now)");
    expect(renderText).toContain("shownFullDate(value.date)");
    expect(renderText).not.toContain("+ Logic.dayLabel(value.date, now) +");
    expect(renderText).not.toContain("+ Logic.fullDateLabel(value.date) +");
  });

  it("colours the categories by the chosen light or dark, not only the phone's", () => {
    expect(renderText).toContain("return isDark() ? pair[1] : pair[0];");
    expect(renderText.match(/darkQuery\.matches/g)).toHaveLength(1);
  });

  it("has light and dark blocks that set every colour the phone's dark mode sets", () => {
    const darkMedia = declarationsIn(blockAfter("@media (prefers-color-scheme: dark) {\n  :root {"));
    const lightRoot = declarationsIn(blockAfter(":root {"));
    expect(declarationsIn(blockAfter(':root[data-theme="dark"] {'))).toEqual(darkMedia);
    expect(declarationsIn(blockAfter(':root[data-theme="light"] {'))).toEqual(lightRoot);
  });
});

describe("Money settings: dates and light or dark, run without a screen", () => {
  const look = loadLookScript();

  it("leaves the page's own date while the format is auto", () => {
    expect(look.chosenDate(null, "2026-11-13")).toBeNull();
    expect(look.chosenDate({ "dates.format": "auto" }, "2026-11-13")).toBeNull();
    expect(look.chosenDate({ "dates.format": "sideways" }, "2026-11-13")).toBeNull();
  });

  it("writes the day in the chosen format, on the right day", () => {
    expect(look.chosenDate({ "dates.format": "month-day-year" }, "2026-11-13")).toBe("Nov 13, 2026");
    expect(look.chosenDate({ "dates.format": "numeric-day-first" }, "2026-01-02")).toBe("02/01/2026");
  });

  it("reads light or dark, auto when unset or not offered", () => {
    expect(look.themeOf(null)).toBe("auto");
    expect(look.themeOf({ "page.theme": "dark" })).toBe("dark");
    expect(look.themeOf({ "page.theme": "purple" })).toBe("auto");
  });
});

describe("Money settings: set_setting", () => {
  it("writes the first settings:self, and it passes the write gate", () => {
    const outcome = call("set_setting", { key: "accent.colour", value: "#2f6feb" }, baseRecords());
    expectSchemaValid(outcome);
    expect(outcome.ops).toHaveLength(1);
    expect(settingsWritten(outcome)).toEqual({ "accent.colour": "#2F6FEB" });
  });

  it("keeps the settings already there", () => {
    const outcome = call("set_setting", { key: "page.theme", value: "dark" }, baseRecords({ $type: "money.settings", "page.colour": "#FFF8E7" }));
    expectSchemaValid(outcome);
    expect(settingsWritten(outcome)).toEqual({ $type: "money.settings", "page.colour": "#FFF8E7", "page.theme": "dark" });
  });

  it("turns a part off with a person's word", () => {
    const outcome = call("set_setting", { key: "percentages.show", value: "hide" }, baseRecords());
    expectSchemaValid(outcome);
    expect(settingsWritten(outcome)!["percentages.show"]).toBe(false);
  });

  it("refuses a value the setting does not take, and a setting that does not exist", () => {
    expect(call("set_setting", { key: "total.size", value: "huge" }, baseRecords()).refused).toBe("value-not-offered");
    expect(call("set_setting", { key: "page.theme", value: "purple" }, baseRecords()).refused).toBe("value-not-offered");
    expect(call("set_setting", { key: "currency", value: "EUR" }, baseRecords()).refused).toBe("nothing-to-change");
  });
});

describe("Money settings: a hidden feature's tools answer turned off", () => {
  it("a hidden Delete Expense button turns off delete_expense only", () => {
    const records = baseRecords({ "deleteButton.show": false });
    const deleted = call("delete_expense", { which: "Starbucks", amount: null }, records);
    expect(deleted.refused).toBe("turned-off");
    expect(deleted.ops).toBeUndefined();
    expect(deleted.result.text).toBe("Delete Expense button is turned off");
    const added = call("add_expense", { amount: 4.5, merchant: "Blue Bottle", date: null, daysAgo: null, category: "Dining", items: null, tax: null, tip: null }, records);
    expectSchemaValid(added);
    expect(added.ops!.length).toBeGreaterThan(0);
  });

  it("works again once the button is shown", () => {
    const deleted = call("delete_expense", { which: "Starbucks", amount: null }, baseRecords({ "deleteButton.show": true }));
    expect(deleted.refused).toBeUndefined();
    expect(deleted.ops).toEqual([{ op: "delete", key: "expense:a2" }]);
  });
});
