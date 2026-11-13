// The Dictation Sidekick (TEST, staging only; founder 2026-11-13, docs/briefs/dictation-sidekick-test.md).
// Its page, manifest and tools.js pass the deploy gate; the records the shell's Dictation Test
// screen writes (shell/Midas/DictationSidekick.swift, DictationRunRecord) fit the manifest's
// types and bad ones are refused; the two tools read the runs newest first with the same summary
// the page shows; the widget fits the shell's widget type and limits with pieces every build has;
// and the page, run in Node against a fake shell, asks for the native screen with a
// "test.dictation" request only on a build that carries it out, waits for the screen to close,
// then shows the runs it saved.
process.env.TZ = "America/Los_Angeles";

import { readFileSync } from "node:fs";
import vm from "node:vm";
import { describe, expect, it } from "vitest";
import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import MidasShellTypes from "../../shell/sdk/shell-types.js";
import { checkBundleFiles } from "../scripts/bundle-tools.mjs";
import { loadToolsScript } from "../scripts/sidekick-tools.mjs";

const folder = new URL("../../sidekicks/dictation/", import.meta.url);
const html = readFileSync(new URL("index.html", folder), "utf8");
const manifestText = readFileSync(new URL("manifest.json", folder), "utf8");
const toolsText = readFileSync(new URL("tools.js", folder), "utf8");
const manifest = JSON.parse(manifestText);
const shellSource = readFileSync(new URL("../../shell/Midas/DictationSidekick.swift", import.meta.url), "utf8");

const loaded = loadToolsScript(toolsText);
if (!("tools" in loaded)) {
  throw new Error(loaded.problem);
}
const tools = loaded.tools;

const TEST_KIND = "test.dictation";
const HOME_SCREEN_KIND = "home-screen.widget";
const NOW = "2026-11-13T22:00:00.000Z";

type Value = Record<string, unknown>;
type Records = Array<{ key: string; value: Value }>;
type Outcome = { ops?: unknown[]; refused?: string; result: { text: string; [field: string]: unknown } };

// A run exactly as DictationRunRecord.value writes it
function runValue(fields: Value = {}): Value {
  return {
    $type: "dictation.run", at: "2026-11-13T21:30:45.123Z", source: "phrase", raw: "uh tell mom im on my way",
    cleaned: "Tell Mom I'm on my way.", cleanupMs: 412, firstCall: false, modelStatus: "Available", device: "iPhone17,1",
    ios: "26.1", build: "24", ...fields,
  };
}

// Five runs, stored in key order; the newest by time is the spoken one at 21:40
function fixtureRecords(): Records {
  return [
    { key: "run:20261113T213000000Z-0001", value: runValue({ at: "2026-11-13T21:30:00.000Z", cleanupMs: 1900, firstCall: true }) },
    { key: "run:20261113T213100000Z-0002", value: runValue({ at: "2026-11-13T21:31:00.000Z", cleanupMs: 400, source: "run-all" }) },
    { key: "run:20261113T213200000Z-0003", value: runValue({ at: "2026-11-13T21:32:00.000Z", cleanupMs: 401, source: "run-all" }) },
    {
      key: "run:20261113T214000000Z-0004",
      value: runValue({ at: "2026-11-13T21:40:00.000Z", cleanupMs: 650, source: "spoken", releaseToRawMs: 230, totalMs: 900, raw: "um so like be there at 5 no wait 6", cleaned: "Be there at 6." }),
    },
    { key: "run:20261113T213500000Z-0005", value: runValue({ at: "2026-11-13T21:35:00.000Z", cleanupMs: 300 }) },
    { key: "summary:main", value: { $type: "dictation.summary", runs: 5 } },
    { key: "widget:summary", value: { $type: "midas.widget", name: "Dictation" } },
  ];
}

function schemaProblem(key: string, value: Value) {
  const stamped = MidasRecordSchema.stampType(manifest.types, key, value);
  return MidasRecordSchema.checkRecord(manifest.types, key, stamped);
}

