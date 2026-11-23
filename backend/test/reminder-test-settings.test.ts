// The settings engine in the Reminder Test Sidekick (D1 2026-11-13: the settings engine and
// set_setting are core in every Sidekick; founder 2026-11-22: extend it to Money, Reminder Test and
// Sounds). Reminder Test is the Reminders page under its own id, so it carries the Reminders
// catalogue (same parts, same keys, its own tool names) plus light or dark. These checks hold the
// catalogue in manifest.json, the page and tools.js together, check every selector names a part
// the page really draws, and run set_setting and "turned off" on real-shaped records.
process.env.TZ = "America/Los_Angeles";

import { readFileSync } from "node:fs";
import vm from "node:vm";
import { describe, expect, it } from "vitest";
import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import MidasSettings from "../../shell/sdk/midas-settings.js";
import { missingEngineParts } from "../../runner/core-checks/settings-engine.mjs";
import { findEngineBlock, textOutsideEngine } from "../scripts/settings-engine-tools.mjs";
import { loadToolsScript, sidekickToolsProblems } from "../scripts/sidekick-tools.mjs";

const folder = new URL("../../sidekicks/reminder-test/", import.meta.url);
const html = readFileSync(new URL("index.html", folder), "utf8");
const toolsText = readFileSync(new URL("tools.js", folder), "utf8");
const manifest = JSON.parse(readFileSync(new URL("manifest.json", folder), "utf8"));
const catalogue = manifest.settings;
const remindersManifest = JSON.parse(readFileSync(new URL("../../sidekicks/reminders/manifest.json", import.meta.url), "utf8"));

const loaded = loadToolsScript(toolsText);
if (!("tools" in loaded)) {
  throw new Error(loaded.problem);
}
const tools = loaded.tools;

const LA = "America/Los_Angeles";
const NOW = "2026-10-20T17:00:00.000Z";
const LIST_ORDER = ["today", "next7", "scheduled", "unscheduled", "all", "pastDue", "completed", "work"];

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

// The body of a function in the page's script, up to the next function at the same depth
function functionBody(name: string) {
  const start = html.indexOf(`  function ${name}(`);
  if (start === -1) {
    throw new Error(`index.html has no function ${name}`);
  }
  return html.slice(start, html.indexOf("\n  }\n", start));
}

/* ---------- Tools ---------- */

