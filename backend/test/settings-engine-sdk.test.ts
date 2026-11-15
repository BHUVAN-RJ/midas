import { readFileSync } from "node:fs";
import vm from "node:vm";
import { describe, expect, it } from "vitest";
import MidasSettings from "../../shell/sdk/midas-settings.js";
import type { SettingsCatalogue } from "../../shell/sdk/midas-settings.js";
import {
  engineBlock,
  findEngineBlock,
  manifestWithSettings,
  pageWithEngine,
  textOutsideEngine,
  toolsWithEngine,
  WATCH_CALL,
  ATTACH_CALL,
} from "../scripts/settings-engine-tools.mjs";
import { loadToolsScript } from "../scripts/bundle-tools.mjs";

// The settings engine (repair lanes W5, founder D1 2026-11-13): shell/sdk/midas-settings.js, pasted
// into every Sidekick page and tools.js. One catalogue per Sidekick (manifest.json "settings"); one
// record (settings:self); colours, sizes and hidden parts drawn as a style sheet; set_setting core;
// a hidden feature's tool answers "turned off".

const CATALOGUE: SettingsCatalogue = {
  entries: [
    { key: "title.colour", label: "Title colour", type: "colour", part: "title", selector: ".title", css: "color", default: "#111111" },
    { key: "title.size", label: "Title size", type: "size", part: "title", selector: ".title", default: "m" },
    { key: "search.show", label: "Search tab", type: "show", part: "search", selector: ".search-tab", default: true, tools: ["demo.search"] },
    { key: "dates.format", label: "Date format", type: "dateFormat", part: "dates", default: "auto" },
    { key: "look", label: "Look", type: "choice", part: "page", values: ["paper", "soft"], default: "paper" },
  ],
};

describe("the catalogue", () => {
  it("accepts a good catalogue", () => {
    expect(MidasSettings.catalogueProblems(CATALOGUE)).toEqual([]);
  });

  it("refuses what the engine could not draw or check", () => {
    const cases: Array<[unknown, string]> = [
      [{ entries: [] }, "at least one setting"],
      [{ entries: [{ ...CATALOGUE.entries[0], key: "Title colour" }] }, ".key must be a name"],
      [{ entries: [CATALOGUE.entries[0], CATALOGUE.entries[0]] }, "listed twice"],
      [{ entries: [{ ...CATALOGUE.entries[0], type: "font" }] }, ".type must be one of"],
      [{ entries: [{ ...CATALOGUE.entries[0], selector: ".title { background: url(x) }" }] }, "plain CSS selector"],
      [{ entries: [{ ...CATALOGUE.entries[0], css: "color; background" }] }, ".css must name"],
      [{ entries: [{ ...CATALOGUE.entries[0], default: "blue" }] }, ".default must be one of"],
      [{ entries: [{ ...CATALOGUE.entries[1], values: ["s", "huge"] }] }, 'has "huge", not a size'],
      [{ entries: [{ ...CATALOGUE.entries[3], selector: ".date" }] }, "read by the page"],
      [{ entries: [{ ...CATALOGUE.entries[0], tools: ["demo.search"] }] }, ".tools is a list, for show only"],
      [{ entries: [{ ...CATALOGUE.entries[4], values: undefined }] }, "needs values"],
    ];
    for (const [catalogue, expected] of cases) {
      const problems = MidasSettings.catalogueProblems(catalogue);
      expect(problems.join(" | "), expected).toContain(expected);
    }
  });
});

