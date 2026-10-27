// Water, founder decisions 2026-10-27 (docs/WIDGETS.md, "Add to Home Screen"):
// - "in the water, there are still two options, like Water Today and Water Week, which should not
//   be the case": one widget, "Water" (widget:today; small and medium the day, large the week),
//   and the page deletes the old widget:week.
// - "remove the add to home screen +" from Settings.
// Water's help menu replaces the title and the Widget button (docs/PRODUCT.md, founder 2026-10-27,
// commit f4cb805; docs/DESIGN.md 1a): "I like the question mark... Add Widget and How Water Works...
// the small menu... Design should be subtle... I like the 1-day streak on the top left instead of the
// water itself." The streak sits on the left, a quiet "?" on the right opens Add Widget (only on a
// build with the sheet) and How Water Works; the bottom bar is Log and Settings only, and the page no
// longer asks the shell { op: 'widget-placed' }.
// The page runs in Node against a fake shell that answers the store protocol; it still answers
// widget-placed and counts the asks, so a page that asks again is caught.
process.env.TZ = "America/Los_Angeles";

import { readFileSync } from "node:fs";
import vm from "node:vm";
import { describe, expect, it } from "vitest";
import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import MidasShellTypes from "../../shell/sdk/shell-types.js";

const html = readFileSync(new URL("../../sidekicks/hydration/index.html", import.meta.url), "utf8");
const toolsSource = readFileSync(new URL("../../sidekicks/hydration/tools.js", import.meta.url), "utf8");
const HOME_SCREEN_KIND = "home-screen.widget";
const BOTTOM_WITHOUT_WIDGET = '<div class="bottom"><button data-action="show-log">Log</button><button data-action="show-settings">Settings</button></div>';

type Value = Record<string, unknown>;
type StoreRequest = { op: string; key?: string; value?: Value; patch?: Value; prefix?: string };
type Op = { op: string; key: string };
// with-sheet: this build; no-placed-op: a build with the sheet but before widget-placed (build 18/19);
// older: before the sheet
type ShellBuild = "with-sheet" | "no-placed-op" | "older";
type Handler = (event: unknown) => void;