function baseRecords(settingsValue?: Value): Records {
  const settings = settingsValue || { $type: "reminder-test.settings", order: LIST_ORDER.slice() };
  return [
    { key: "list:work", value: { $type: "reminder-test.list", name: "Work", color: "#007AFF", icon: "briefcase", createdAt: "2026-10-01T00:00:00.000Z" } },
    { key: "settings:self", value: settings },
    { key: "reminder:callmom00001", value: { $type: "reminder-test.item", title: "Call Mom", done: false, timeZone: LA, at: "2026-10-21T01:00:00.000Z", allDay: false, createdAt: "2026-10-10T00:00:00.000Z" } },
    { key: "reminder:dentist00001", value: { $type: "reminder-test.item", title: "Dentist", done: true, completedAt: "2026-10-15T00:00:00.000Z", timeZone: LA, createdAt: "2026-10-12T00:00:00.000Z" } },
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

/* ---------- The page's date code, run without a screen ---------- */

function loadPageScript() {
  const scriptMatch = html.match(/<script>([\s\S]*?)<\/script>/);
  if (!scriptMatch) {
    throw new Error("index.html has no inline script");
  }
  const sandbox = { window: { location: { origin: "sidekick://reminder-test" } }, console, Intl, Date, Math, JSON };
  vm.createContext(sandbox);
  vm.runInContext(scriptMatch[1], sandbox);
  return sandbox as Record<string, any>;
}

describe("Reminder Test settings: the catalogue", () => {
  it("is a valid catalogue of 25 to 50 settings", () => {
    expect(MidasSettings.catalogueProblems(catalogue)).toEqual([]);
    expect(catalogue.entries.length).toBeGreaterThanOrEqual(25);
    expect(catalogue.entries.length).toBeLessThanOrEqual(50);
  });

  it("is the Reminders catalogue under its own tool names, plus light or dark", () => {
    const expected = JSON.parse(JSON.stringify(remindersManifest.settings.entries)) as Entry[];
    for (const remindersEntry of expected) {
      if (remindersEntry.tools) {
        remindersEntry.tools = remindersEntry.tools.map(function ownName(toolName) {
          return toolName.replace(/^reminders\./, "reminder-test.");
        });
      }
    }
    const withoutTheme = (catalogue.entries as Entry[]).filter(function isNotTheme(candidate) {
      return candidate.key !== "page.theme";
    });
    expect(withoutTheme).toEqual(expected);
    expect(entry("page.theme")).toMatchObject({ type: "choice", values: ["auto", "light", "dark"], default: "auto" });
  });

  it("has a clear background, main colour and text size for vague words, first in the list", () => {
    const keys = (catalogue.entries as Entry[]).map(function keyOf(candidate) {
      return candidate.key;
    });
    expect(keys.slice(0, 6)).toEqual(expect.arrayContaining(["page.colour", "accent.colour", "text.colour", "page.size"]));
    expect(entry("page.colour")!.label).toBe("Background colour");
    expect(entry("accent.colour")!.label).toMatch(/^Main colour/);
    expect(entry("reminderText.size")!.label).toBe("Reminder text size");
  });

  it("is the same in the page, in tools.js and in manifest.json", () => {
    expect(findEngineBlock(html)!.catalogue).toEqual(catalogue);
    expect(findEngineBlock(toolsText)!.catalogue).toEqual(catalogue);
    expect(findEngineBlock(html)!.engineText).toBe(readFileSync(new URL("../../shell/sdk/midas-settings.js", import.meta.url), "utf8").trim());
  });

  it("gives each setting its schema in settings:self, next to the list order", () => {
    const properties = manifest.types["settings:"].schema.properties;
    for (const candidate of catalogue.entries as Entry[]) {
      expect(properties[candidate.key], candidate.key).toEqual(MidasSettings.propertySchemaFor(candidate));
    }
    expect(properties.order).toEqual({ type: "array", maxItems: 200, items: { type: "string", maxLength: 200 } });
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
    expect(sidekickToolsProblems(manifest, toolsText, html, "reminder-test")).toEqual([]);
    expect(typeof tools.handlers.set_setting).toBe("function");
    expect(missingEngineParts({ sidekickId: "reminder-test", copy: { manifest, html, loadedTools: loaded } })).toEqual([]);
  });
});

describe("Reminder Test settings: every selector is a part the page draws", () => {
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
        if (candidate.selector === ":root") {
          expect(String(candidate.default).toUpperCase(), candidate.key).toBe(lightRoot[property].toUpperCase());
        }
      }
    }
  });

  it("draws nothing until a setting is changed, then a rule for that part", () => {
    expect(MidasSettings.cssFor(catalogue, { $type: "reminder-test.settings", order: LIST_ORDER })).toBe("");
    const css = MidasSettings.cssFor(catalogue, { "circles.colour": "#FF9500", "notes.show": false });
    expect(css).toContain(".circle { --c: #FF9500 !important; }");
    expect(css).toContain(".row-notes { display: none !important; }");
  });
});