describe("values", () => {
  it("reads a person's words into the catalogue's values", () => {
    const [colour, size, show, , choice] = CATALOGUE.entries;
    expect(MidasSettings.checkValue(colour, "#1e6fd9")).toEqual({ value: "#1E6FD9" });
    expect(MidasSettings.checkValue(colour, "blue").problem).toContain("takes a colour");
    expect(MidasSettings.checkValue(size, "xl")).toEqual({ value: "xl" });
    expect(MidasSettings.checkValue(size, "huge").problem).toContain("takes s, m, l, xl");
    expect(MidasSettings.checkValue(show, "hide")).toEqual({ value: false });
    expect(MidasSettings.checkValue(show, true)).toEqual({ value: true });
    expect(MidasSettings.checkValue(show, "maybe").problem).toContain("on or off");
    expect(MidasSettings.checkValue(choice, "Soft")).toEqual({ value: "soft" });
  });

  it("gives the default for a missing or broken stored value", () => {
    const values = MidasSettings.valuesFrom(CATALOGUE, { "title.size": "l", "title.colour": "red" });
    expect(values["title.size"]).toBe("l");
    expect(values["title.colour"]).toBe("#111111");
    expect(values["search.show"]).toBe(true);
  });

  it("changes only the keys it is given, removes a key set to null, adds alsoSet", () => {
    const record = { $type: "demo.settings", order: ["a", "b"], "title.size": "l" };
    const catalogue = { ...CATALOGUE, alsoSet: { preset: "custom" } };
    const next = MidasSettings.recordWith(catalogue, record, { "title.colour": "#1E6FD9", "title.size": null });
    expect(next).toEqual({ $type: "demo.settings", order: ["a", "b"], "title.colour": "#1E6FD9", preset: "custom" });
    expect(record["title.size"]).toBe("l");
  });

  it("gives each key the JSON Schema the manifest declares for it", () => {
    expect(MidasSettings.propertySchemaFor(CATALOGUE.entries[0])).toEqual({ type: "string", pattern: "^#[0-9A-Fa-f]{6}$" });
    expect(MidasSettings.propertySchemaFor(CATALOGUE.entries[1])).toEqual({ type: "string", enum: ["s", "m", "l", "xl"] });
    expect(MidasSettings.propertySchemaFor(CATALOGUE.entries[2])).toEqual({ type: "boolean" });
  });
});

describe("drawing", () => {
  it("draws only what the person changed, as a style sheet over the named parts", () => {
    expect(MidasSettings.cssFor(CATALOGUE, null)).toBe("");
    const css = MidasSettings.cssFor(CATALOGUE, { "title.colour": "#1e6fd9", "title.size": "xl", "search.show": false, look: "soft" });
    expect(css).toContain(".title { color: #1E6FD9 !important; }");
    expect(css).toContain(".title { zoom: 1.4 !important; }");
    expect(css).toContain(".search-tab { display: none !important; }");
    expect(css).not.toContain("soft");
  });

  it("sets every property a colour names", () => {
    const sea = { key: "sea.colour", label: "Sea", type: "colour" as const, part: "sea", selector: ":root", css: ["--sea-top", "--sea-bottom"], default: "#000000" };
    const css = MidasSettings.cssFor({ entries: [sea] }, { "sea.colour": "#1E6FD9" });
    expect(css).toBe(":root { --sea-top: #1E6FD9 !important; --sea-bottom: #1E6FD9 !important; }");
  });

  it("formats dates in the chosen format, and leaves auto to the page", () => {
    const date = new Date(2026, 10, 13, 12, 0);
    expect(MidasSettings.formatDate(CATALOGUE, null, "dates.format", date)).toBeNull();
    const expected: Record<string, string> = {
      "day-month": "13 Nov",
      "month-day": "Nov 13",
      "day-month-year": "13 Nov 2026",
      "month-day-year": "Nov 13, 2026",
      "weekday-day-month": "Fri 13 Nov",
      "weekday-month-day": "Fri, Nov 13",
      "numeric-day-first": "13/11/2026",
      "numeric-month-first": "11/13/2026",
    };
    for (const [format, text] of Object.entries(expected)) {
      expect(MidasSettings.formatDate(CATALOGUE, { "dates.format": format }, "dates.format", date)).toBe(text);
    }
  });
});

// A page with just enough DOM for the engine: one <style> element, visibility, timers
function makePage() {
  const appended: Array<{ id: string; textContent: string }> = [];
  const listeners: Record<string, () => void> = {};
  const intervals: Array<() => void> = [];
  const page = {
    hidden: false,
    head: {
      appendChild(element: { id: string; textContent: string }) {
        if (!appended.includes(element)) {
          appended.push(element);
        }
      },
    },
    getElementById(id: string) {
      return appended.find(function hasId(element) {
        return element.id === id;
      }) ?? null;
    },
    createElement() {
      return { id: "", textContent: "" };
    },
    addEventListener(name: string, listener: () => void) {
      listeners[name] = listener;
    },
    removeEventListener() {},
  };
  function setInterval(callback: () => void) {
    intervals.push(callback);
    return intervals.length;
  }
  function clearInterval() {}
  const sandbox = { document: page, setInterval, clearInterval, JSON, Promise, Object, Array, String };
  vm.createContext(sandbox);
  const engineText = readFileSync(new URL("../../shell/sdk/midas-settings.js", import.meta.url), "utf8");
  vm.runInContext(`${engineText}\n;globalThis.__engine = MidasSettings;`, sandbox);
  return { engine: (sandbox as unknown as { __engine: typeof MidasSettings }).__engine, page, appended, intervals };
}