function call(verb: string, input: Value, records: Records = fixtureRecords()): Outcome {
  const outcome = tools.handlers[verb](input, records, NOW);
  return JSON.parse(JSON.stringify(outcome));
}

describe("dictation: the bundle", () => {
  it("passes the deploy gate (page, manifest, agent block, tools.js and its copied block)", () => {
    const checked = checkBundleFiles(html, manifestText, "dictation", toolsText);
    expect(checked.problems).toEqual([]);
  });

  it("is a tile from the fixed palette with the waveform symbol", () => {
    expect(manifest.icon).toEqual({ symbol: "waveform", background: "#2E2E2E", backgroundDark: "#1F1F1F" });
    expect(manifest.name).toBe("Dictation");
  });

  it("shows the TEST tag and the one action, in the shell's palette", () => {
    expect(html).toContain('<span class="tag">TEST</span>');
    expect(html).toContain('data-action="open-test">Open Dictation Test</button>');
    expect(html).toContain("--paper: #FFFFFF; --ink: #111111;");
    expect(html).toContain("--paper: #111111; --ink: #FFFFFF;");
  });
});

describe("dictation: the records the shell writes", () => {
  it("takes a phrase run and a spoken run as DictationRunRecord writes them", () => {
    expect(schemaProblem("run:20261113T213045123Z-0001", runValue())).toBeNull();
    const spoken = runValue({ source: "spoken", releaseToRawMs: 230, totalMs: 900, firstCall: true });
    expect(schemaProblem("run:20261113T213045123Z-0002", spoken)).toBeNull();
    expect(schemaProblem("run:20261113T213045123Z-0003", runValue({ source: "run-all" }))).toBeNull();
  });

  it("takes the summary with and without runs", () => {
    const full = { runs: 5, lastCleanupMs: 650, averageCleanupMs: 730, worstCleanupMs: 1900, lastAt: "2026-11-13T21:40:00.000Z", updatedAt: NOW };
    expect(schemaProblem("summary:main", full)).toBeNull();
    expect(schemaProblem("summary:main", { runs: 0, updatedAt: NOW })).toBeNull();
  });

  it("refuses a run without its cleanup time, with an unknown source or with text over 4,000 characters", () => {
    const withoutCleanup = runValue();
    delete withoutCleanup.cleanupMs;
    expect(schemaProblem("run:x", withoutCleanup)).not.toBeNull();
    expect(schemaProblem("run:x", runValue({ source: "typed" }))).not.toBeNull();
    expect(schemaProblem("run:x", runValue({ raw: "a".repeat(4001) }))).not.toBeNull();
    expect(schemaProblem("run:x", runValue({ cleanupMs: -1 }))).not.toBeNull();
    expect(schemaProblem("run:x", runValue({ at: "yesterday" }))).not.toBeNull();
  });

  it("matches the shell's names: Sidekick id, prefixes, request kind, text cap", () => {
    expect(shellSource).toContain('static let sidekickId = "dictation"');
    expect(shellSource).toContain('static let keyPrefix = "run:"');
    expect(shellSource).toContain('static let summaryKey = "summary:main"');
    expect(shellSource).toContain('static let dictationTestKind = "test.dictation"');
    expect(shellSource).toContain("static let maxTextCharacters = 4000");
    expect(manifest.types["run:"].schema.properties.raw.maxLength).toBe(4000);
    expect(html).toContain("const TEST_REQUEST_KIND = 'test.dictation';");
  });
});