function waterLogicSource(pageHtml: string) {
  const start = pageHtml.indexOf("var WaterLogic = (function createWaterLogic() {");
  const end = pageHtml.indexOf("\n})();\n", start) + "\n})();\n".length;
  return pageHtml.slice(start, end);
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const Logic: any = vm.runInNewContext(waterLogicSource(html) + "\n;WaterLogic;", {});

function pageScript(pageHtml: string) {
  const start = pageHtml.indexOf("<script>") + "<script>".length;
  const end = pageHtml.indexOf("</script>", start);
  return pageHtml.slice(start, end);
}

function settingsValue(): Value {
  return {
    $type: "hydration.settings", goalMl: 2500, unit: "ml", presetsMl: [250, 500, 750], remindStart: "09:00", remindEnd: "21:00",
    everyHours: 2, remindersOn: true, createdAt: "2026-10-01T00:00:00.000Z",
  };
}

function fakeShell(build: ShellBuild, startRecords: Map<string, Value>) {
  const records = startRecords;
  const ops: Op[] = [];
  const placement = { placed: false, asked: 0 };

  function answer(request: StoreRequest): Value {
    if (request.op === "shell") {
      if (build === "older") {
        return { ok: false, error: "unknown op shell" };
      }
      return { ok: true, requests: ["import.apple-reminders", HOME_SCREEN_KIND] };
    }
    if (request.op === "widget-placed") {
      placement.asked += 1;
      if (build !== "with-sheet") {
        return { ok: false, error: "unknown op widget-placed" };
      }
      return { ok: true, placed: placement.placed };
    }
    const key = String(request.key ?? "");
    if (request.op === "set") {
      const value = JSON.parse(JSON.stringify(request.value)) as Value;
      ops.push({ op: "set", key });
      records.set(key, value);
      if (key.startsWith("request:") && value.kind === HOME_SCREEN_KIND) {
        records.set(key, { ...value, status: "done" });
      }
      return { ok: true };
    }
    if (request.op === "get") {
      return { ok: true, value: records.has(key) ? records.get(key) : null };
    }
    if (request.op === "delete") {
      ops.push({ op: "delete", key });
      records.delete(key);
      return { ok: true };
    }
    if (request.op === "update") {
      const merged = { ...(records.get(key) ?? {}), ...(request.patch ?? {}) };
      ops.push({ op: "update", key });
      records.set(key, merged);
      return { ok: true, value: merged };
    }
    if (request.op === "query") {
      const prefix = String(request.prefix ?? "");
      const found: Array<{ key: string; value: Value }> = [];
      const keys = Array.from(records.keys());
      keys.sort();
      for (const recordKey of keys) {
        if (recordKey.startsWith(prefix)) {
          found.push({ key: recordKey, value: records.get(recordKey) as Value });
        }
      }
      return { ok: true, records: found };
    }
    return { ok: false, error: "unknown op " + request.op };
  }

  async function fetchFromPage(url: string, options: { body: string }) {
    expect(url).toBe("sidekick://hydration/_midas/store");
    const reply = answer(JSON.parse(options.body) as StoreRequest);
    return { json: async () => reply };
  }

  return { records, ops, placement, fetchFromPage };
}

function loadPage(build: ShellBuild, placed: boolean, extraRecords: Array<[string, Value]> = []) {
  const startRecords = new Map<string, Value>();
  startRecords.set("settings:main", settingsValue());
  for (const [key, value] of extraRecords) {
    startRecords.set(key, value);
  }
  const shell = fakeShell(build, startRecords);
  shell.placement.placed = placed;
  const elements = new Map<string, { innerHTML: string; setAttribute: () => void }>();
  const documentHandlers = new Map<string, Handler>();
  const fakeDocument = { hidden: false, getElementById: elementById, addEventListener: addDocumentListener };

  function elementById(id: string) {
    if (!elements.has(id)) {
      elements.set(id, { innerHTML: "", setAttribute() {} });
    }
    return elements.get(id);
  }

  function addDocumentListener(name: string, handler: Handler) {
    documentHandlers.set(name, handler);
  }

  function ignore() {
    // the page's timers, scrolling and resize are not part of these checks
  }

  const sandbox: Value = {
    window: { location: { origin: "sidekick://hydration" }, innerWidth: 402, innerHeight: 874, addEventListener: ignore, scrollTo: ignore },
    document: fakeDocument,
    fetch: shell.fetchFromPage,
    console: { warn: ignore, log: ignore },
    setTimeout, clearTimeout, setInterval: ignore,
    Intl, Date, Math, JSON, Promise, Array, Object, String, Number,
  };
  vm.createContext(sandbox);
  vm.runInContext(pageScript(html) + "\n;globalThis.__app = WaterApp;", sandbox);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const app = sandbox.__app as any;

  function mainHtml() {
    return elementById("main")?.innerHTML ?? "";
  }

  // The bottom bar's markup on Today
  function bottomBar() {
    const match = /<div class="bottom">[\s\S]*?<\/div>/.exec(mainHtml());
    return match ? match[0] : "";
  }

  function tap(action: string) {
    const target = { tagName: "BUTTON", dataset: { action } };
    const clickHandler = documentHandlers.get("click") as Handler;
    clickHandler({ target: { closest: () => target } });
  }

  // The page coming back on screen, as WebKit tells it
  function becomeVisible() {
    const visibilityHandler = documentHandlers.get("visibilitychange") as Handler;
    visibilityHandler({});
  }

  return { app, shell, mainHtml, bottomBar, tap, becomeVisible };
}

async function settled(check: () => boolean) {
  for (let attempt = 0; attempt < 200; attempt += 1) {
    if (check()) {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, 1));
  }
}

async function openToday(build: ShellBuild, placed: boolean, extraRecords: Array<[string, Value]> = []) {
  const page = loadPage(build, placed, extraRecords);
  await page.app.whenReady();
  return page;
}

