// Build 35: make the mic test unmistakable (TEST, staging only; founder 2026-11-19,
// docs/briefs/dictation-keyboard-test.md, "Build 35"; branch agent/dictation-test, never merged).
// The Dictation Sidekick gains keyboardMic "keyboard-only", `mic` on keyboard runs with a count per
// microphone on the page and in the summary, and the keyboard log (`log:keyboard`, dictation.log)
// shown newest first on the page and read by dictation.keyboard_log, exactly as the shell writes
// them (shell/DictationKeyboardShared/DictationKeyboardLog.swift, shell/Midas/DictationSidekick.swift).
process.env.TZ = "America/Los_Angeles";

import { readFileSync } from "node:fs";
import vm from "node:vm";
import { describe, expect, it } from "vitest";
import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import { checkBundleFiles } from "../scripts/bundle-tools.mjs";
import { loadToolsScript } from "../scripts/sidekick-tools.mjs";

const folder = new URL("../../sidekicks/dictation/", import.meta.url);
const html = readFileSync(new URL("index.html", folder), "utf8");
const manifestText = readFileSync(new URL("manifest.json", folder), "utf8");
const toolsText = readFileSync(new URL("tools.js", folder), "utf8");
const manifest = JSON.parse(manifestText);
const logSource = readFileSync(new URL("../../shell/DictationKeyboardShared/DictationKeyboardLog.swift", import.meta.url), "utf8");
const micSource = readFileSync(new URL("../../shell/DictationKeyboardShared/DictationKeyboardMic.swift", import.meta.url), "utf8");
const sidekickSource = readFileSync(new URL("../../shell/Midas/DictationSidekick.swift", import.meta.url), "utf8");
const projectSource = readFileSync(new URL("../../shell/project.yml", import.meta.url), "utf8");

const loaded = loadToolsScript(toolsText);
if (!("tools" in loaded)) {
  throw new Error(loaded.problem);
}
const tools = loaded.tools;
const NOW = "2026-11-19T23:00:00.000Z";

type Value = Record<string, unknown>;
type Records = Array<{ key: string; value: Value }>;
type Outcome = { ops?: Array<{ op: string; key: string; value: Value }>; refused?: string; result: { text: string; [field: string]: unknown } };

function schemaProblem(key: string, value: Value) {
  const stamped = MidasRecordSchema.stampType(manifest.types, key, value);
  return MidasRecordSchema.checkRecord(manifest.types, key, stamped);
}

