// The settings engine in the To-Do Sidekick (repair lanes W5, founder D1, 2026-11-13). To-Do keeps
// its own Make It Yours engine (todo.set_setting { preset, field, value }); the manifest catalogue
// lists every Make It Yours field with the page's own values and defaults, plus colour, size,
// show and date-format settings for the page's parts, which the shared engine draws and writes.
// Checks: the catalogue is valid and agrees with the page, manifest and tools.js; every selector
// names a part the page draws; set_setting writes a record the schema accepts and never drops
// the other side's fields; a hidden feature's tool answers "turned off"; the date format changes
// the page's date text; a change to settings:self is drawn on the page at once.
process.env.TZ = "America/Los_Angeles";

import { readFileSync } from "node:fs";
import vm from "node:vm";
import { describe, expect, it } from "vitest";
import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import { loadToolsScript, sidekickToolsProblems } from "../scripts/sidekick-tools.mjs";
import { MidasSettings, findEngineBlock, textOutsideEngine } from "../scripts/settings-engine-tools.mjs";

const folder = new URL("../../sidekicks/todo/", import.meta.url);
const html = readFileSync(new URL("index.html", folder), "utf8");
const toolsText = readFileSync(new URL("tools.js", folder), "utf8");
const manifest = JSON.parse(readFileSync(new URL("manifest.json", folder), "utf8"));
const catalogue = manifest.settings;

type Value = Record<string, unknown>;
type Records = Array<{ key: string; value: Value }>;
type Op = { op: string; key: string; value?: Value };
type Outcome = { ops?: Op[]; refused?: string; result: { text: string; [field: string]: unknown } };
type Entry = { key: string; label: string; type: string; part: string; default: unknown; values?: unknown[]; selector?: string; css?: string | string[]; tools?: string[] };

const NOW = "2026-10-31T17:00:00.000Z";

function todoLogicSource(pageHtml: string) {
  const start = pageHtml.indexOf("var TodoLogic = (function createTodoLogic() {");
  const end = pageHtml.indexOf("\n})();\n", start) + "\n})();\n".length;
  if (start === -1 || end <= start) {
    throw new Error("TodoLogic is not in index.html");
  }
  return pageHtml.slice(start, end);
}

