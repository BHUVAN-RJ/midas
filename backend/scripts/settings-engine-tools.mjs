// The settings engine in a Sidekick's files (repair lanes W5, founder D1, 2026-11-13). One place
// that knows how the engine sits in a page, its tools.js and its manifest, used by:
//   - the base Sidekicks' tests (backend/test/settings-engine-sidekicks.test.ts),
//   - the copies script (scripts/bring-settings-engine.mjs), which puts the engine into each
//     person's repaired copy while keeping their changes.
//
// In the page and in tools.js the engine is one block of text, the same in both:
//
//   <shell/sdk/midas-settings.js, unchanged>
//   var SETTINGS_CATALOGUE = <manifest.json "settings", as JSON>;
//
// In tools.js it sits between "copied from index.html" markers, so the deploy gate refuses a
// tools.js whose engine or catalogue no longer matches the page. tools.js ends with
// MidasSettings.attachTools, which gives the tools set_setting and answers "turned off" for a
// hidden feature's tool.
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const MidasSettings = require("../../shell/sdk/midas-settings.js");

export const ENGINE_FIRST_LINE = "// Midas settings engine for Sidekicks";
export const ENGINE_END = "\n})();\n\nif (typeof module !== 'undefined' && module.exports) {\n  module.exports = MidasSettings;\n}";
export const CATALOGUE_DECLARATION = "var SETTINGS_CATALOGUE = ";
export const COPY_BEGIN = "/* copied from index.html: begin */";
export const COPY_END = "/* copied from index.html: end */";
export const ATTACH_CALL = "MidasSidekickTools = MidasSettings.attachTools(";
export const WATCH_CALL = "MidasSettings.watch(";
export const SETTINGS_TYPE_PREFIX = "settings:";
export const SETTINGS_KEY = "settings:self";
const STORE_HELPER_END = "\n})();";
const STORE_HELPER_LINE = "var store = (function createMidasStore() {";
const TOOLS_EXPORT_LINE = "if (typeof module !== 'undefined' && module.exports) {\n  module.exports = MidasSidekickTools;\n}";

export { MidasSettings };

export function currentSettingsEngine(enginePath = new URL("../../shell/sdk/midas-settings.js", import.meta.url)) {
  return readFileSync(enginePath, "utf8").trim();
}

export function catalogueLine(catalogue) {
  return `${CATALOGUE_DECLARATION}${JSON.stringify(catalogue)};`;
}

// The block the page and tools.js both hold
export function engineBlock(catalogue, engineText = currentSettingsEngine()) {
  return `${engineText}\n${catalogueLine(catalogue)}\n`;
}

// The engine block found in a page or tools.js: { start, end, engineText, catalogue } or null
export function findEngineBlock(text) {
  const start = text.indexOf(ENGINE_FIRST_LINE);
  if (start === -1) {
    return null;
  }
  const engineEnd = text.indexOf(ENGINE_END, start);
  if (engineEnd === -1) {
    return null;
  }
  const engineStop = engineEnd + ENGINE_END.length;
  const declarationStart = text.indexOf(CATALOGUE_DECLARATION, engineStop);
  if (declarationStart === -1 || text.slice(engineStop, declarationStart).trim() !== "") {
    return null;
  }
  const lineEnd = text.indexOf("\n", declarationStart);
  const declaration = text.slice(declarationStart + CATALOGUE_DECLARATION.length, lineEnd === -1 ? text.length : lineEnd).trim();
  let catalogue = null;
  try {
    catalogue = JSON.parse(declaration.replace(/;$/, ""));
  } catch {
    return null;
  }
  return { start, end: lineEnd === -1 ? text.length : lineEnd + 1, engineText: text.slice(start, engineStop), catalogue };
}

// The text outside the engine block: the engine's own comments name the calls a page and a
// tools.js make, so a call is looked for only outside it
export function textOutsideEngine(text) {
  const found = findEngineBlock(text);
  if (found === null) {
    return text;
  }
  return text.slice(0, found.start) + text.slice(found.end);
}

/* ---------- manifest.json ---------- */

// Every catalogue key as a field of settings:self, with the schema the engine writes
export function settingsSchemaProperties(catalogue) {
  const properties = {};
  for (const entry of catalogue.entries) {
    properties[entry.key] = MidasSettings.propertySchemaFor(entry);
  }
  return properties;
}

// The manifest with its "settings:" type holding every catalogue key (added, never narrowed: a
// field the type already has is kept as it is) and the catalogue itself. A manifest with no
// "settings:" type gets one, open to any other field the page already keeps there.
export function manifestWithSettings(manifest, catalogue) {
  const next = structuredClone(manifest);
  next.settings = structuredClone(catalogue);
  next.types = next.types ?? {};
  const existing = next.types[SETTINGS_TYPE_PREFIX];
  if (existing === undefined) {
    next.types[SETTINGS_TYPE_PREFIX] = { $type: `${manifest.id}.settings`, schema: { type: "object", properties: { $type: { type: "string" } } } };
  }
  const schema = next.types[SETTINGS_TYPE_PREFIX].schema;
  schema.properties = schema.properties ?? {};
  for (const [key, propertySchema] of Object.entries(settingsSchemaProperties(catalogue))) {
    if (schema.properties[key] === undefined) {
      schema.properties[key] = propertySchema;
    }
  }
  return next;
}