describe("the page redraws live when settings:self changes", () => {
  it("draws at once, then again on a change, and calls the page back only for a change", async () => {
    const { engine, page, appended, intervals } = makePage();
    let stored: Record<string, unknown> | null = null;
    const changes: Array<Record<string, unknown>> = [];
    async function read() {
      return stored;
    }
    function onChange(values: Record<string, unknown>) {
      changes.push(values);
    }
    const watch = engine.watch({ catalogue: CATALOGUE, read, onChange }) as { ready: Promise<void>; check(): Promise<void> };
    await watch.ready;
    expect(appended.length).toBe(1);
    expect(appended[0].id).toBe("midas-settings");
    expect(appended[0].textContent).toBe("");
    expect(changes.length).toBe(0);

    stored = { "search.show": false };
    await watch.check();
    expect(appended[0].textContent).toBe(".search-tab { display: none !important; }");
    expect(changes.length).toBe(1);
    expect(changes[0]["search.show"]).toBe(false);

    await watch.check();
    expect(changes.length).toBe(1);
    expect(intervals.length).toBe(1);
    page.hidden = true;
    stored = { "search.show": true };
    intervals[0]();
    await Promise.resolve();
    expect(changes.length).toBe(1);
  });

  it("keeps the page's last settings when a read fails", async () => {
    const { engine, appended } = makePage();
    let failing = false;
    async function read() {
      if (failing) {
        throw new Error("shell busy");
      }
      return { "title.size": "l" };
    }
    const watch = engine.watch({ catalogue: CATALOGUE, read }) as { ready: Promise<void>; check(): Promise<void> };
    await watch.ready;
    failing = true;
    await watch.check();
    expect(appended[0].textContent).toBe(".title { zoom: 1.2 !important; }");
  });
});

describe("tools: set_setting and turned off", () => {
  function demoTools() {
    function search() {
      return { result: { text: "Found 2" } };
    }
    function ownSetting() {
      return { result: { text: "Make It Yours" } };
    }
    return { context() { return {}; }, handlers: { search, set_setting: ownSetting } };
  }

  it("set_setting writes settings:self with the other fields kept", () => {
    const tools = MidasSettings.attachTools({ handlers: {} }, { sidekickId: "demo", catalogue: CATALOGUE }) as { handlers: Record<string, (input: unknown, records: unknown) => { ops?: Array<{ key: string; value: Record<string, unknown> }>; refused?: string; result: { text: string } }> };
    const records = [{ key: "settings:self", value: { $type: "demo.settings", order: ["x"] } }];
    const outcome = tools.handlers.set_setting({ key: "title.size", value: "l" }, records);
    expect(outcome.ops).toEqual([{ op: "set", key: "settings:self", value: { $type: "demo.settings", order: ["x"], "title.size": "l" } }]);
    expect(tools.handlers.set_setting({ key: "title.size", value: "huge" }, records).refused).toBe("value-not-offered");
    expect(tools.handlers.set_setting({ key: "nope", value: "l" }, records).refused).toBe("nothing-to-change");
    const already = [{ key: "settings:self", value: { "title.size": "l" } }];
    expect(tools.handlers.set_setting({ key: "title.size", value: "l" }, already).refused).toBe("nothing-to-change");
  });

  it("a hidden feature's tool answers turned off; the others and set_setting still work", () => {
    const tools = MidasSettings.attachTools(demoTools(), { sidekickId: "demo", catalogue: CATALOGUE, ownKeys: ["look"] }) as { handlers: Record<string, (input: unknown, records: unknown) => { refused?: string; result: { text: string } }> };
    const hidden = [{ key: "settings:self", value: { "search.show": false } }];
    expect(tools.handlers.search({}, hidden)).toEqual({ refused: "turned-off", result: { text: "Search tab is turned off" } });
    expect(tools.handlers.search({}, [])).toEqual({ result: { text: "Found 2" } });
    expect(tools.handlers.set_setting({ key: "search.show", value: "on" }, hidden).refused).toBeUndefined();
  });

  it("with the Sidekick's own set_setting, its own keys and presets stay its own", () => {
    const tools = MidasSettings.attachTools(demoTools(), { sidekickId: "demo", catalogue: CATALOGUE, ownKeys: ["look"] }) as { handlers: Record<string, (input: unknown, records: unknown) => { result: { text: string } }> };
    expect(tools.handlers.set_setting({ field: "look", value: "soft" }, []).result.text).toBe("Make It Yours");
    expect(tools.handlers.set_setting({ preset: "heat", field: null, value: null }, []).result.text).toBe("Make It Yours");
    expect(tools.handlers.set_setting({ field: "title.size", value: "l" }, []).result.text).toBe("Changed");
  });
});