// A top-level function of the page's script, as written
function pageFunction(name: string) {
  const plain = html.indexOf(`\nfunction ${name}(`);
  const start = plain === -1 ? html.indexOf(`\nasync function ${name}(`) : plain;
  if (start === -1) {
    throw new Error(`${name} is not in index.html`);
  }
  const end = html.indexOf("\n}\n", start) + "\n}\n".length;
  return html.slice(start + 1, end);
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const Logic: any = vm.runInNewContext(todoLogicSource(html) + "\n;TodoLogic;", { Intl, Date, Math, JSON });
const pageEngine = findEngineBlock(html);
const toolsEngine = findEngineBlock(toolsText);
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const PageSettings: any = vm.runInNewContext(`${pageEngine?.engineText}\n;MidasSettings;`, { Date, Math, JSON });

const loaded = loadToolsScript(toolsText);
if (!("tools" in loaded)) {
  throw new Error(loaded.problem);
}
const tools = loaded.tools;

const MIY_FIELDS: string[] = Object.keys(Logic.DEFAULT_SETTINGS);
const entries: Entry[] = catalogue.entries;
const engineEntries = entries.filter((entry) => !MIY_FIELDS.includes(entry.key));

// What the page writes after Make It Yours, plus a setting the engine wrote (title colour)
function baseRecords(extra: Value = {}): Records {
  const settings = { $type: "todo.settings", ...Logic.settingsRecordValue(Logic.DEFAULT_SETTINGS, "mine"), ...extra };
  return [
    { key: "reminder:gym", value: { $type: "todo.item", title: "Gym", list: "inbox", subtasks: [], done: false, order: 1, someday: false, createdAt: "2026-10-30T17:00:00.000Z", when: "2026-10-31" } },
    { key: "reminder:old", value: { $type: "todo.item", title: "Dentist", list: "inbox", subtasks: [], done: false, order: 2, someday: false, createdAt: "2026-10-29T17:00:00.000Z", deletedAt: "2026-10-30T17:00:00.000Z" } },
    { key: "settings:self", value: settings },
  ];
}

function call(verb: string, input: Value, records: Records): Outcome {
  return tools.handlers[verb](input, records, NOW) as Outcome;
}

// The settings:self value a set_setting call writes, checked as the shell's write gate checks it
function writtenSettings(outcome: Outcome): Value {
  expect(outcome.refused, outcome.result.text).toBeUndefined();
  expect(outcome.ops).toHaveLength(1);
  const op = (outcome.ops as Op[])[0];
  expect(op.key).toBe("settings:self");
  const stamped = MidasRecordSchema.stampType(manifest.types, op.key, op.value as Value);
  expect(MidasRecordSchema.checkRecord(manifest.types, op.key, stamped)).toBeNull();
  return JSON.parse(JSON.stringify(op.value));
}

function withSettings(records: Records, changes: Value): Records {
  return records.map(function changedRecord(record) {
    if (record.key !== "settings:self") {
      return record;
    }
    return { key: record.key, value: { ...record.value, ...changes } };
  });
}

/* ---------- the page's markup and render code, without its style sheet and the engine ---------- */

const styleStart = html.indexOf("<style>");
const styleEnd = html.indexOf("</style>");
const styleText = html.slice(styleStart, styleEnd);
const pageCode = textOutsideEngine(html.slice(0, styleStart) + html.slice(styleEnd));

function escapeRegExp(text: string) {
  return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// Why a selector names nothing the page draws: each class, id and attribute must be written by the
// page's markup or its render code; empty when every part is
function selectorProblems(selector: string): string[] {
  const problems: string[] = [];
  const classNames = selector.match(/\.[A-Za-z][\w-]*/g) ?? [];
  for (const dotted of classNames) {
    const name = dotted.slice(1);
    const written = new RegExp(`(class="[^"]*|['" ])(?<![\\w-])${escapeRegExp(name)}(?![\\w-])`);
    if (!written.test(pageCode)) {
      problems.push(`class ${name} is not written by the page`);
    }
  }
  const ids = selector.match(/#[A-Za-z][\w-]*/g) ?? [];
  for (const hashed of ids) {
    if (!pageCode.includes(`id="${hashed.slice(1)}"`)) {
      problems.push(`id ${hashed} is not written by the page`);
    }
  }
  const attributes = [...selector.matchAll(/\[([\w-]+)="([^"]+)"\]/g)];
  for (const [, name, value] of attributes) {
    const literal = pageCode.includes(`${name}="${value}"`);
    // A value the render code fills in from a list: data-view="' + tabs[index][0] + '"
    const filledIn = pageCode.includes(`${name}="' +`) && pageCode.includes(`'${value}'`);
    if (!literal && !filledIn) {
      problems.push(`${name}="${value}" is not written by the page`);
    }
  }
  return problems;
}

describe("todo settings: the catalogue", () => {
  it("is a valid catalogue, and any change makes the look Custom", () => {
    expect(MidasSettings.catalogueProblems(catalogue)).toEqual([]);
    expect(catalogue.alsoSet).toEqual({ preset: "custom" });
  });

  it("lists every Make It Yours field with the page's own values and the founder's start", () => {
    for (const field of MIY_FIELDS) {
      const entry = MidasSettings.entryFor(catalogue, field) as Entry | null;
      expect(entry, field).not.toBeNull();
      expect((entry as Entry).selector, field).toBeUndefined();
      expect((entry as Entry).default, field).toEqual(Logic.DEFAULT_SETTINGS[field]);
      if (field === "accent") {
        expect((entry as Entry).type).toBe("colour");
      } else {
        expect((entry as Entry).type, field).toBe("choice");
        expect((entry as Entry).values, field).toEqual(JSON.parse(JSON.stringify(Logic.settingChoices(field))));
      }
    }
  });

  it("has colour, size and show settings for the page's parts and a date format", () => {
    const types = new Set(engineEntries.map((entry) => entry.type));
    expect([...types].sort()).toEqual(["colour", "dateFormat", "show", "size"]);
    expect(MidasSettings.entryFor(catalogue, "dates.format")).toMatchObject({ type: "dateFormat", default: "auto" });
    expect(MidasSettings.entryFor(catalogue, "makeItYours.show")).toMatchObject({ type: "show", default: true });
  });

  it("names, in every selector, parts the page really draws", () => {
    for (const entry of engineEntries) {
      if (entry.selector === undefined) {
        continue;
      }
      expect(selectorProblems(entry.selector), entry.key).toEqual([]);
    }
    // The check fails for a part the page never draws
    expect(selectorProblems(".streak-chip")).toEqual(["class streak-chip is not written by the page"]);
    expect(selectorProblems('.tab[data-view="calendar"]')).toEqual(['data-view="calendar" is not written by the page']);
  });

  it("sets only CSS custom properties the page's style sheet uses", () => {
    for (const entry of engineEntries) {
      const names = entry.css === undefined ? [] : Array.isArray(entry.css) ? entry.css : [entry.css];
      for (const name of names) {
        if (name.startsWith("--")) {
          expect(styleText.includes(`var(${name}`), `${entry.key} ${name}`).toBe(true);
        }
      }
    }
  });

  it("has defaults matching the page as built (Notebook, light)", () => {
    const notebookLight = styleText.match(/\.screen\[data-look="notebook"\]\[data-theme="light"\] \{([^}]*)\}/);
    expect(notebookLight).not.toBeNull();
    const rule = (notebookLight as RegExpMatchArray)[1];
    const expectations: Array<[string, string]> = [["page.colour", "--bg"], ["text.colour", "--ink"], ["fadedText.colour", "--ink-2"], ["lines.colour", "--line"]];
    for (const [key, property] of expectations) {
      const declared = rule.match(new RegExp(`${escapeRegExp(property)}:\\s*(#[0-9A-Fa-f]{6})`));
      expect(declared, property).not.toBeNull();
      expect((MidasSettings.entryFor(catalogue, key) as Entry).default, key).toBe((declared as RegExpMatchArray)[1]);
    }
  });
});

describe("todo settings: the files agree", () => {
  it("has the same catalogue in the page, tools.js and the manifest, and passes the tools gate", () => {
    expect(pageEngine).not.toBeNull();
    expect(toolsEngine).not.toBeNull();
    expect(pageEngine?.catalogue).toEqual(catalogue);
    expect(toolsEngine?.catalogue).toEqual(catalogue);
    expect(pageEngine?.engineText).toBe(toolsEngine?.engineText);
    expect(sidekickToolsProblems(manifest, toolsText, html, "todo")).toEqual([]);
  });

  it("gives every new key the schema the engine writes, and keeps Make It Yours's own", () => {
    const properties = manifest.types["settings:"].schema.properties;
    for (const entry of engineEntries) {
      expect(properties[entry.key], entry.key).toEqual(MidasSettings.propertySchemaFor(entry));
    }
    // Every value Make It Yours offers still fits its own (unchanged) schema
    for (const field of MIY_FIELDS) {
      const entry = MidasSettings.entryFor(catalogue, field) as Entry;
      const offered = field === "accent" ? Logic.ACCENTS : entry.values;
      for (const value of offered as unknown[]) {
        const record = MidasRecordSchema.stampType(manifest.types, "settings:self", { [field]: value });
        expect(MidasRecordSchema.checkRecord(manifest.types, "settings:self", record), `${field} ${String(value)}`).toBeNull();
      }
    }
  });

  it("offers every catalogue key in todo.set_setting, and says what values look like", () => {
    const setTool = manifest.agent.tools.find((tool: Value) => tool.name === "todo.set_setting");
    const fields = setTool.inputSchema.properties.field.enum;
    for (const entry of entries) {
      expect(fields, entry.key).toContain(entry.key);
    }
    expect(fields).toContain(null);
    const description: string = setTool.inputSchema.properties.value.description;
    expect(description.length).toBeLessThan(1000);
    for (const words of ["#RRGGBB", "s/m/l/xl", ".show on/off", "day-month"]) {
      expect(description, words).toContain(words);
    }
  });

  it("passes the engine Make It Yours's fields and keeps To-Do's own set_setting for them", () => {
    const attach = textOutsideEngine(toolsText).match(/MidasSidekickTools = MidasSettings\.attachTools\(MidasSidekickTools, (\{.*\})\);/);
    expect(attach).not.toBeNull();
    const options = JSON.parse((attach as RegExpMatchArray)[1].replace("catalogue: SETTINGS_CATALOGUE", '"catalogue": null').replace(/(\w+):/g, '"$1":').replace(/""/g, '"'));
    expect(options.sidekickId).toBe("todo");
    expect([...options.ownKeys].sort()).toEqual([...MIY_FIELDS].sort());
  });
});

describe("todo settings: set_setting", () => {
  it("writes a part's setting through the engine, keeping Make It Yours's fields, and makes the look Custom", () => {
    const value = writtenSettings(call("set_setting", { preset: null, field: "title.colour", value: "#ff0000" }, baseRecords()));
    expect(value["title.colour"]).toBe("#FF0000");
    expect(value.preset).toBe("custom");
    for (const field of MIY_FIELDS) {
      expect(value[field], field).toEqual(Logic.DEFAULT_SETTINGS[field]);
    }
    const size = writtenSettings(call("set_setting", { preset: null, field: "rows.size", value: "xl" }, baseRecords()));
    expect(size["rows.size"]).toBe("xl");
    const hidden = writtenSettings(call("set_setting", { preset: null, field: "makeItYours.show", value: "off" }, baseRecords()));
    expect(hidden["makeItYours.show"]).toBe(false);
    const dates = writtenSettings(call("set_setting", { preset: null, field: "dates.format", value: "day-month-year" }, baseRecords()));
    expect(dates["dates.format"]).toBe("day-month-year");
  });

  it("refuses a value a part does not take", () => {
    expect(call("set_setting", { preset: null, field: "title.colour", value: "red" }, baseRecords()).refused).toBe("value-not-offered");
    expect(call("set_setting", { preset: null, field: "rows.size", value: "huge" }, baseRecords()).refused).toBe("value-not-offered");
    expect(call("set_setting", { preset: null, field: "dates.format", value: "yesterday" }, baseRecords()).refused).toBe("value-not-offered");
  });

  it("keeps Make It Yours's own rules for its fields (the eight accents), and works with no record", () => {
    expect(call("set_setting", { preset: null, field: "accent", value: "#123456" }, baseRecords()).refused).toBe("value-not-offered");
    const records = baseRecords().filter((record) => record.key !== "settings:self");
    const value = writtenSettings(call("set_setting", { preset: null, field: "headings.size", value: "l" }, records));
    expect(value["headings.size"]).toBe("l");
  });

  it("keeps the engine's keys when Make It Yours changes an option or a whole look", () => {
    const records = baseRecords({ "title.colour": "#FF0000", "dates.format": "month-day" });
    const option = writtenSettings(call("set_setting", { preset: null, field: "tickSound", value: "off" }, records));
    expect(option).toMatchObject({ tickSound: "off", preset: "custom", "title.colour": "#FF0000", "dates.format": "month-day" });
    const look = writtenSettings(call("set_setting", { preset: "heat", field: null, value: null }, records));
    expect(look).toMatchObject({ look: "heat", preset: "heat", "title.colour": "#FF0000", "dates.format": "month-day" });
    // The page's own save (Make It Yours on the page) keeps them too
    const saved = Logic.settingsRecordValue(Logic.presetSettings("soft"), "soft", records[2].value);
    expect(saved).toMatchObject({ look: "soft", preset: "soft", "title.colour": "#FF0000" });
  });

  it("still changes settings with the Make It Yours button hidden (the engine stays)", () => {
    const records = baseRecords({ "makeItYours.show": false });
    const value = writtenSettings(call("set_setting", { preset: null, field: "look", value: "paper" }, records));
    expect(value).toMatchObject({ look: "paper", "makeItYours.show": false });
    expect(MidasSettings.cssFor(catalogue, { "makeItYours.show": false })).toContain('.topbar [data-action="panel"] { display: none !important; }');
  });
});

describe("todo settings: a hidden feature's tool answers turned off", () => {
  it("refuses search while Search is hidden, and leaves the other tools working", () => {
    expect(call("search", { query: "gym" }, baseRecords()).refused).toBeUndefined();
    const hidden = baseRecords({ "search.show": false });
    const outcome = call("search", { query: "gym" }, hidden);
    expect(outcome.refused).toBe("turned-off");
    expect(outcome.result.text).toBe("Search (tab, button and box) is turned off");
    expect(call("today", {}, hidden).refused).toBeUndefined();
    expect(call("restore", { item: "Dentist" }, hidden).refused).toBeUndefined();
  });

  it("refuses restore while Trash is hidden", () => {
    const hidden = baseRecords({ "trash.show": false });
    expect(call("restore", { item: "Dentist" }, hidden).refused).toBe("turned-off");
    expect(call("search", { query: "gym" }, hidden).refused).toBeUndefined();
  });
});

describe("todo settings: the page", () => {
  function datePage(record: Value | null) {
    const context = { Logic, MidasSettings: PageSettings, SETTINGS_CATALOGUE: pageEngine?.catalogue, state: { settingsRecord: record } };
    vm.runInNewContext(`${pageFunction("formattedDate")}\n${pageFunction("dayText")}\nthis.dayText = dayText; this.formattedDate = formattedDate;`, context);
    return context as unknown as { dayText: (key: string, today: string) => string; formattedDate: (date: Date) => string | null };
  }

  it("writes dates in the person's date format, and its own way while auto", () => {
    const today = "2026-10-31";
    const auto = datePage(null);
    expect(auto.dayText("2026-11-12", today)).toBe("Nov 12");
    expect(auto.dayText("2026-11-03", today)).toBe("Tue");
    expect(auto.formattedDate(Logic.parseDay(today))).toBeNull();
    const dayMonth = datePage({ "dates.format": "day-month" });
    expect(dayMonth.dayText("2026-11-12", today)).toBe("12 Nov");
    expect(dayMonth.dayText("2026-11-03", today)).toBe("3 Nov");
    expect(dayMonth.dayText("2026-11-01", today)).toBe("Tomorrow");
    const full = datePage({ "dates.format": "weekday-month-day" });
    expect(full.formattedDate(Logic.parseDay(today))).toBe("Sat, Oct 31");
  });

  it("sends every date it shows through the date format", () => {
    const outsideLogic = pageCode.slice(pageCode.indexOf("\n})();\n", pageCode.indexOf("var TodoLogic")));
    const ownDates = outsideLogic.match(/Logic\.(friendlyDay|longDay|shortDate)\(/g) ?? [];
    // dayText's own fallback and the Today subtitle's fallback (auto)
    expect(ownDates).toEqual(["Logic.friendlyDay(", "Logic.longDay("]);
    expect(pageFunction("viewTitle")).toContain("formattedDate(Logic.parseDay(todayKey())) || Logic.longDay(todayKey())");
    expect(pageFunction("renderUpcoming")).toContain("formattedDate(date)");
  });

  it("watches settings:self from start, and draws a change at once", () => {
    expect(pageFunction("start")).toContain("settingsWatch = MidasSettings.watch({ catalogue: SETTINGS_CATALOGUE, read: readSettingsRecord, onChange: handleSettingsChange });");
    const calls: string[] = [];
    const state = { settings: Logic.copyJson(Logic.DEFAULT_SETTINGS), preset: "mine", settingsRecord: null as Value | null };
    const context = {
      Logic,
      state,
      render: function countRender() { calls.push("render"); },
      fitViewToHome: function countFit() { calls.push("fit"); },
      publishWidget: function countWidget() { calls.push("widget"); },
    };
    vm.runInNewContext(`${pageFunction("handleSettingsChange")}\nthis.handleSettingsChange = handleSettingsChange;`, context);
    const record = { $type: "todo.settings", ...Logic.settingsRecordValue(Logic.DEFAULT_SETTINGS, "custom"), look: "heat", accent: "#E5484D", "title.colour": "#FF0000" };
    (context as unknown as { handleSettingsChange: (values: Value, record: Value) => void }).handleSettingsChange(PageSettings.valuesFrom(catalogue, record), record);
    expect(state.settings.look).toBe("heat");
    expect(state.settings.accent).toBe("#E5484D");
    expect(state.preset).toBe("custom");
    expect(state.settingsRecord).toEqual(record);
    expect(calls).toEqual(["fit", "render", "widget"]);
  });

  it("saves Make It Yours over the stored record, so the engine's keys survive", () => {
    const save = pageFunction("saveSettings");
    expect(save).toContain("Logic.settingsRecordValue(state.settings, state.preset, state.settingsRecord)");
    expect(pageFunction("loadAll")).toContain("state.settingsRecord = storedSettings(records);");
  });
});