describe("dictation: tools", () => {
  it("summary: count, newest run's time, average rounded half up and worst, over every run", () => {
    const outcome = call("summary", {});
    expect(outcome.ops).toEqual([]);
    expect(outcome.refused).toBeUndefined();
    // (1900 + 400 + 401 + 650 + 300) / 5 = 730.2
    expect(outcome.result).toEqual({
      text: "5 runs. Last 650 ms, average 730 ms, worst 1,900 ms.", runs: 5, lastCleanupMs: 650, averageCleanupMs: 730, worstCleanupMs: 1900,
    });
  });

  it("summary: rounds .5 up, as the shell's summary record does", () => {
    const records = [
      { key: "run:a", value: runValue({ at: "2026-11-13T21:00:00.000Z", cleanupMs: 1 }) },
      { key: "run:b", value: runValue({ at: "2026-11-13T21:01:00.000Z", cleanupMs: 2 }) },
    ];
    expect(call("summary", {}, records).result.averageCleanupMs).toBe(2);
  });

  it("summary: no runs yet", () => {
    const outcome = call("summary", {}, []);
    expect(outcome.result.text).toBe("No runs yet");
    expect(outcome.result.runs).toBe(0);
    expect(outcome.result.averageCleanupMs).toBeNull();
  });

  it("runs: newest first by time, 10 by default, with the timings measured", () => {
    const outcome = call("runs", { limit: null });
    expect(outcome.ops).toEqual([]);
    const runs = outcome.result.runs as Value[];
    const times: unknown[] = [];
    for (const run of runs) {
      times.push(run.cleanupMs);
    }
    expect(times).toEqual([650, 300, 401, 400, 1900]);
    expect(runs[0]).toEqual({
      at: "2026-11-13T21:40:00.000Z", source: "Spoken", raw: "um so like be there at 5 no wait 6", cleaned: "Be there at 6.", cleanupMs: 650,
      firstCall: false, releaseToRawMs: 230, totalMs: 900,
    });
    expect(runs[4].firstCall).toBe(true);
    expect(String(outcome.result.text).split("\n")[0]).toBe("Cleanup 650 ms · Raw 230 ms · Total 900 ms · Spoken: Be there at 6.");
  });

  it("runs: a limit said is kept between 1 and 50", () => {
    expect((call("runs", { limit: 2 }).result.runs as Value[]).length).toBe(2);
    expect((call("runs", { limit: 0 }).result.runs as Value[]).length).toBe(1);
    const many: Records = [];
    for (let index = 0; index < 60; index += 1) {
      const minute = String(index).padStart(2, "0");
      many.push({ key: "run:" + minute, value: runValue({ at: "2026-11-13T20:" + minute + ":00.000Z", cleanupMs: index }) });
    }
    const capped = call("runs", { limit: 99 }, many).result.runs as Value[];
    expect(capped.length).toBe(50);
    expect(capped[0].cleanupMs).toBe(59);
  });

  it("runs: no runs yet", () => {
    expect(call("runs", { limit: null }, []).result).toEqual({ text: "No runs yet", runs: [] });
  });

  it("tells jess the summary", () => {
    expect(tools.context(fixtureRecords(), NOW)).toEqual({ runs: 5, lastCleanupMs: 650, averageCleanupMs: 730, worstCleanupMs: 1900 });
  });
});

