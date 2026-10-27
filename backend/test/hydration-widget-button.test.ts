// Water, founder decisions 2026-10-27 (docs/WIDGETS.md, "Add to Home Screen"):
// - "in the water, there are still two options, like Water Today and Water Week, which should not
//   be the case": one widget, "Water" (widget:today; small and medium the day, large the week),
//   and the page deletes the old widget:week.
// - "remove the add to home screen +" from Settings; "Let's go with A [a Widget button in Water's
//   bottom bar] ... It should only be visible until the widget is added. Also, the log and settings
//   should rearrange once the widget button is removed."
// The page runs in Node against a fake shell that answers the store protocol, including
// { op: 'widget-placed' } (shell/Midas/HomeScreenWidgetPlacement.swift).
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

describe("Water: the Widget button on Today", () => {
  it("shows Widget after Log and Settings while no Water widget is placed", async () => {
    const page = await openToday("with-sheet", false);
    expect(page.app.state().view).toBe("today");
    expect(page.app.state().widgetPlaced).toBe(false);
    const bottom = page.bottomBar();
    expect(bottom).toContain('<button data-action="add-home-screen">');
    expect(bottom).toMatch(/<button data-action="add-home-screen"><svg[^>]*>(<rect [^>]*\/>){4}<\/svg>Widget<\/button><\/div>$/);
    expect(bottom.indexOf("show-log")).toBeLessThan(bottom.indexOf("show-settings"));
    expect(bottom.indexOf("show-settings")).toBeLessThan(bottom.indexOf("add-home-screen"));
  });

  it("is gone once a Water widget is placed, Log and Settings alone in the bar", async () => {
    const page = await openToday("with-sheet", true);
    expect(page.app.state().widgetPlaced).toBe(true);
    expect(page.bottomBar()).toBe(BOTTOM_WITHOUT_WIDGET);
    expect(page.mainHtml()).not.toContain("add-home-screen");
  });

  it("asks again when the page is back on screen, and hides the button after the widget was added", async () => {
    const page = await openToday("with-sheet", false);
    expect(page.bottomBar()).toContain("add-home-screen");
    const askedOnOpen = page.shell.placement.asked;
    expect(askedOnOpen).toBe(1);
    page.shell.placement.placed = true;
    page.becomeVisible();
    await settled(() => !page.bottomBar().includes("add-home-screen"));
    expect(page.shell.placement.asked).toBe(askedOnOpen + 1);
    expect(page.bottomBar()).toBe(BOTTOM_WITHOUT_WIDGET);
  });

  it("comes back if the widget is removed from the Home Screen", async () => {
    const page = await openToday("with-sheet", true);
    page.shell.placement.placed = false;
    page.becomeVisible();
    await settled(() => page.bottomBar().includes("add-home-screen"));
    expect(page.bottomBar()).toContain("add-home-screen");
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

  it("shows no button on a build with the sheet that cannot tell whether the widget is placed", async () => {
    const page = await openToday("no-placed-op", false);
    expect(page.app.state().homeScreen).toBe(true);
    expect(page.app.state().widgetPlaced).toBeNull();
    expect(page.bottomBar()).toBe(BOTTOM_WITHOUT_WIDGET);
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
    for (const value of [widget.value, widget.plain]) {
      expect(JSON.stringify(value.small)).not.toContain("$week");
      expect(JSON.stringify(value.medium)).not.toContain("$week");
      expect(JSON.stringify(value.large)).toContain('{"chart":"$week.values","color":"accent"}');
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
