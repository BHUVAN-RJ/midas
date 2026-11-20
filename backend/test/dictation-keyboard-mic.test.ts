// Build 34: mic inside the keyboard (TEST, staging only; founder 2026-11-19,
// docs/briefs/dictation-keyboard-test.md, "Build 34"; branch agent/dictation-test, never merged).
// The Dictation Sidekick's settings:main gains `keyboardMic` ("keyboard", the default, or "app"),
// edited on the page's Settings and by dictation.save_settings; the manifest gains a
// `dictation.probe` type for each keyboard attempt at the microphone, exactly as the shell writes
// it (shell/DictationKeyboardShared/DictationKeyboardMic.swift, DictationProbeRecord.value).
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
const micSource = readFileSync(new URL("../../shell/DictationKeyboardShared/DictationKeyboardMic.swift", import.meta.url), "utf8");
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

// A failed probe exactly as DictationProbeRecord.value writes it
function failedProbe(fields: Value = {}): Value {
  return {
    at: "2026-11-19T22:41:07.512Z", result: "failed", step: "engine-start", errorDomain: "com.apple.coreaudio.avfaudio", errorCode: 561145187,
    errorMessage: "The operation couldn’t be completed. (com.apple.coreaudio.avfaudio error 561145187.)", fullAccess: true,
    microphone: "granted", speech: "authorized", build: "34", ios: "27.1", buffers: 0, peak: 0, ...fields,
  };
}

// A working probe: no step, no error
function worksProbe(): Value {
  return { at: "2026-11-19T22:42:00.000Z", result: "works", fullAccess: true, microphone: "granted", speech: "authorized", build: "34", ios: "27.1",
    buffers: 212, peak: 0.41 };
}

// The saved settings as the page wrote them before build 34 (no keyboardMic)
function settingsWithoutMode(): Value {
  const settings = Logic.defaultSettings();
  delete settings.keyboardMic;
  return settings;
}

describe("dictation keyboard mic: the probe record", () => {
  it("takes a failed and a working probe as the shell writes them", () => {
    expect(schemaProblem("probe:20261119T224107512Z-0001", failedProbe())).toBeNull();
    expect(schemaProblem("probe:20261119T224200000Z-0002", worksProbe())).toBeNull();
    expect(manifest.types["probe:"].$type).toBe("dictation.probe");
  });

  it("takes a negative iOS error code (AVFoundation's are)", () => {
    expect(schemaProblem("probe:x", failedProbe({ errorCode: -11800 }))).toBeNull();
  });

  it("refuses an unknown result or step, a peak over 1 and a probe without its build", () => {
    expect(schemaProblem("probe:x", failedProbe({ result: "maybe" }))).not.toBeNull();
    expect(schemaProblem("probe:x", failedProbe({ step: "speaker" }))).not.toBeNull();
    expect(schemaProblem("probe:x", failedProbe({ peak: 1.5 }))).not.toBeNull();
    expect(schemaProblem("probe:x", failedProbe({ buffers: -1 }))).not.toBeNull();
    const withoutBuild = failedProbe();
    delete withoutBuild.build;
    expect(schemaProblem("probe:x", withoutBuild)).not.toBeNull();
  });

  it("lists the shell's steps, in its order", () => {
    const steps: string[] = [];
    const stepBlock = micSource.slice(micSource.indexOf("enum DictationKeyboardProbeStep"), micSource.indexOf("var label: String"));
    for (const match of stepBlock.matchAll(/case (\w+)(?: = "([a-z-]+)")?\n/g)) {
      steps.push(match[2] ?? match[1]);
    }
    expect(steps).toEqual(["session-category", "activate", "engine-start", "audio", "recogniser"]);
    expect(manifest.types["probe:"].schema.properties.step.enum).toEqual(steps);
  });

  it("names every field the shell writes in the manifest", () => {
    const valueBlock = micSource.slice(micSource.indexOf("enum DictationProbeRecord"), micSource.indexOf("/// \"2026-11-19T23:15:02.123Z\""));
    const written = new Set<string>();
    for (const match of valueBlock.matchAll(/"([a-zA-Z]+)": \./g)) {
      written.add(match[1]);
    }
    for (const match of valueBlock.matchAll(/fields\["([a-zA-Z]+)"\]/g)) {
      written.add(match[1]);
    }
    expect(written.size).toBe(13);
    const properties = Object.keys(manifest.types["probe:"].schema.properties);
    for (const field of written) {
      expect(properties).toContain(field);
    }
  });
});