// The set_setting tool every Sidekick without its own gets: { key, value } over the catalogue
export function setSettingTool(sidekickId, catalogue) {
  const keys = catalogue.entries.map(function keyOf(entry) {
    return entry.key;
  });
  return {
    name: `${sidekickId}.set_setting`,
    description: "Change how the page looks: a part's colour or size, show or hide a part, the date format.",
    _meta: { "midas/page-actions": ["drawSettings"] },
    inputSchema: {
      type: "object",
      additionalProperties: false,
      required: ["key", "value"],
      properties: {
        key: { type: "string", enum: keys, description: "The setting, from the list." },
        value: {
          type: "string",
          description: "A colour as #RRGGBB; a size s, m, l or xl; on or off to show or hide; a date format such as day-month or month-day-year; else one of the setting's choices.",
        },
      },
    },
  };
}

export function hasSettingTool(manifest, sidekickId) {
  const tools = manifest?.agent?.tools;
  if (!Array.isArray(tools)) {
    return false;
  }
  return tools.some(function isSetSetting(tool) {
    return tool?.name === `${sidekickId}.set_setting`;
  });
}

/* ---------- index.html ---------- */

// The page with the engine block right after the store helper (replacing an older engine
// block), and, when it has none, the generic wiring that draws the settings and redraws on a
// change. Returns { html, status } with status "current", "added", "refreshed" or "no-store-helper".
export function pageWithEngine(html, catalogue, engineText = currentSettingsEngine()) {
  const block = engineBlock(catalogue, engineText);
  let next = html;
  let status = "current";
  const found = findEngineBlock(next);
  if (found !== null) {
    const same = next.slice(found.start, found.end) === block;
    if (!same) {
      next = next.slice(0, found.start) + block + next.slice(found.end);
      status = "refreshed";
    }
  } else {
    const helperLine = next.indexOf(STORE_HELPER_LINE);
    const helperEnd = helperLine === -1 ? -1 : next.indexOf(STORE_HELPER_END, helperLine);
    if (helperEnd === -1) {
      return { html, status: "no-store-helper" };
    }
    const insertAt = helperEnd + STORE_HELPER_END.length;
    next = `${next.slice(0, insertAt)}\n${block.trimEnd()}${next.slice(insertAt)}`;
    status = "added";
  }
  if (!textOutsideEngine(next).includes(WATCH_CALL)) {
    const afterBlock = findEngineBlock(next);
    const wiring =
      "// The person's settings, drawn now and again whenever settings:self changes (repair lanes W5)\n" +
      "var settingsWatch = MidasSettings.watch({ catalogue: SETTINGS_CATALOGUE, read: function readSettingsRecord() { return store.get(MidasSettings.RECORD_KEY); } });\n";
    next = next.slice(0, afterBlock.end) + wiring + next.slice(afterBlock.end);
    if (status === "current") {
      status = "refreshed";
    }
  }
  return { html: next, status };
}

/* ---------- tools.js ---------- */

// tools.js with the engine block (between copied markers, before everything else) and the
// attachTools call before its export. Returns { toolsText, status } ("current", "added",
// "refreshed", or "no-export" when the file does not end the way every tools.js does).
export function toolsWithEngine(toolsText, sidekickId, catalogue, options = {}, engineText = currentSettingsEngine()) {
  const block = engineBlock(catalogue, engineText);
  let next = toolsText;
  let status = "current";
  const found = findEngineBlock(next);
  if (found !== null) {
    if (next.slice(found.start, found.end) !== block) {
      next = next.slice(0, found.start) + block + next.slice(found.end);
      status = "refreshed";
    }
  } else {
    const toolsStart = next.indexOf("var MidasSidekickTools");
    if (toolsStart === -1) {
      return { toolsText, status: "no-export" };
    }
    const copied = `${COPY_BEGIN}\n${block}${COPY_END}\n\n`;
    next = next.slice(0, toolsStart) + copied + next.slice(toolsStart);
    status = "added";
  }
  if (!textOutsideEngine(next).includes(ATTACH_CALL)) {
    const exportAt = next.lastIndexOf(TOOLS_EXPORT_LINE);
    if (exportAt === -1) {
      return { toolsText, status: "no-export" };
    }
    const ownKeys = Array.isArray(options.ownKeys) ? `, ownKeys: ${JSON.stringify(options.ownKeys)}` : "";
    const attach =
      "// The settings engine's set_setting, and \"turned off\" for a hidden feature's tool (repair lanes W5)\n" +
      `${ATTACH_CALL}MidasSidekickTools, { sidekickId: ${JSON.stringify(sidekickId)}, catalogue: SETTINGS_CATALOGUE${ownKeys} });\n\n`;
    next = next.slice(0, exportAt) + attach + next.slice(exportAt);
    if (status === "current") {
      status = "refreshed";
    }
  }
  return { toolsText: next, status };
}
