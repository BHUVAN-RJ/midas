// The settings engine in the Reminders Sidekick (repair lanes W5, founder D1, 2026-11-13). A person
// changes a part's colour or size, hides a part, or picks a date format by saying it; the values
// live in settings:self next to the page's own list order. These checks hold the catalogue in
// manifest.json, the page and tools.js together, check every selector names a part the page
// really draws, and run set_setting and "turned off" on real-shaped records.
process.env.TZ = "America/Los_Angeles";

import { readFileSync } from "node:fs";
import vm from "node:vm";
import { describe, expect, it } from "vitest";
import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import MidasSettings from "../../shell/sdk/midas-settings.js";
import { findEngineBlock, textOutsideEngine } from "../scripts/settings-engine-tools.mjs";
import { loadToolsScript, sidekickToolsProblems } from "../scripts/sidekick-tools.mjs";

const folder = new URL("../../sidekicks/reminders/", import.meta.url);
const html = readFileSync(new URL("index.html", folder), "utf8");
const toolsText = readFileSync(new URL("tools.js", folder), "utf8");
const manifest = JSON.parse(readFileSync(new URL("manifest.json", folder), "utf8"));
const catalogue = manifest.settings;

const loaded = loadToolsScript(toolsText);
if (!("tools" in loaded)) {
  throw new Error(loaded.problem);
}
const tools = loaded.tools;

const LA = "America/Los_Angeles";
const NOW = "2026-10-20T17:00:00.000Z";
const LIST_ORDER = ["today", "next7", "scheduled", "unscheduled", "all", "pastDue", "completed", "work"];

type Entry = { key: string; type: string; selector?: string; css?: string | string[]; default: unknown; tools?: string[] };
type Records = Array<{ key: string; value: Record<string, unknown> }>;
type Outcome = {
  ops?: Array<{ op: string; key: string; value?: Record<string, unknown> }>;
  refused?: string;
  result: { text: string };
};

/* ---------- The page's parts ---------- */

const styleMatch = html.match(/<style>([\s\S]*?)<\/style>/);
if (!styleMatch) {
  throw new Error("index.html has no style block");
}
const pageCss = styleMatch[1];
// The markup and the render code: the page without its style sheet and without the engine
// (whose comments and catalogue name the same classes)
const pageWithoutStyle = html.replace(styleMatch[0], "");
const renderText = textOutsideEngine(pageWithoutStyle);