describe("dictation keyboard mic: the setting", () => {
  it("is keyboard by default, in the record schema as keyboard or app", () => {
    expect(Logic.defaultSettings().keyboardMic).toBe("keyboard");
    expect(manifest.types["settings:"].schema.properties.keyboardMic.enum).toEqual(["keyboard", "app"]);
    expect(schemaProblem("settings:main", { ...Logic.defaultSettings(), keyboardMic: "app" })).toBeNull();
    expect(schemaProblem("settings:main", { ...Logic.defaultSettings(), keyboardMic: "phone" })).not.toBeNull();
  });

  it("reads a record from before build 34 as saved, with keyboard", () => {
    const resolved = Logic.resolvedSettings(settingsWithoutMode());
    expect(resolved.saved).toBe(true);
    expect(resolved.settings.keyboardMic).toBe("keyboard");
  });

  it("keeps app, and falls back to the built-in settings for an unknown mode", () => {
    expect(Logic.resolvedSettings({ ...Logic.defaultSettings(), keyboardMic: "app" }).settings.keyboardMic).toBe("app");
    expect(Logic.settingsProblem({ ...Logic.defaultSettings(), keyboardMic: "phone" })).toBe("keyboardMic");
    expect(Logic.resolvedSettings({ ...Logic.defaultSettings(), keyboardMic: "phone" })).toEqual({ settings: Logic.defaultSettings(), saved: false });
  });

  it("the shell reads the same field, values and default", () => {
    expect(micSource).toContain('static let settingsField = "keyboardMic"');
    expect(micSource).toContain("static let builtIn: DictationKeyboardMicMode = .keyboard");
    const modeBlock = micSource.slice(micSource.indexOf("enum DictationKeyboardMicMode"), micSource.indexOf("static let builtIn"));
    const modes: string[] = [];
    for (const match of modeBlock.matchAll(/\n    case (\w+)\n/g)) {
      modes.push(match[1]);
    }
    expect(modes).toEqual(Logic.KEYBOARD_MIC_MODES);
  });
});