function call(verb: string, input: Value, records: Records): Outcome {
  const outcome = tools.handlers[verb](input, records, NOW);
  return JSON.parse(JSON.stringify(outcome));
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function logicFromPage(): any {
  const start = html.indexOf("var DictationLogic = (function createDictationLogic() {");
  const end = html.indexOf("\n})();\n", start) + "\n})();\n".length;
  return vm.runInNewContext(html.slice(start, end) + "\n;DictationLogic;", { Intl, Date, Math, JSON, Number, Object, String, Array });
}

const Logic = logicFromPage();

// A keyboard run as DictationRunRecord.value writes it, with build 35's mic when given
function keyboardRun(at: string, mic: string | null, raw = "send the deck"): Value {
  const run: Value = {
    at, source: "keyboard", raw, cleaned: raw.charAt(0).toUpperCase() + raw.slice(1) + ".", cleanupMs: 0, firstCall: false,
    modelStatus: "Available", device: "iPhone17,1", ios: "27.1", build: "35", releaseToRawMs: 1040, totalMs: 1048, path: "skip", matched: [],
    gateMs: 0.4, thermal: "nominal",
  };
  if (mic !== null) {
    run.mic = mic;
  }
  return run;
}

// The log record as DictationKeyboardLog.recordValue writes it, oldest line first
function logRecord(count: number): Value {
  const entries: Value[] = [];
  for (let index = 0; index < count; index += 1) {
    const seconds = String(index % 60).padStart(2, "0");
    entries.push({ at: "2026-11-19T23:10:" + seconds + ".000Z", event: index === 0 ? "appeared" : "mic step", detail: "line " + index });
  }
  return { updatedAt: "2026-11-19T23:11:00.000Z", entries };
}

describe("dictation build 35: keyboard-only", () => {
  it("is a keyboardMic value of the record, the page, the tools and the shell", () => {
    expect(Logic.KEYBOARD_MIC_MODES).toContain("keyboard-only");
    expect(Logic.KEYBOARD_MIC_LABELS["keyboard-only"]).toBe("Keyboard Only");
    expect(schemaProblem("settings:main", { ...Logic.defaultSettings(), keyboardMic: "keyboard-only" })).toBeNull();
    expect(Logic.resolvedSettings({ ...Logic.defaultSettings(), keyboardMic: "keyboard-only" })).toEqual({
      settings: { ...Logic.defaultSettings(), keyboardMic: "keyboard-only" }, saved: true,
    });
    expect(micSource).toContain('case keyboardOnly = "keyboard-only"');
    // The default stays keyboard
    expect(Logic.defaultSettings().keyboardMic).toBe("keyboard");
  });

  it("save_settings writes keyboard-only alone and settings names it", () => {
    const outcome = call("save_settings", { keyboardMic: "keyboard-only" }, []);
    expect(outcome.refused).toBeUndefined();
    expect(outcome.ops?.[0].key).toBe("settings:main");
    expect(outcome.ops?.[0].value).toEqual({ ...Logic.defaultSettings(), keyboardMic: "keyboard-only" });
    const shown = call("settings", {}, [{ key: "settings:main", value: outcome.ops?.[0].value as Value }]);
    expect(shown.result.keyboardMic).toBe("keyboard-only");
    expect(shown.result.text).toContain("Keyboard mic: Keyboard Only.");
  });

  it("the save tool tells jess about keyboard-only", () => {
    const saveTool = manifest.agent.tools.find((tool: Value) => tool.name === "dictation.save_settings");
    expect(saveTool.inputSchema.properties.keyboardMic.description).toContain("keyboard-only");
    expect(manifest.agent.examples).toContain("Use only the keyboard mic for dictation");
  });
});

describe("dictation build 35: mic on keyboard runs", () => {
  it("the run record takes mic keyboard or app and refuses anything else", () => {
    expect(schemaProblem("run:20261119T231000000Z-0001", keyboardRun("2026-11-19T23:10:00.000Z", "keyboard"))).toBeNull();
    expect(schemaProblem("run:20261119T231000000Z-0002", keyboardRun("2026-11-19T23:10:01.000Z", "app"))).toBeNull();
    expect(schemaProblem("run:20261119T231000000Z-0003", keyboardRun("2026-11-19T23:10:02.000Z", null))).toBeNull();
    expect(schemaProblem("run:x", keyboardRun("2026-11-19T23:10:03.000Z", "phone"))).not.toBeNull();
    expect(Logic.RUN_MICS).toEqual(["keyboard", "app"]);
    const micBlock = micSource.slice(micSource.indexOf("enum DictationRunMic"));
    expect(micBlock).toMatch(/^enum DictationRunMic: String[^{]*\{\n    case keyboard\n    case app\n\}/);
    expect(sidekickSource).toContain('fields["mic"] = .string(mic.rawValue)');
  });

  it("each run shows its mic; the summary counts runs per mic over the runs that logged one", () => {
    const records: Records = [
      { key: "run:a", value: keyboardRun("2026-11-19T23:10:00.000Z", "keyboard") },
      { key: "run:b", value: keyboardRun("2026-11-19T23:10:01.000Z", "keyboard") },
      { key: "run:c", value: keyboardRun("2026-11-19T23:10:02.000Z", "app") },
      { key: "run:d", value: keyboardRun("2026-11-19T23:10:03.000Z", null) },
    ];
    const runs = Logic.runsOf(records);
    expect(runs.map((run: Value) => run.mic)).toEqual([null, "app", "keyboard", "keyboard"]);
    expect(Logic.timingsLine(runs[1])).toContain("Keyboard · App Mic · Skip");
    expect(Logic.timingsLine(runs[0])).not.toContain("Mic");
    expect(Logic.micSummaryOf(runs)).toEqual({ keyboard: { runs: 2 }, app: { runs: 1 } });
    expect(Logic.micSummaryOf(Logic.runsOf([records[3]]))).toBeNull();

    const summary = call("summary", {}, records);
    expect(summary.result.mics).toEqual({ keyboard: { runs: 2 }, app: { runs: 1 } });
    expect(summary.result.text).toContain("Keyboard Mic 2, App Mic 1.");
    const listed = call("runs", { limit: null }, records);
    const listedRuns = listed.result.runs as Value[];
    expect(listedRuns[1].mic).toBe("app");
    expect(listedRuns[0].mic).toBeUndefined();
  });

  it("summary:main takes the shell's mics", () => {
    const summaryValue = { runs: 3, updatedAt: "2026-11-19T23:11:00.000Z", mics: { keyboard: { runs: 2 }, app: { runs: 1 } } };
    expect(schemaProblem("summary:main", summaryValue)).toBeNull();
    expect(schemaProblem("summary:main", { ...summaryValue, mics: { keyboard: { runs: -1 }, app: { runs: 1 } } })).not.toBeNull();
    expect(sidekickSource).toContain('fields["mics"] = mics');
  });
});

describe("dictation build 35: the keyboard log record", () => {
  it("takes the shell's record of up to 50 lines and refuses more or longer", () => {
    expect(manifest.types["log:"].$type).toBe("dictation.log");
    expect(schemaProblem("log:keyboard", logRecord(50))).toBeNull();
    expect(schemaProblem("log:keyboard", logRecord(51))).not.toBeNull();
    const longDetail = logRecord(1);
    (longDetail.entries as Value[])[0].detail = "d".repeat(301);
    expect(schemaProblem("log:keyboard", longDetail)).not.toBeNull();
    const longEvent = logRecord(1);
    (longEvent.entries as Value[])[0].event = "e".repeat(41);
    expect(schemaProblem("log:keyboard", longEvent)).not.toBeNull();
  });

  it("uses the shell's key and limits", () => {
    expect(logSource).toContain('static let recordKey = "log:keyboard"');
    expect(logSource).toContain("static let maxEntries = 50");
    expect(logSource).toContain("static let maxEventCharacters = 40");
    expect(logSource).toContain("static let maxDetailCharacters = 300");
    expect(Logic.KEYBOARD_LOG_KEY).toBe("log:keyboard");
    const entries = manifest.types["log:"].schema.properties.entries;
    expect(entries.maxItems).toBe(50);
    expect(entries.items.properties.event.maxLength).toBe(40);
    expect(entries.items.properties.detail.maxLength).toBe(300);
  });

  it("reads newest first; null without a log", () => {
    const lines = Logic.keyboardLogOf([{ key: "log:keyboard", value: logRecord(3) }]);
    expect(lines.map((line: Value) => line.detail)).toEqual(["line 2", "line 1", "line 0"]);
    expect(lines[2].event).toBe("appeared");
    expect(Logic.keyboardLogOf([])).toBeNull();
    expect(Logic.keyboardLogOf([{ key: "log:keyboard", value: { entries: "no" } }])).toBeNull();
  });
});

describe("dictation build 35: the keyboard_log tool", () => {
  it("is in the agent block with a nullable limit and opens the page's Keyboard Log", () => {
    const tool = manifest.agent.tools.find((entry: Value) => entry.name === "dictation.keyboard_log");
    expect(tool).toBeDefined();
    expect(tool.inputSchema.required).toEqual(["limit"]);
    expect(tool.inputSchema.properties.limit.type).toEqual(["integer", "null"]);
    expect(tool._meta["midas/page-actions"]).toEqual(["show-keyboard-log"]);
    expect(html).toContain('data-action="show-keyboard-log"');
    expect(manifest.agent.examples).toContain("What did the Midas keyboard do?");
  });

  it("returns the lines newest first, up to the limit, and says when there is none", () => {
    const records: Records = [{ key: "log:keyboard", value: logRecord(12) }];
    const all = call("keyboard_log", { limit: null }, records);
    const entries = all.result.entries as Value[];
    expect(entries.length).toBe(10);
    expect(entries[0].detail).toBe("line 11");
    expect(all.result.text.split("\n")[0]).toBe("2026-11-19T23:10:11.000Z mic step: line 11");
    const two = call("keyboard_log", { limit: 2 }, records);
    expect((two.result.entries as Value[]).length).toBe(2);
    expect(two.ops).toEqual([]);
    const none = call("keyboard_log", { limit: null }, []);
    expect(none.result.text).toBe("No keyboard log yet");
    expect(none.result.entries).toEqual([]);
  });

  it("still passes the deploy gate (the copied block matches the page)", () => {
    const checked = checkBundleFiles(html, manifestText, "dictation", toolsText);
    expect(checked.problems).toEqual([]);
  });
});

/* ---------- The page ---------- */

function pageScript(pageHtml: string) {
  const start = pageHtml.indexOf("<script>") + "<script>".length;
  const end = pageHtml.indexOf("</script>", start);
  return pageHtml.slice(start, end);
}

type StoreRequest = { op: string; key?: string; value?: Value; prefix?: string };

function loadPage(initial: Records) {
  const records = new Map<string, Value>();
  for (const record of initial) {
    records.set(record.key, record.value);
  }

  function answer(request: StoreRequest): Value {
    const key = String(request.key ?? "");
    if (request.op === "shell") {
      return { ok: true, requests: ["home-screen.widget", "test.dictation"] };
    }
    if (request.op === "set") {
      const value = JSON.parse(JSON.stringify(request.value)) as Value;
      const problem = schemaProblem(key, value);
      if (problem !== null) {
        return { ok: false, error: String(problem) };
      }
      records.set(key, value);
      return { ok: true };
    }
    if (request.op === "get") {
      return { ok: true, value: records.has(key) ? records.get(key) : null };
    }
    if (request.op === "delete") {
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
    return { ok: false, error: "unknown op" };
  }

  async function fetchFromPage(url: string, options: { body: string }) {
    const reply = answer(JSON.parse(options.body) as StoreRequest);
    return { json: async () => reply };
  }

  const elements = new Map<string, Value>();
  const handlers = new Map<string, (event: unknown) => void>();

  function elementById(id: string) {
    if (!elements.has(id)) {
      elements.set(id, { innerHTML: "" });
    }
    return elements.get(id);
  }

  function addListener(name: string, handler: (event: unknown) => void) {
    handlers.set(name, handler);
  }

  function ignore() {
    return 0;
  }

  const sandbox: Value = {
    window: { location: { origin: "sidekick://dictation" }, scrollTo: ignore, requestAnimationFrame: ignore, devicePixelRatio: 3 },
    document: { hidden: false, getElementById: elementById, addEventListener: addListener },
    fetch: fetchFromPage,
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
    const clickHandler = handlers.get("click") as (event: unknown) => void;
    clickHandler({ target: { closest: () => target } });
  }

  return { app, mainHtml, tap };
}

describe("dictation build 35: the page", () => {
  it("the ? menu has Keyboard Log, which shows the log newest first", async () => {
    const page = loadPage([{ key: "log:keyboard", value: logRecord(3) }]);
    await page.app.whenReady();
    page.tap("toggle-help");
    expect(page.mainHtml()).toContain('<button role="menuitem" data-action="show-keyboard-log">Keyboard Log</button>');
    page.tap("show-keyboard-log");
    const shown = page.mainHtml();
    expect(shown).toContain('<h2 class="h1">Keyboard Log</h2>');
    expect(shown.indexOf("line 2")).toBeGreaterThan(-1);
    expect(shown.indexOf("line 2")).toBeLessThan(shown.indexOf("line 1"));
    expect(shown.indexOf("line 1")).toBeLessThan(shown.indexOf("line 0"));
    expect(shown).toContain('data-log-event="appeared"');
  });

  it("Keyboard Log says when there is none", async () => {
    const page = loadPage([]);
    await page.app.whenReady();
    page.tap("show-keyboard-log");
    expect(page.mainHtml()).toContain('<div class="empty">No Keyboard Log</div>');
  });

  it("the summary shows keyboard runs per mic, and nothing before a run logged one", async () => {
    const withMics = loadPage([
      { key: "run:a", value: keyboardRun("2026-11-19T23:10:00.000Z", "keyboard") },
      { key: "run:b", value: keyboardRun("2026-11-19T23:10:01.000Z", "app") },
      { key: "run:c", value: keyboardRun("2026-11-19T23:10:02.000Z", "keyboard") },
    ]);
    await withMics.app.whenReady();
    const shown = withMics.mainHtml();
    expect(shown).toContain('<div class="lab">Keyboard Mic</div>');
    expect(shown).toContain('<div class="path" data-mic="keyboard"><b>Keyboard Mic</b><span>2 runs</span></div>');
    expect(shown).toContain('<div class="path" data-mic="app"><b>App Mic</b><span>1 run</span></div>');
    const withoutMics = loadPage([{ key: "run:a", value: keyboardRun("2026-11-19T23:10:00.000Z", null) }]);
    await withoutMics.app.whenReady();
    expect(withoutMics.mainHtml()).not.toContain("data-mic=");
  });

  it("Settings shows Keyboard Only picked when saved", async () => {
    const page = loadPage([{ key: "settings:main", value: { ...Logic.defaultSettings(), keyboardMic: "keyboard-only" } }]);
    await page.app.whenReady();
    page.tap("show-settings");
    expect(page.mainHtml()).toContain('<option value="keyboard-only" selected>Keyboard Only</option>');
  });
});

describe("dictation build 35: the build", () => {
  it("is build 35", () => {
    expect(projectSource).toContain('CURRENT_PROJECT_VERSION: "35"');
    expect(projectSource).not.toContain('CURRENT_PROJECT_VERSION: "34"');
  });
});