describe("putting the engine into a page, tools.js and manifest", () => {
  const storeHelper = readFileSync(new URL("../../shell/sdk/midas-store.js", import.meta.url), "utf8").trim();
  const page = `<html><body><script>\n${storeHelper}\nvar App = 1;\n</script></body></html>`;
  const tools =
    "var MidasSidekickTools = (function createDemoTools() {\n  function search() { return { result: { text: 'ok' } }; }\n  return { context: function context() { return {}; }, handlers: { search: search } };\n})();\n\n" +
    "if (typeof module !== 'undefined' && module.exports) {\n  module.exports = MidasSidekickTools;\n}\n";

  it("pastes the engine after the store helper with the generic wiring, once", () => {
    const first = pageWithEngine(page, CATALOGUE);
    expect(first.status).toBe("added");
    const found = findEngineBlock(first.html);
    expect(found?.catalogue).toEqual(CATALOGUE);
    expect(first.html.indexOf(storeHelper)).toBeLessThan(found?.start ?? -1);
    expect(textOutsideEngine(first.html)).toContain(WATCH_CALL);
    const again = pageWithEngine(first.html, CATALOGUE);
    expect(again.status).toBe("current");
    expect(again.html).toBe(first.html);
    const newer = pageWithEngine(first.html, { entries: [CATALOGUE.entries[0]] });
    expect(newer.status).toBe("refreshed");
    expect(findEngineBlock(newer.html)?.catalogue.entries.length).toBe(1);
  });

  it("refuses a page without the store helper", () => {
    expect(pageWithEngine("<script>var x = 1;</script>", CATALOGUE).status).toBe("no-store-helper");
  });

  it("puts the same block into tools.js and attaches set_setting; the result loads and matches the page", () => {
    const pageResult = pageWithEngine(page, CATALOGUE);
    const toolsResult = toolsWithEngine(tools, "demo", CATALOGUE);
    expect(toolsResult.status).toBe("added");
    expect(textOutsideEngine(toolsResult.toolsText)).toContain(ATTACH_CALL);
    expect(pageResult.html).toContain(engineBlock(CATALOGUE));
    const loaded = loadToolsScript(toolsResult.toolsText) as { tools?: { handlers: Record<string, unknown> } };
    expect(Object.keys(loaded.tools?.handlers ?? {}).sort()).toEqual(["search", "set_setting"]);
    expect(toolsWithEngine(toolsResult.toolsText, "demo", CATALOGUE).status).toBe("current");
  });

  it("adds the catalogue keys to the settings: type, never narrowing a field already there", () => {
    const manifest = { id: "demo", types: { "settings:": { $type: "demo.settings", schema: { type: "object", properties: { $type: { type: "string" }, look: { type: "string" } } } } } };
    const next = manifestWithSettings(manifest, CATALOGUE) as { settings: unknown; types: Record<string, { schema: { properties: Record<string, unknown> } }> };
    expect(next.settings).toEqual(CATALOGUE);
    expect(next.types["settings:"].schema.properties.look).toEqual({ type: "string" });
    expect(next.types["settings:"].schema.properties["title.size"]).toEqual({ type: "string", enum: ["s", "m", "l", "xl"] });
    const bare = manifestWithSettings({ id: "demo", types: {} }, CATALOGUE) as { types: Record<string, { $type: string }> };
    expect(bare.types["settings:"].$type).toBe("demo.settings");
  });
});