describe("dictation keyboard mic: the tools", () => {
  const savedApp: Records = [{ key: "settings:main", value: { ...Logic.defaultSettings(), keyboardMic: "app" } }];

  it("settings says where the keyboard records", () => {
    const builtIn = call("settings", {}, []);
    expect(builtIn.result.keyboardMic).toBe("keyboard");
    expect(builtIn.result.text).toContain("Keyboard mic: Keyboard.");
    const app = call("settings", {}, savedApp);
    expect(app.result.keyboardMic).toBe("app");
    expect(app.result.text).toContain("Keyboard mic: App Switch.");
  });

  it("save_settings changes keyboardMic alone, keeping the rest", () => {
    const outcome = call("save_settings", { keyboardMic: "app" }, []);
    expect(outcome.refused).toBeUndefined();
    expect(outcome.ops?.length).toBe(1);
    expect(outcome.ops?.[0].key).toBe("settings:main");
    expect(outcome.ops?.[0].value).toEqual({ ...Logic.defaultSettings(), keyboardMic: "app" });
    expect(outcome.result.changed).toEqual(["keyboard mic"]);
  });

  it("save_settings keeps keyboardMic when another field changes", () => {
    const outcome = call("save_settings", { fillers: ["um"], keyboardMic: null }, savedApp);
    expect(outcome.ops?.[0].value.keyboardMic).toBe("app");
    expect(outcome.ops?.[0].value.fillers).toEqual(["um"]);
  });

  it("save_settings refuses an unknown mode and writes nothing", () => {
    const outcome = call("save_settings", { keyboardMic: "phone" }, []);
    expect(outcome.refused).toBe("bad keyboardMic");
    expect(outcome.ops).toBeUndefined();
    expect(outcome.result.text).toBe("Can’t save keyboard mic");
  });

  it("the save tool's input lists keyboardMic as required and nullable", () => {
    const saveTool = manifest.agent.tools.find((tool: Value) => tool.name === "dictation.save_settings");
    expect(saveTool.inputSchema.required).toContain("keyboardMic");
    expect(saveTool.inputSchema.properties.keyboardMic.type).toEqual(["string", "null"]);
    expect(manifest.agent.examples).toContain("Use the app switch for keyboard dictation");
  });

  it("still pass the deploy gate (the copied block matches the page)", () => {
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
  const sets: Array<{ key: string; value: Value }> = [];

  function answer(request: StoreRequest): Value {
    const key = String(request.key ?? "");
    if (request.op === "shell") {
      return { ok: true, requests: ["home-screen.widget", "test.dictation"] };
    }
    if (request.op === "set") {
      const value = JSON.parse(JSON.stringify(request.value)) as Value;
      // The store's write gate: the manifest's types
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

  // Typing (or picking) in a form field: the element the page reads by id
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

describe("dictation keyboard mic: the page", () => {
  it("Settings starts with Keyboard Mic, Keyboard picked when nothing is saved", async () => {
    const page = loadPage([]);
    await page.app.whenReady();
    page.tap("show-settings");
    const shown = page.mainHtml();
    expect(shown).toContain('<div class="lab">Keyboard Mic</div><select class="field wide" id="set-keyboard-mic" aria-label="Keyboard Mic">'
      + '<option value="keyboard" selected>Keyboard</option><option value="app">App Switch</option></select>');
    expect(shown.indexOf("Keyboard Mic")).toBeLessThan(shown.indexOf("Fillers"));
    expect(settingsSets(page.sets)).toEqual([]);
  });

  it("shows App Switch picked when saved", async () => {
    const page = loadPage([{ key: "settings:main", value: { ...Logic.defaultSettings(), keyboardMic: "app" } }]);
    await page.app.whenReady();
    page.tap("show-settings");
    expect(page.mainHtml()).toContain('<option value="keyboard">Keyboard</option><option value="app" selected>App Switch</option>');
  });

  it("Save writes the picked mode with the rest of the settings", async () => {
    const page = loadPage([]);
    await page.app.whenReady();
    page.tap("show-settings");
    page.type("set-keyboard-mic", "app");
    await page.app.saveSettings();
    const saved = settingsSets(page.sets);
    expect(saved.length).toBe(1);
    expect(saved[0].keyboardMic).toBe("app");
    expect(saved[0].fillers).toEqual(Logic.defaultSettings().fillers);
    expect(page.app.state().settings.keyboardMic).toBe("app");
    expect(page.mainHtml()).toContain('<div class="message">Saved</div>');
  });

  it("Save refuses a mode that is not keyboard or app and writes nothing", async () => {
    const page = loadPage([]);
    await page.app.whenReady();
    page.tap("show-settings");
    page.type("set-keyboard-mic", "phone");
    await page.app.saveSettings();
    expect(settingsSets(page.sets)).toEqual([]);
    expect(page.mainHtml()).toContain('<div class="message">Can’t Save Keyboard Mic</div>');
  });
});

describe("dictation keyboard mic: build 34", () => {
  it("is build 34, and the keyboard asks for the microphone and speech with the app's lines", () => {
    expect(projectSource).toContain('CURRENT_PROJECT_VERSION: "34"');
    const keyboardBlock = projectSource.slice(projectSource.indexOf("\n  MidasKeyboard:\n"), projectSource.indexOf("\n  MidasTests:\n"));
    expect(keyboardBlock).toContain('NSMicrophoneUsageDescription: "Midas listens when you speak a request or an edit."');
    expect(keyboardBlock).toContain('NSSpeechRecognitionUsageDescription: "Midas turns your voice into text on this iPhone."');
    for (const file of ["Midas/VoiceTranscriber.swift", "Midas/DictationGate.swift", "Midas/JSONValue.swift"]) {
      expect(keyboardBlock).toContain("- " + file);
    }
  });
});