describe("Water: the ? menu on Today", () => {
  // The menu's markup from Today, or "" while it is closed
  function topRow(page: { mainHtml: () => string }) {
    const html = page.mainHtml();
    const end = html.indexOf('<div class="visual">');
    return end < 0 ? "" : html.slice(0, end);
  }

  it("has no Water title, a ? in the top row, Log and Settings alone in the bar, menu closed, with or without a widget", async () => {
    for (const placed of [false, true]) {
      const page = await openToday("with-sheet", placed);
      expect(page.app.state().view, String(placed)).toBe("today");
      expect(page.mainHtml(), String(placed)).not.toContain('class="title"');
      expect(topRow(page), String(placed)).toContain('data-action="toggle-help"');
      expect(page.bottomBar(), String(placed)).toBe(BOTTOM_WITHOUT_WIDGET);
      expect(page.app.state().helpOpen, String(placed)).toBe(false);
      expect(page.mainHtml(), String(placed)).not.toContain("add-home-screen");
    }
  });

  it("opens with Add Widget before How Water Works, also when a widget is placed, and closes on a tap outside", async () => {
    for (const placed of [false, true]) {
      const page = await openToday("with-sheet", placed);
      page.tap("toggle-help");
      expect(page.app.state().helpOpen, String(placed)).toBe(true);
      const menu = topRow(page);
      expect(menu, String(placed)).toContain('data-action="add-home-screen"');
      expect(menu, String(placed)).toContain("Add Widget");
      expect(menu, String(placed)).toContain('data-action="show-how"');
      expect(menu.indexOf("Add Widget"), String(placed)).toBeLessThan(menu.indexOf("How Water Works"));
      expect(page.bottomBar(), String(placed)).toBe(BOTTOM_WITHOUT_WIDGET);
      page.tap("close-help");
      expect(page.app.state().helpOpen, String(placed)).toBe(false);
      expect(page.mainHtml(), String(placed)).not.toContain("add-home-screen");
      expect(page.mainHtml(), String(placed)).not.toContain("show-how");
    }
  });

  it("never asks the shell whether the widget is placed, on open or back on screen", async () => {
    const page = await openToday("with-sheet", false);
    expect(page.shell.placement.asked).toBe(0);
    page.shell.placement.placed = true;
    page.becomeVisible();
    await new Promise((resolve) => setTimeout(resolve, 20));
    expect(page.shell.placement.asked).toBe(0);
    expect(page.bottomBar()).toBe(BOTTOM_WITHOUT_WIDGET);
  });

  it("offers Add Widget only on a build with the sheet, How Water Works on every build", async () => {
    const older = await openToday("older", false);
    older.tap("toggle-help");
    expect(topRow(older)).toContain('data-action="show-how"');
    expect(older.mainHtml()).not.toContain("add-home-screen");
    const noPlacedOp = await openToday("no-placed-op", false);
    noPlacedOp.tap("toggle-help");
    expect(topRow(noPlacedOp)).toContain('data-action="add-home-screen"');
    expect(topRow(noPlacedOp)).toContain("Add Widget");
  });

  it("How Water Works opens its own screen, and Today comes back from it", async () => {
    const page = await openToday("with-sheet", false);
    page.tap("toggle-help");
    page.tap("show-how");
    expect(page.app.state().view).toBe("how");
    expect(page.app.state().helpOpen).toBe(false);
    expect(page.mainHtml()).toContain("How Water Works");
    expect(page.mainHtml()).toContain("Reminders come every 2 hours");
    expect(page.mainHtml()).not.toContain('data-action="toggle-help"');
    page.tap("show-today");
    expect(page.app.state().view).toBe("today");
    expect(page.mainHtml()).toContain('data-action="toggle-help"');
  });

  it("draws the ? quiet: the help chip, no accent class (docs/DESIGN.md 1a)", async () => {
    const page = await openToday("with-sheet", false);
    const button = /<button class="help"[^>]*>\?<\/button>/.exec(page.mainHtml());
    expect(button).not.toBeNull();
    expect((button as RegExpExecArray)[0]).not.toMatch(/accent|primary|badge|dot/);
  });

  it("writes the Add to Home Screen request from Today", async () => {
    const page = await openToday("with-sheet", false);
    page.tap("add-home-screen");
    function isRequestDelete(op: Op) {
      return op.op === "delete" && op.key.startsWith("request:");
    }
    function isRequestSet(op: Op) {
      return op.op === "set" && op.key.startsWith("request:");
    }
    function requestWasDeleted() {
      return page.shell.ops.some(isRequestDelete);
    }
    await settled(requestWasDeleted);
    const requestSets = page.shell.ops.filter(isRequestSet);
    expect(requestSets.length).toBe(1);
  });

  it("shows no button on a build without the sheet, and does not ask there", async () => {
    const page = await openToday("older", false);
    expect(page.bottomBar()).toBe(BOTTOM_WITHOUT_WIDGET);
    expect(page.shell.placement.asked).toBe(0);
  });

  it("has no Widget section or Add to Home Screen row in Settings", async () => {
    const page = await openToday("with-sheet", false);
    page.app.show("settings");
    expect(page.mainHtml()).toContain("Reminders");
    expect(page.mainHtml()).not.toContain("Add to Home Screen");
    expect(page.mainHtml()).not.toContain('<div class="lab">Widget</div>');
    expect(page.mainHtml()).not.toContain("add-home-screen");
  });
});