describe("Reminder Test settings: the page watches settings:self", () => {
  it("starts the watch with the page's own read of settings:self and redraws on a change", () => {
    expect(functionBody("start")).toContain("MidasSettings.watch({ catalogue: SETTINGS_CATALOGUE, read: readSettings, onChange: handleSettingsChange })");
    expect(functionBody("start")).toContain("settingsWatch.ready.then(handleSettingsChange)");
    expect(functionBody("readSettings")).toContain("store.get(SETTINGS_KEY)");
    expect(functionBody("handleSettingsChange")).toContain("applyTheme();");
    expect(functionBody("handleSettingsChange")).toContain("requestRender()");
    expect(functionBody("applyTheme")).toContain("['page.theme']");
  });

  it("writes every date it shows through the person's date format", () => {
    const dateFunctions = ["formatDayLabel", "formatLongKey", "formatLongDate", "formatDayMonth", "formatRange", "weekDayHeaderHTML"];
    for (const name of dateFunctions) {
      expect(functionBody(name), name).toMatch(/chosenDateText\(|formatDayMonth\(/);
    }
    expect(functionBody("chosenDateText")).toContain("RemindersSettingsDates.chosenText(");
  });

  it("keeps the list order and the settings together when the page saves the order", () => {
    expect(functionBody("saveSidebarOrderTask")).toContain("Object.assign({}, existing || {}");
  });

  it("has light and dark blocks that set every colour the phone's light and dark modes set", () => {
    expect(declarationsIn(blockAfter(':root[data-theme="light"] {'))).toEqual(declarationsIn(blockAfter(":root {")));
    expect(declarationsIn(blockAfter(':root[data-theme="dark"] {'))).toEqual(declarationsIn(blockAfter("@media (prefers-color-scheme: dark) {\n  :root {")));
  });
});

describe("Reminder Test settings: the date format changes the page's dates", () => {
  const dates = loadPageScript().RemindersSettingsDates;

  it("leaves the page's own format while the format is auto", () => {
    expect(dates.chosenText(null, "2026-11-13")).toBeNull();
    expect(dates.chosenText({ "dates.format": "auto" }, "2026-11-13")).toBeNull();
    expect(dates.chosenText({ "dates.format": "sideways" }, "2026-11-13")).toBeNull();
  });

  it("writes the day in the chosen format, on the right day", () => {
    expect(dates.chosenText({ "dates.format": "month-day-year" }, "2026-11-13")).toBe("Nov 13, 2026");
    expect(dates.chosenText({ "dates.format": "weekday-month-day" }, "2026-11-13")).toBe("Fri, Nov 13");
  });
});

describe("Reminder Test settings: set_setting", () => {
  it("writes the setting into settings:self and keeps the list order", () => {
    const outcome = call("set_setting", { key: "accent.colour", value: "#0a84ff" }, baseRecords());
    expectSchemaValid(outcome);
    expect(outcome.ops).toHaveLength(1);
    expect(settingsWritten(outcome)).toEqual({ $type: "reminder-test.settings", order: LIST_ORDER, "accent.colour": "#0A84FF" });
  });

  it("sets light or dark, and refuses what it does not offer", () => {
    expectSchemaValid(call("set_setting", { key: "page.theme", value: "dark" }, baseRecords()));
    expect(call("set_setting", { key: "page.theme", value: "sepia" }, baseRecords()).refused).toBe("value-not-offered");
    expect(call("set_setting", { key: "order", value: "work" }, baseRecords()).refused).toBe("nothing-to-change");
  });

  it("keeps the settings when a list is added afterwards", () => {
    const withSetting = baseRecords({ $type: "reminder-test.settings", order: LIST_ORDER.slice(), "title.colour": "#AF52DE" });
    const created = call("create_list", { name: "Travel", color: "orange", icon: "airplane" }, withSetting);
    expectSchemaValid(created);
    const afterCreate = settingsWritten(created)!;
    expect(afterCreate["title.colour"]).toBe("#AF52DE");
    expect(afterCreate.order).toHaveLength(LIST_ORDER.length + 1);
  });
});

describe("Reminder Test settings: a hidden feature's tools answer turned off", () => {
  it("hidden checkbox circles turn off complete and uncomplete, and nothing else", () => {
    const records = baseRecords({ $type: "reminder-test.settings", order: LIST_ORDER.slice(), "circles.show": false });
    const complete = call("complete", { item: "Call Mom" }, records);
    expect(complete.refused).toBe("turned-off");
    expect(complete.result.text).toBe("Checkbox circles is turned off");
    expect(call("uncomplete", { item: "Dentist" }, records).refused).toBe("turned-off");
    expectSchemaValid(call("add", { title: "Buy milk", notes: null, list: null, when: null }, records));
  });

  it("works again once the circles are shown", () => {
    const records = baseRecords({ $type: "reminder-test.settings", order: LIST_ORDER.slice(), "circles.show": true });
    const complete = call("complete", { item: "Call Mom" }, records);
    expectSchemaValid(complete);
    expect(complete.ops!.length).toBeGreaterThan(0);
  });
});
