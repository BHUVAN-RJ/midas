// Build 40: our UI while Apple listens (TEST, staging only; founder 2026-11-22,
// docs/briefs/dictation-keyboard-test.md, "Build 40"; branch agent/dictation-test, never merged).
// The Dictation Sidekick gains keyboardMic "apple" (Apple's own dictation, watched and cleaned up by
// the Midas keyboard), appleCleanup in settings:main (on by default), and on keyboard runs mic
// "apple" with `cleanup` (applied or why not) and `dictationEnd`, exactly as the shell writes them
// (shell/DictationKeyboardShared/DictationKeyboardApple.swift, shell/Midas/DictationSidekick.swift).
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
const appleSource = readFileSync(new URL("../../shell/DictationKeyboardShared/DictationKeyboardApple.swift", import.meta.url), "utf8");
const micSource = readFileSync(new URL("../../shell/DictationKeyboardShared/DictationKeyboardMic.swift", import.meta.url), "utf8");
const gateSource = readFileSync(new URL("../../shell/Midas/DictationGate.swift", import.meta.url), "utf8");
const sidekickSource = readFileSync(new URL("../../shell/Midas/DictationSidekick.swift", import.meta.url), "utf8");
const sessionSource = readFileSync(new URL("../../shell/Midas/DictationKeyboardSession.swift", import.meta.url), "utf8");
const keyboardModelSource = readFileSync(new URL("../../shell/MidasKeyboard/MidasKeyboardModel.swift", import.meta.url), "utf8");
const controllerSource = readFileSync(new URL("../../shell/MidasKeyboard/KeyboardViewController.swift", import.meta.url), "utf8");
const projectSource = readFileSync(new URL("../../shell/project.yml", import.meta.url), "utf8");

const loaded = loadToolsScript(toolsText);
if (!("tools" in loaded)) {
  throw new Error(loaded.problem);
}
const tools = loaded.tools;
const NOW = "2026-11-22T20:00:00.000Z";

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

// The raw values of a Swift enum's cases, in order (a case with a raw value is stored as it)
function swiftCases(source: string, enumName: string): string[] {
  const start = source.indexOf("enum " + enumName);
  const end = source.indexOf("\n}\n", start);
  const block = source.slice(start, end);
  const cases: string[] = [];
  for (const match of block.matchAll(/\n    case (\w+)(?: = "([a-z-]+)")?\n/g)) {
    cases.push(match[2] ?? match[1]);
  }
  return cases;
}

// An Apple dictation run as DictationRunRecord.value writes it (DictationTestRuns.keyboard(appleRun:))
function appleRun(at: string, fields: Value = {}): Value {
  return {
    at, source: "keyboard", raw: "Um tell mom I'm on my way.", cleaned: "Tell mom I'm on my way.", cleanupMs: 0, firstCall: false,
    modelStatus: "Available", device: "iPhone17,1", ios: "27.1", build: "40", totalMs: 1562, path: "rule", matched: ["um"], gateMs: 0.3,
    thermal: "nominal", mic: "apple", cleanup: "applied", dictationEnd: "quiet", ...fields,
  };
}

describe("dictation build 40: keyboardMic apple", () => {
  it("is a value of the record, the page, the tools and the shell, after keyboard-only", () => {
    expect(Logic.KEYBOARD_MIC_MODES).toEqual(["keyboard", "app", "keyboard-only", "apple"]);
    expect(Logic.KEYBOARD_MIC_LABELS.apple).toBe("Apple Dictation");
    expect(manifest.types["settings:"].schema.properties.keyboardMic.enum).toEqual(Logic.KEYBOARD_MIC_MODES);
    expect(swiftCases(micSource, "DictationKeyboardMicMode")).toEqual(Logic.KEYBOARD_MIC_MODES);
    expect(schemaProblem("settings:main", { ...Logic.defaultSettings(), keyboardMic: "apple" })).toBeNull();
    expect(Logic.resolvedSettings({ ...Logic.defaultSettings(), keyboardMic: "apple" })).toEqual({
      settings: { ...Logic.defaultSettings(), keyboardMic: "apple" }, saved: true,
    });
    // The default stays keyboard
    expect(Logic.defaultSettings().keyboardMic).toBe("keyboard");
  });

  it("the shell routes apple to Apple's dictation with the APPLE MIC label and the hint", () => {
    expect(micSource).toMatch(/case \.apple:\n\s+return \.apple/);
    expect(appleSource).toContain('static let label = "APPLE MIC"');
    expect(appleSource).toContain('static let hint = "Tap 🎙 below"');
    expect(appleSource).toContain("static let quietEnd: TimeInterval = 1.5");
    expect(swiftCases(micSource, "DictationRunMic")).toEqual(["keyboard", "app", "apple"]);
  });

  it("save_settings writes apple alone and settings names it", () => {
    const outcome = call("save_settings", { keyboardMic: "apple" }, []);
    expect(outcome.refused).toBeUndefined();
    expect(outcome.ops?.[0].value).toEqual({ ...Logic.defaultSettings(), keyboardMic: "apple" });
    const shown = call("settings", {}, [{ key: "settings:main", value: outcome.ops?.[0].value as Value }]);
    expect(shown.result.keyboardMic).toBe("apple");
    expect(shown.result.text).toContain("Keyboard mic: Apple Dictation.");
  });

  it("the save tool and the agent block tell jess about apple", () => {
    const saveTool = manifest.agent.tools.find((tool: Value) => tool.name === "dictation.save_settings");
    expect(saveTool.inputSchema.properties.keyboardMic.description).toContain("apple (Apple's own dictation");
    expect(manifest.agent.examples).toContain("Use Apple's dictation in the Midas keyboard");
    expect(manifest.agent.description).toContain("Apple's own dictation");
  });
});