// The widget, from the page's own code
function logicSource(pageHtml: string) {
  const start = pageHtml.indexOf("var DictationLogic = (function createDictationLogic() {");
  const end = pageHtml.indexOf("\n})();\n", start) + "\n})();\n".length;
  return pageHtml.slice(start, end);
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const Logic: any = vm.runInNewContext(logicSource(html) + "\n;DictationLogic;", { Intl, Date, Math, JSON, Number, Object, String, Array });
const EXISTING_PIECES = ["vstack", "hstack", "grid", "list", "spacer", "divider", "text", "symbol", "bar", "ring", "dots", "chart", "timer", "tick", "button"];

type Piece = Record<string, unknown>;

function piecesOf(piece: Piece, depth: number, found: Array<{ piece: Piece; depth: number }>) {
  found.push({ piece, depth });
  for (const name of ["vstack", "hstack", "grid"]) {
    if (Array.isArray(piece[name])) {
      for (const child of piece[name] as Piece[]) {
        piecesOf(child, depth + 1, found);
      }
    }
  }
  return found;
}

function pieceName(piece: Piece) {
  for (const name of EXISTING_PIECES) {
    if (name in piece) {
      return name;
    }
  }
  return "unknown";
}

describe("dictation: widget", () => {
  const widgets = Logic.widgetRecords();
  const widget = widgets[0].value;

  it("is one widget, widget:summary named Dictation, small and medium, reading summary:main", () => {
    expect(widgets.length).toBe(1);
    expect(widgets[0].key).toBe("widget:summary");
    expect(widget.name).toBe("Dictation");
    expect(widget.version).toBe(1);
    expect(widget.sources).toEqual({ summary: { record: "summary:main" } });
    expect(widget.small).toBeTruthy();
    expect(widget.medium).toBeTruthy();
  });

  it("fits the shell's widget record type", () => {
    const stamped = MidasRecordSchema.stampType(MidasShellTypes, "widget:summary", widget);
    expect(MidasRecordSchema.checkRecord(MidasShellTypes, "widget:summary", stamped)).toBeNull();
  });

  it("uses only pieces every build has, within the limits, with no colour of its own", () => {
    for (const size of ["small", "medium"]) {
      const found = piecesOf(widget[size], 0, []);
      expect(found.length).toBeLessThanOrEqual(150);
      for (const entry of found) {
        expect(pieceName(entry.piece), JSON.stringify(entry.piece)).not.toBe("unknown");
        expect(entry.depth).toBeLessThanOrEqual(12);
        if (entry.piece.color !== undefined) {
          expect(["primary", "secondary"]).toContain(entry.piece.color);
        }
        if (typeof entry.piece.text === "string") {
          expect((entry.piece.text as string).length).toBeLessThanOrEqual(200);
        }
      }
    }
    expect(widget.background).toBeUndefined();
  });

  it("small shows the last and average cleanup ms, and No Runs when there are none", () => {
    const texts: Piece[] = [];
    for (const entry of piecesOf(widget.small, 0, [])) {
      if (typeof entry.piece.text === "string") {
        texts.push(entry.piece);
      }
    }
    const byText = new Map<string, Piece>();
    for (const text of texts) {
      byText.set(text.text as string, text);
    }
    expect(byText.get("$summary.lastCleanupMs ms")?.if).toBe("$summary.runs");
    expect(byText.get("Avg $summary.averageCleanupMs ms")?.if).toBe("$summary.runs");
    expect(byText.get("No Runs")?.unless).toBe("$summary.runs");
  });

  it("is not rewritten when the stored one only adds the stamped type", () => {
    expect(Logic.sameWidget({ ...JSON.parse(JSON.stringify(widget)), $type: "midas.widget" }, widget)).toBe(true);
    expect(Logic.sameWidget({ ...JSON.parse(JSON.stringify(widget)), version: 0 }, widget)).toBe(false);
  });
});

/* ---------- The page against a fake shell ---------- */

type StoreRequest = { op: string; key?: string; value?: Value; prefix?: string };
type ShellBuild = "midas-test" | "midas" | "older";

function pageScript(pageHtml: string) {
  const start = pageHtml.indexOf("<script>") + "<script>".length;
  const end = pageHtml.indexOf("</script>", start);
  return pageHtml.slice(start, end);
}

function fakeShell(build: ShellBuild, initial: Records) {
  const records = new Map<string, Value>();
  for (const record of initial) {
    records.set(record.key, record.value);
  }
  const sets: Array<{ key: string; value: Value }> = [];
  const deletes: string[] = [];

  function answerShellOp(): Value {
    if (build === "older") {
      return { ok: false, error: "unknown op shell" };
    }
    if (build === "midas") {
      return { ok: true, requests: ["import.apple-reminders", HOME_SCREEN_KIND] };
    }
    return { ok: true, requests: ["import.apple-reminders", HOME_SCREEN_KIND, TEST_KIND] };
  }

  function answer(request: StoreRequest): Value {
    if (request.op === "shell") {
      return answerShellOp();
    }
    const key = String(request.key ?? "");
    if (request.op === "set") {
      const value = JSON.parse(JSON.stringify(request.value)) as Value;
      sets.push({ key, value: JSON.parse(JSON.stringify(value)) });
      records.set(key, value);
      // DictationTestCenter shows the screen and marks the request open before it replies
      if (key.startsWith("request:") && value.kind === TEST_KIND && build === "midas-test") {
        records.set(key, { ...value, status: "open" });
      }
      return { ok: true };
    }
    if (request.op === "get") {
      return { ok: true, value: records.has(key) ? records.get(key) : null };
    }
    if (request.op === "delete") {
      deletes.push(key);
      records.delete(key);
      return { ok: true };
    }
    if (request.op === "query") {
      const prefix = String(request.prefix ?? "");
      const found: Records = [];
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
    expect(url).toBe("sidekick://dictation/_midas/store");
    const reply = answer(JSON.parse(options.body) as StoreRequest);
    return { json: async () => reply };
  }

  return { records, sets, deletes, fetchFromPage };
}

type Handler = (event: unknown) => void;

function loadPage(build: ShellBuild, initial: Records = []) {
  const shell = fakeShell(build, initial);
  const elements = new Map<string, Value>();
  const documentHandlers = new Map<string, Handler>();

  function elementById(id: string) {
    if (!elements.has(id)) {
      elements.set(id, { innerHTML: "" });
    }
    return elements.get(id);
  }

  function addDocumentListener(name: string, handler: Handler) {
    documentHandlers.set(name, handler);
  }

  function ignore() {
    // the orb's frames, the poll timer and scrolling are not part of these checks
    return 0;
  }

  const sandbox: Value = {
    window: { location: { origin: "sidekick://dictation" }, scrollTo: ignore, requestAnimationFrame: ignore, devicePixelRatio: 3 },
    document: { hidden: false, getElementById: elementById, addEventListener: addDocumentListener },
    fetch: shell.fetchFromPage,
    console: { warn: ignore, log: ignore },
    setTimeout: ignore, clearTimeout: ignore,
    Intl, Date, Math, JSON, Promise, Array, Object, String, Number,
  };
  vm.createContext(sandbox);
  vm.runInContext(pageScript(html) + "\n;globalThis.__app = DictationApp;", sandbox);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const app = sandbox.__app as any;

  function mainHtml() {
    return String((elementById("main") as Value).innerHTML);
  }

  function tap(action: string) {
    const target = { tagName: "BUTTON", dataset: { action } };
    const clickHandler = documentHandlers.get("click") as Handler;
    clickHandler({ target: { closest: () => target } });
  }

  return { shell, app, mainHtml, tap };
}

function requestSets(shell: ReturnType<typeof fakeShell>) {
  const found: Array<{ key: string; value: Value }> = [];
  for (const set of shell.sets) {
    if (set.key.startsWith("request:")) {
      found.push(set);
    }
  }
  return found;
}

describe("dictation: the page", () => {
  it("on Midas Test: shows the button, writes the widget, lists the runs newest first with average and worst", async () => {
    const page = loadPage("midas-test", fixtureRecords());
    await page.app.whenReady();
    const html = page.mainHtml();
    expect(page.app.state().canOpenTest).toBe(true);
    expect(html).toContain('data-action="open-test">Open Dictation Test</button>');
    expect(html).toContain('<div class="n">5</div><div class="l">Runs</div>');
    expect(html).toContain('<div class="n">730 ms</div><div class="l">Average</div>');
    expect(html).toContain('<div class="n">1,900 ms</div><div class="l">Worst</div>');
    // Latest five, newest first: the spoken run leads
    expect(html.indexOf("Be there at 6.")).toBeLessThan(html.indexOf("Cleanup 300 ms"));
    expect(html).toContain("Cleanup 650 ms · Raw 230 ms · Total 900 ms · Spoken");
    expect(html).toContain("Cleanup 1,900 ms · Phrase · First Call");
    const widgetSet = page.shell.sets.find(function isWidget(set) {
      return set.key === "widget:summary";
    });
    expect(widgetSet?.value.name).toBe("Dictation");
  });

  it("on Midas Test: Open Dictation Test writes a test.dictation request and waits until the screen closes", async () => {
    const page = loadPage("midas-test", []);
    await page.app.whenReady();
    expect(page.mainHtml()).toContain("No Runs");
    await page.app.openTest();
    const requests = requestSets(page.shell);
    expect(requests.length).toBe(1);
    expect(requests[0].value.kind).toBe(TEST_KIND);
    expect(requests[0].value.status).toBe("pending");
    expect(page.mainHtml()).toContain("Testing…");
    // Still open: the page keeps waiting
    await page.app.poll();
    expect(page.app.state().waitingKey).toBe(requests[0].key);
    // The screen saved a run and closed (DictationTestCenter.save, then dismiss)
    page.shell.records.set("run:20261113T214500000Z-0001", runValue({ at: "2026-11-13T21:45:00.000Z", cleanupMs: 512, cleaned: "Buy eggs." }));
    page.shell.records.set(requests[0].key, { ...requests[0].value, status: "done", runs: 1 });
    await page.app.poll();
    expect(page.app.state().waitingKey).toBeNull();
    expect(page.shell.deletes).toContain(requests[0].key);
    expect(page.mainHtml()).toContain("Buy eggs.");
    expect(page.mainHtml()).toContain('data-action="open-test">Open Dictation Test</button>');
  });

  it("on the everyday Midas app and older builds: no button, no request", async () => {
    for (const build of ["midas", "older"] as ShellBuild[]) {
      const page = loadPage(build, fixtureRecords());
      await page.app.whenReady();
      expect(page.app.state().canOpenTest).toBe(false);
      expect(page.mainHtml()).not.toContain('data-action="open-test"');
      expect(page.mainHtml()).toContain("Midas Test Only");
      expect(requestSets(page.shell)).toEqual([]);
    }
  });

  it("clears requests left from an earlier open", async () => {
    const leftover = { key: "request:dold", value: { kind: TEST_KIND, status: "open" } };
    const page = loadPage("midas-test", [leftover]);
    await page.app.whenReady();
    expect(page.shell.records.has("request:dold")).toBe(false);
  });

  it("Show All opens every run, the back button returns", async () => {
    const page = loadPage("midas-test", fixtureRecords());
    await page.app.whenReady();
    expect(page.mainHtml()).not.toContain('data-action="show-all-runs"');
    const more = fixtureRecords();
    more.push({ key: "run:z", value: runValue({ at: "2026-11-13T21:50:00.000Z", cleanupMs: 222 }) });
    const fuller = loadPage("midas-test", more);
    await fuller.app.whenReady();
    expect(fuller.mainHtml()).toContain('data-action="show-all-runs"');
    fuller.tap("show-all-runs");
    expect(fuller.mainHtml()).toContain('<h2 class="h1">Runs</h2>');
    expect(fuller.mainHtml()).toContain("Cleanup 1,900 ms");
    fuller.tap("show-summary");
    expect(fuller.app.state().view).toBe("summary");
  });

  it("the ? menu has Add Widget on a build with the sheet, and How Dictation Works", async () => {
    const page = loadPage("midas-test", []);
    await page.app.whenReady();
    page.tap("toggle-help");
    expect(page.mainHtml()).toContain('data-action="add-home-screen">Add Widget</button>');
    expect(page.mainHtml()).toContain('data-action="show-how">How Dictation Works</button>');
    const older = loadPage("older", []);
    await older.app.whenReady();
    older.tap("toggle-help");
    expect(older.mainHtml()).not.toContain("Add Widget");
  });
});