describe("Water: one widget", () => {
  function settingsFor(unit: string) {
    return Logic.settingsFrom({ unit, goalMl: 2500 });
  }

  function widgetsFor(unit: string): Array<{ key: string; value: Value; plain: Value }> {
    return JSON.parse(JSON.stringify(Logic.widgetRecords(settingsFor(unit))));
  }

  it("writes one widget, widget:today named Water, in small, medium and large", () => {
    for (const unit of ["ml", "l", "oz"]) {
      const widgets = widgetsFor(unit);
      expect(widgets.length, unit).toBe(1);
      expect(widgets[0].key).toBe("widget:today");
      for (const value of [widgets[0].value, widgets[0].plain]) {
        expect(value.name).toBe("Water");
        expect([Boolean(value.small), Boolean(value.medium), Boolean(value.large)]).toEqual([true, true, true]);
        const stamped = MidasRecordSchema.stampType(MidasShellTypes, "widget:today", value);
        expect(MidasRecordSchema.checkRecord(MidasShellTypes, "widget:today", stamped)).toBeNull();
      }
    }
  });

  it("small and medium show the day, large adds the week chart", () => {
    const widget = widgetsFor("l")[0];
    // The chart colour: light and dark in value, the system accent in plain (founder, 2026-10-27)
    const chartPieces = [
      { value: widget.value, chart: '{"chart":"$week.values","color":{"light":"#2F7E87","dark":"#5FB3BA"}}' },
      { value: widget.plain, chart: '{"chart":"$week.values","color":"accent"}' },
    ];
    for (const { value, chart } of chartPieces) {
      expect(JSON.stringify(value.small)).not.toContain("$week");
      expect(JSON.stringify(value.medium)).not.toContain("$week");
      expect(JSON.stringify(value.large)).toContain(chart);
      expect((value.sources as Value).week).toEqual({ records: "water:", sum: "ml", limit: 7 });
    }
    // The Tide look keeps the sea on every size
    for (const size of ["small", "medium", "large"]) {
      expect((widget.value[size] as Value).fill, size).toEqual({ value: "$day.ml", of: "$settings.goalMl" });
    }
  });

  it("retires widget:week", () => {
    expect(Logic.RETIRED_WIDGET_KEYS).toEqual(["widget:week"]);
  });

  it("deletes widget:week on open when a person still has it, and writes the one widget", async () => {
    const oldWeek: Value = { $type: "midas.widget", version: 1, name: "Water this week", large: { text: "week" } };
    const page = await openToday("with-sheet", false, [["widget:week", oldWeek]]);
    expect(page.shell.records.has("widget:week")).toBe(false);
    expect(page.shell.ops).toContainEqual({ op: "delete", key: "widget:week" });
    const written = page.shell.records.get("widget:today") as Value;
    expect(written.name).toBe("Water");
    expect(Boolean(written.large)).toBe(true);
  });

  it("deletes nothing when there is no widget:week", async () => {
    const page = await openToday("with-sheet", false);
    function isDelete(op: Op) {
      return op.op === "delete";
    }
    const deletes = page.shell.ops.filter(isDelete);
    expect(deletes).toEqual([]);
  });

  it("keeps tools.js's copied WaterLogic identical to the page", () => {
    const pageBlock = waterLogicSource(html);
    expect(pageBlock).toContain("RETIRED_WIDGET_KEYS");
    expect(toolsSource).toContain(pageBlock);
  });
});