describe("dictation build 40: appleCleanup", () => {
  it("is on by default, true or false in the record, and a record without it reads as on", () => {
    expect(Logic.defaultSettings().appleCleanup).toBe(true);
    expect(manifest.types["settings:"].schema.properties.appleCleanup).toEqual({ type: "boolean" });
    expect(schemaProblem("settings:main", { ...Logic.defaultSettings(), appleCleanup: false })).toBeNull();
    expect(schemaProblem("settings:main", { ...Logic.defaultSettings(), appleCleanup: "yes" })).not.toBeNull();
    const withoutField = Logic.defaultSettings();
    delete withoutField.appleCleanup;
    const resolved = Logic.resolvedSettings(withoutField);
    expect(resolved.saved).toBe(true);
    expect(resolved.settings.appleCleanup).toBe(true);
    expect(Logic.resolvedSettings({ ...Logic.defaultSettings(), appleCleanup: false }).settings.appleCleanup).toBe(false);
    expect(Logic.settingsProblem({ ...Logic.defaultSettings(), appleCleanup: "yes" })).toBe("appleCleanup");
  });

  it("the shell reads and writes the same field, on by default, a non-boolean not fitting", () => {
    expect(appleSource).toContain('static let cleanupField = "appleCleanup"');
    expect(gateSource).toContain("var appleCleanup = true");
    expect(gateSource).toContain("DictationAppleConstants.cleanupField: .bool(appleCleanup)");
    expect(gateSource).toMatch(/guard case \.bool\(let storedCleanup\) = cleanupValue else \{\n\s+return nil/);
  });

  it("save_settings turns it off alone, keeps it when another field changes, and refuses a non-boolean", () => {
    const off = call("save_settings", { appleCleanup: false }, []);
    expect(off.refused).toBeUndefined();
    expect(off.ops?.[0].value).toEqual({ ...Logic.defaultSettings(), appleCleanup: false });
    expect(off.result.changed).toEqual(["apple cleanup"]);
    const savedOff: Records = [{ key: "settings:main", value: off.ops?.[0].value as Value }];
    const other = call("save_settings", { fillers: ["um"], appleCleanup: null }, savedOff);
    expect(other.ops?.[0].value.appleCleanup).toBe(false);
    const bad = call("save_settings", { appleCleanup: "yes" }, []);
    expect(bad.refused).toBe("bad appleCleanup");
    expect(bad.ops).toBeUndefined();
    expect(bad.result.text).toBe("Can’t save apple cleanup");
    expect(call("settings", {}, savedOff).result.text).toContain("Apple cleanup: Off.");
    expect(call("settings", {}, []).result.text).toContain("Apple cleanup: On.");
    expect(call("settings", {}, savedOff).result.appleCleanup).toBe(false);
  });

  it("the save tool lists appleCleanup as required and nullable", () => {
    const saveTool = manifest.agent.tools.find((tool: Value) => tool.name === "dictation.save_settings");
    expect(saveTool.inputSchema.required).toContain("appleCleanup");
    expect(saveTool.inputSchema.properties.appleCleanup.type).toEqual(["boolean", "null"]);
    expect(manifest.agent.examples).toContain("Turn off Apple dictation cleanup");
  });
});

describe("dictation build 40: Apple dictation runs", () => {
  it("cleanup and dictationEnd are the shell's values, in its order", () => {
    expect(swiftCases(appleSource, "DictationAppleCleanupResult")).toEqual(["applied", "unchanged", "off", "text-changed", "empty", "context-lost"]);
    expect(manifest.types["run:"].schema.properties.cleanup.enum).toEqual(swiftCases(appleSource, "DictationAppleCleanupResult"));
    expect(Logic.APPLE_CLEANUP_RESULTS).toEqual(swiftCases(appleSource, "DictationAppleCleanupResult"));
    expect(swiftCases(appleSource, "DictationAppleEnd")).toEqual(["input-mode", "quiet", "keyboard-shown", "midas-key", "keyboard-hidden"]);
    expect(manifest.types["run:"].schema.properties.dictationEnd.enum).toEqual(swiftCases(appleSource, "DictationAppleEnd"));
    expect(Logic.DICTATION_ENDS).toEqual(swiftCases(appleSource, "DictationAppleEnd"));
    for (const result of Logic.APPLE_CLEANUP_RESULTS) {
      expect(typeof Logic.CLEANUP_LABELS[result]).toBe("string");
    }
  });

  it("the run record takes an Apple run as the shell writes it and refuses unknown values", () => {
    expect(schemaProblem("run:20261122T200000000Z-0001", appleRun("2026-11-22T20:00:00.000Z"))).toBeNull();
    expect(schemaProblem("run:x", appleRun("2026-11-22T20:00:00.000Z", { cleanup: "text-changed", path: "skip", matched: [] }))).toBeNull();
    expect(schemaProblem("run:x", appleRun("2026-11-22T20:00:00.000Z", { cleanup: "maybe" }))).not.toBeNull();
    expect(schemaProblem("run:x", appleRun("2026-11-22T20:00:00.000Z", { dictationEnd: "later" }))).not.toBeNull();
    expect(schemaProblem("run:x", appleRun("2026-11-22T20:00:00.000Z", { mic: "siri" }))).not.toBeNull();
    expect(sidekickSource).toContain('fields["cleanup"] = .string(cleanup.rawValue)');
    expect(sidekickSource).toContain('fields["dictationEnd"] = .string(dictationEnd.rawValue)');
    expect(sidekickSource).toContain("run.mic = .apple");
    expect(sessionSource).toContain("mailbox.queued(DictationAppleRun.self, in: DictationAppleConstants.runsFolder)");
  });

  it("each Apple run shows its mic and cleanup; skips say why; the summary counts Apple Mic", () => {
    const records: Records = [
      { key: "run:a", value: appleRun("2026-11-22T20:00:00.000Z") },
      { key: "run:b", value: appleRun("2026-11-22T20:00:01.000Z", { cleanup: "text-changed" }) },
    ];
    const runs = Logic.runsOf(records);
    expect(runs[0].cleanup).toBe("text-changed");
    expect(runs[1].dictationEnd).toBe("quiet");
    expect(Logic.timingsLine(runs[1])).toContain("Keyboard · Apple Mic · Cleaned Up · Rule");
    expect(Logic.timingsLine(runs[0])).toContain("Apple Mic · Not Cleaned: Text Changed");
    expect(Logic.micSummaryOf(runs)).toEqual({ keyboard: { runs: 0 }, app: { runs: 0 }, apple: { runs: 2 } });
    const summary = call("summary", {}, records);
    expect(summary.result.text).toContain("Keyboard Mic 0, App Mic 0, Apple Mic 2.");
    const listed = call("runs", { limit: null }, records);
    const listedRuns = listed.result.runs as Value[];
    expect(listedRuns[0].cleanup).toBe("text-changed");
    expect(listedRuns[1].dictationEnd).toBe("quiet");
    expect(listedRuns[1].mic).toBe("apple");
  });

  it("an older run has no cleanup or dictation end", () => {
    const older = appleRun("2026-11-22T20:00:00.000Z", { mic: "app" });
    delete older.cleanup;
    delete older.dictationEnd;
    const run = Logic.runsOf([{ key: "run:a", value: older }])[0];
    expect(run.cleanup).toBeNull();
    expect(run.dictationEnd).toBeNull();
    expect(Logic.timingsLine(run)).not.toContain("Clean");
  });

  it("summary:main takes the shell's mics with apple", () => {
    const summaryValue = { runs: 2, updatedAt: NOW, mics: { keyboard: { runs: 0 }, app: { runs: 0 }, apple: { runs: 2 } } };
    expect(schemaProblem("summary:main", summaryValue)).toBeNull();
    expect(schemaProblem("summary:main", { ...summaryValue, mics: { keyboard: { runs: 0 }, app: { runs: 0 }, apple: { runs: -1 } } })).not.toBeNull();
  });

  it("still passes the deploy gate (the copied block matches the page)", () => {
    const checked = checkBundleFiles(html, manifestText, "dictation", toolsText);
    expect(checked.problems).toEqual([]);
  });
});

describe("dictation build 40: the keyboard watches with public signals only", () => {
  it("reads the input mode, textWillChange, textDidChange, appearing and the text around the cursor", () => {
    expect(controllerSource).toContain("UITextInputMode.currentInputModeDidChangeNotification");
    expect(controllerSource).toContain("override func textWillChange(");
    expect(controllerSource).toContain("override func viewDidAppear(");
    expect(controllerSource).toContain("textDocumentProxy.documentContextAfterInput");
    expect(controllerSource).toContain("textDocumentProxy.documentIdentifier");
    expect(controllerSource).toContain("hasDictationKey");
    expect(keyboardModelSource).toContain("DictationAppleCleanup.plan(span: finished.span, contextNow: contextNow, settings: gateSettings)");
  });

  it("adds no private selector for dictation (the only one is build 33's open URL)", () => {
    const selectors = Array.from(controllerSource.matchAll(/NSSelectorFromString\("([^"]+)"\)/g), (match) => match[1]);
    expect(selectors).toEqual(["openURL:options:completionHandler:"]);
    for (const source of [appleSource, keyboardModelSource]) {
      expect(source).not.toContain("NSSelectorFromString");
      expect(source).not.toContain("perform(");
    }
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
  const sets: Array<{ key: string; value: Value }> = [];

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
      sets.push({ key, value });
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

  function type(id: string, text: string) {
    const element = elementById(id) as Value;
    element.value = text;
  }

  return { app, sets, mainHtml, tap, type };
}

function settingsSets(sets: Array<{ key: string; value: Value }>) {
  const found: Value[] = [];
  for (const set of sets) {
    if (set.key === "settings:main") {
      found.push(set.value);
    }
  }
  return found;
}

describe("dictation build 40: the page", () => {
  it("Settings offers Apple Dictation and shows Apple Cleanup On after Keyboard Mic, before Fillers", async () => {
    const page = loadPage([]);
    await page.app.whenReady();
    page.tap("show-settings");
    const shown = page.mainHtml();
    expect(shown).toContain('<option value="apple">Apple Dictation</option></select>');
    expect(shown).toContain('<div class="lab">Apple Cleanup</div><select class="field wide" id="set-apple-cleanup" aria-label="Apple Cleanup">'
      + '<option value="on" selected>On</option><option value="off">Off</option></select>');
    expect(shown.indexOf("Keyboard Mic")).toBeLessThan(shown.indexOf("Apple Cleanup"));
    expect(shown.indexOf("Apple Cleanup")).toBeLessThan(shown.indexOf("Fillers"));
    expect(settingsSets(page.sets)).toEqual([]);
  });

  it("shows apple and Off picked when saved", async () => {
    const page = loadPage([{ key: "settings:main", value: { ...Logic.defaultSettings(), keyboardMic: "apple", appleCleanup: false } }]);
    await page.app.whenReady();
    page.tap("show-settings");
    const shown = page.mainHtml();
    expect(shown).toContain('<option value="apple" selected>Apple Dictation</option>');
    expect(shown).toContain('<option value="on">On</option><option value="off" selected>Off</option>');
  });

  it("Save writes apple and Off with the rest of the settings", async () => {
    const page = loadPage([]);
    await page.app.whenReady();
    page.tap("show-settings");
    page.type("set-keyboard-mic", "apple");
    page.type("set-apple-cleanup", "off");
    await page.app.saveSettings();
    const saved = settingsSets(page.sets);
    expect(saved.length).toBe(1);
    expect(saved[0].keyboardMic).toBe("apple");
    expect(saved[0].appleCleanup).toBe(false);
    expect(saved[0].fillers).toEqual(Logic.defaultSettings().fillers);
    expect(page.app.state().settings.appleCleanup).toBe(false);
    expect(page.mainHtml()).toContain('<div class="message">Saved</div>');
  });

  it("Save refuses an Apple Cleanup that is not On or Off and writes nothing", async () => {
    const page = loadPage([]);
    await page.app.whenReady();
    page.tap("show-settings");
    page.type("set-apple-cleanup", "maybe");
    await page.app.saveSettings();
    expect(settingsSets(page.sets)).toEqual([]);
    expect(page.mainHtml()).toContain('<div class="message">Can’t Save Apple Cleanup</div>');
  });

  it("the summary counts Apple Mic runs", async () => {
    const page = loadPage([{ key: "run:a", value: appleRun("2026-11-22T20:00:00.000Z") }]);
    await page.app.whenReady();
    expect(page.mainHtml()).toContain('<div class="path" data-mic="apple"><b>Apple Mic</b><span>1 run</span></div>');
  });
});

describe("dictation build 40: the build", () => {
  it("is build 40", () => {
    expect(projectSource).toContain('CURRENT_PROJECT_VERSION: "40"');
    expect(projectSource).not.toContain('CURRENT_PROJECT_VERSION: "38"');
  });
});