function escapeForRegExp(text: string) {
  return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// The class names in a selector list: ".row-date .late, .pastdue-view .row-date" → row-date, late, pastdue-view
function classNamesIn(selector: string) {
  const names: string[] = [];
  const matches = selector.matchAll(/\.([A-Za-z][A-Za-z0-9_-]*)/g);
  for (const match of matches) {
    names.push(match[1]);
  }
  return names;
}

// A class the render code writes: inside a class attribute or a quoted class string ('row', ' on')
function renderCodeWritesClass(name: string) {
  const asWord = new RegExp(`["' ]${escapeForRegExp(name)}["' ]`);
  return asWord.test(renderText);
}

function styleSheetStylesClass(name: string) {
  const asSelector = new RegExp(`\\.${escapeForRegExp(name)}(?![A-Za-z0-9_-])`);
  return asSelector.test(pageCss);
}

// The light-mode value of a custom property on :root, as the page is built
function lightRootValue(property: string) {
  const rootBlock = pageCss.match(/:root\s*\{([\s\S]*?)\}/);
  if (!rootBlock) {
    return null;
  }
  const declaration = rootBlock[1].match(new RegExp(`${escapeForRegExp(property)}:\\s*([^;]+);`));
  return declaration ? declaration[1].trim() : null;
}

function cssListOf(entry: Entry) {
  if (Array.isArray(entry.css)) {
    return entry.css;
  }
  return typeof entry.css === "string" ? [entry.css] : [];
}

/* ---------- Tools ---------- */

function baseRecords(settingsValue?: Record<string, unknown>): Records {
  const settings = settingsValue || { $type: "reminders.settings", order: LIST_ORDER.slice() };
  return [
    { key: "list:work", value: { $type: "reminders.list", name: "Work", color: "#007AFF", icon: "briefcase", createdAt: "2026-10-01T00:00:00.000Z" } },
    { key: "settings:self", value: settings },
    { key: "reminder:callmom00001", value: { $type: "reminders.item", title: "Call Mom", done: false, timeZone: LA, at: "2026-10-21T01:00:00.000Z", allDay: false, createdAt: "2026-10-10T00:00:00.000Z" } },
    { key: "reminder:dentist00001", value: { $type: "reminders.item", title: "Dentist", done: true, completedAt: "2026-10-15T00:00:00.000Z", timeZone: LA, createdAt: "2026-10-12T00:00:00.000Z" } },
  ];
}

function call(verb: string, input: Record<string, unknown>, records: Records): Outcome {
  const outcome = tools.handlers[verb](input, records, NOW);
  return JSON.parse(JSON.stringify(outcome));
}

function settingsWritten(outcome: Outcome) {
  const ops = outcome.ops || [];
  const op = ops.find(function isSettingsOp(candidate) {
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
  const sandbox = { window: { location: { origin: "sidekick://reminders" } }, console, Intl, Date, Math, JSON };
  vm.createContext(sandbox);
  vm.runInContext(scriptMatch[1], sandbox);
  return sandbox as Record<string, any>;
}

// The body of a function in the page's script, up to the next function at the same depth
function functionBody(name: string) {
  const start = html.indexOf(`  function ${name}(`);
  if (start === -1) {
    throw new Error(`index.html has no function ${name}`);
  }
  const end = html.indexOf("\n  }\n", start);
  return html.slice(start, end);
}

describe("Reminders settings: the catalogue", () => {
  it("is a valid catalogue of 20 to 45 settings", () => {
    expect(MidasSettings.catalogueProblems(catalogue)).toEqual([]);
    expect(catalogue.entries.length).toBeGreaterThanOrEqual(20);
    expect(catalogue.entries.length).toBeLessThanOrEqual(45);
  });

  it("has one date format, auto by default", () => {
    const dateEntries = catalogue.entries.filter(function isDateFormat(entry: Entry) {
      return entry.type === "dateFormat";
    });
    expect(dateEntries).toHaveLength(1);
    expect(dateEntries[0].key).toBe("dates.format");
    expect(dateEntries[0].default).toBe("auto");
  });

  it("is the same in the page, in tools.js and in manifest.json", () => {
    const pageBlock = findEngineBlock(html);
    const toolsBlock = findEngineBlock(toolsText);
    expect(pageBlock).not.toBeNull();
    expect(toolsBlock).not.toBeNull();
    expect(pageBlock!.catalogue).toEqual(catalogue);
    expect(toolsBlock!.catalogue).toEqual(catalogue);
  });

  it("gives each setting its schema in settings:self, next to the list order", () => {
    const properties = manifest.types["settings:"].schema.properties;
    for (const entry of catalogue.entries as Entry[]) {
      expect(properties[entry.key], entry.key).toEqual(MidasSettings.propertySchemaFor(entry));
    }
    expect(properties.order).toEqual({ type: "array", maxItems: 200, items: { type: "string", maxLength: 200 } });
  });

  it("names only real tools as turned off by a hidden part", () => {
    const toolNames = manifest.agent.tools.map(function nameOf(tool: { name: string }) {
      return tool.name;
    });
    for (const entry of catalogue.entries as Entry[]) {
      for (const toolName of entry.tools || []) {
        expect(toolNames, entry.key).toContain(toolName);
      }
    }
  });

  it("passes the deploy gate's tools check with set_setting added", () => {
    expect(sidekickToolsProblems(manifest, toolsText, html, "reminders")).toEqual([]);
    expect(typeof tools.handlers.set_setting).toBe("function");
  });
});

describe("Reminders settings: every selector is a part the page draws", () => {
  for (const entry of catalogue.entries as Entry[]) {
    if (typeof entry.selector !== "string") {
      continue;
    }
    it(`${entry.key} (${entry.selector})`, () => {
      const names = classNamesIn(entry.selector!);
      const isRootOnly = entry.selector!.trim() === ":root";
      expect(isRootOnly || names.length > 0).toBe(true);
      for (const name of names) {
        expect(styleSheetStylesClass(name), `.${name} in the style sheet`).toBe(true);
        expect(renderCodeWritesClass(name), `.${name} written by the page`).toBe(true);
      }
    });
  }

  it("sets only custom properties the style sheet uses, with the page's own light colour as default", () => {
    for (const entry of catalogue.entries as Entry[]) {
      if (entry.type !== "colour") {
        continue;
      }
      for (const property of cssListOf(entry)) {
        if (!property.startsWith("--")) {
          continue;
        }
        expect(pageCss.includes(`var(${property}`), `${entry.key}: var(${property}) used`).toBe(true);
        const builtValue = entry.selector === ":root" ? lightRootValue(property) : null;
        if (builtValue !== null) {
          expect(String(entry.default).toUpperCase(), entry.key).toBe(builtValue.toUpperCase());
        }
      }
    }
  });

  it("draws nothing until a setting is changed, then a rule for that part", () => {
    expect(MidasSettings.cssFor(catalogue, { $type: "reminders.settings", order: LIST_ORDER })).toBe("");
    const css = MidasSettings.cssFor(catalogue, { "circles.colour": "#FF9500", "notes.show": false });
    expect(css).toContain(".circle { --c: #FF9500 !important; }");
    expect(css).toContain(".row-notes { display: none !important; }");
  });
});

describe("Reminders settings: the page watches settings:self", () => {
  it("starts the watch with the page's own read of settings:self and redraws on a change", () => {
    const startBody = functionBody("start");
    expect(startBody).toContain("MidasSettings.watch({ catalogue: SETTINGS_CATALOGUE, read: readSettings, onChange: handleSettingsChange })");
    expect(functionBody("readSettings")).toContain("store.get(SETTINGS_KEY)");
    expect(functionBody("handleSettingsChange")).toContain("requestRender()");
  });

  it("writes every date it shows through the person's date format", () => {
    const dateFunctions = ["formatDayLabel", "formatLongKey", "formatLongDate", "formatDayMonth", "formatRange", "weekDayHeaderHTML"];
    for (const name of dateFunctions) {
      expect(functionBody(name), name).toMatch(/chosenDateText\(|formatDayMonth\(/);
    }
    expect(functionBody("chosenDateText")).toContain("RemindersSettingsDates.chosenText(");
  });

  it("keeps the list order and the settings together when the page saves the order", () => {
    const saveBody = html.slice(html.indexOf("function saveSidebarOrderTask"), html.indexOf("function saveListTask"));
    expect(saveBody).toContain("Object.assign({}, existing || {}");
  });
});

describe("Reminders settings: the date format changes the page's dates", () => {
  const page = loadPageScript();
  const dates = page.RemindersSettingsDates;

  it("leaves the page's own format while the format is auto", () => {
    expect(dates.chosenText(null, "2026-11-13")).toBeNull();
    expect(dates.chosenText({ $type: "reminders.settings", order: LIST_ORDER }, "2026-11-13")).toBeNull();
    expect(dates.chosenText({ "dates.format": "auto" }, "2026-11-13")).toBeNull();
  });

  it("writes the day in the chosen format, on the right day", () => {
    expect(dates.chosenText({ "dates.format": "month-day-year" }, "2026-11-13")).toBe("Nov 13, 2026");
    expect(dates.chosenText({ "dates.format": "day-month" }, "2026-11-13")).toBe("13 Nov");
    expect(dates.chosenText({ "dates.format": "numeric-day-first" }, "2026-01-02")).toBe("02/01/2026");
    expect(dates.chosenText({ "dates.format": "weekday-month-day" }, "2026-11-13")).toBe("Fri, Nov 13");
  });

  it("ignores a stored value that is not a date format", () => {
    expect(dates.chosenText({ "dates.format": "sideways" }, "2026-11-13")).toBeNull();
  });
});

describe("Reminders settings: set_setting", () => {
  it("writes the setting into settings:self and keeps the list order", () => {
    const outcome = call("set_setting", { key: "circles.colour", value: "#ff9500" }, baseRecords());
    expectSchemaValid(outcome);
    expect(outcome.ops).toHaveLength(1);
    expect(settingsWritten(outcome)).toEqual({ $type: "reminders.settings", order: LIST_ORDER, "circles.colour": "#FF9500" });
  });

  it("writes a record that passes the write gate when there was no settings:self yet", () => {
    const records = baseRecords().filter(function isNotSettings(record) {
      return record.key !== "settings:self";
    });
    const outcome = call("set_setting", { key: "dates.format", value: "day-month-year" }, records);
    expectSchemaValid(outcome);
    expect(settingsWritten(outcome)).toEqual({ "dates.format": "day-month-year" });
  });

  it("turns a part off with a person's word", () => {
    const outcome = call("set_setting", { key: "notes.show", value: "hide" }, baseRecords());
    expectSchemaValid(outcome);
    expect(settingsWritten(outcome)!["notes.show"]).toBe(false);
  });

  it("refuses a value the setting does not take, and a setting that does not exist", () => {
    const badSize = call("set_setting", { key: "title.size", value: "huge" }, baseRecords());
    expect(badSize.refused).toBe("value-not-offered");
    expect(badSize.ops).toBeUndefined();
    const unknown = call("set_setting", { key: "order", value: "work" }, baseRecords());
    expect(unknown.refused).toBe("nothing-to-change");
    expect(unknown.ops).toBeUndefined();
  });

  it("keeps the settings when a list is added afterwards", () => {
    const withSetting = baseRecords({ $type: "reminders.settings", order: LIST_ORDER.slice(), "title.colour": "#AF52DE" });
    const created = call("create_list", { name: "Travel", color: "orange", icon: "airplane" }, withSetting);
    expectSchemaValid(created);
    const afterCreate = settingsWritten(created)!;
    expect(afterCreate["title.colour"]).toBe("#AF52DE");
    expect(afterCreate.order).toHaveLength(LIST_ORDER.length + 1);
  });
});

describe("Reminders settings: a hidden feature's tools answer turned off", () => {
  it("hidden checkbox circles turn off complete and uncomplete, and nothing else", () => {
    const records = baseRecords({ $type: "reminders.settings", order: LIST_ORDER.slice(), "circles.show": false });
    const complete = call("complete", { item: "Call Mom" }, records);
    expect(complete.refused).toBe("turned-off");
    expect(complete.ops).toBeUndefined();
    expect(complete.result.text).toBe("Checkbox circles is turned off");
    const uncomplete = call("uncomplete", { item: "Dentist" }, records);
    expect(uncomplete.refused).toBe("turned-off");
    const added = call("add", { title: "Buy milk", notes: null, list: null, when: null }, records);
    expectSchemaValid(added);
    const createdList = call("create_list", { name: "Travel", color: "orange", icon: "airplane" }, records);
    expectSchemaValid(createdList);
  });

  it("a hidden Add List button turns off create_list only", () => {
    const records = baseRecords({ $type: "reminders.settings", order: LIST_ORDER.slice(), "addList.show": false });
    const createdList = call("create_list", { name: "Travel", color: "orange", icon: "airplane" }, records);
    expect(createdList.refused).toBe("turned-off");
    expect(createdList.ops).toBeUndefined();
    const complete = call("complete", { item: "Call Mom" }, records);
    expectSchemaValid(complete);
  });

  it("works again once the part is shown", () => {
    const records = baseRecords({ $type: "reminders.settings", order: LIST_ORDER.slice(), "circles.show": true });
    const complete = call("complete", { item: "Call Mom" }, records);
    expectSchemaValid(complete);
    expect(complete.ops!.length).toBeGreaterThan(0);
  });
});
