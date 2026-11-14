// The dictation cleanup gate on the Dictation Sidekick (TEST, staging only; founder 2026-11-13,
// docs/briefs/dictation-gate-test.md). The records the shell writes with the gate's fields
// (path, trigger, matched, gateMs; DictationRunRecord.value) and the summary's per-path numbers
// fit the manifest, bad ones are refused; settings:main is checked like the shell checks it
// (DictationGateSettings.from) and falls back to the built-in settings; the per-path math (runs,
// share, average total) is the same for the page, the tools and the shell; the two settings tools
// read and change settings:main as the page's Save does; and the page, run in Node against a fake
// shell, shows the per-path numbers and edits, checks and saves the settings.
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
const gateSource = readFileSync(new URL("../../shell/Midas/DictationGate.swift", import.meta.url), "utf8");
const sidekickSource = readFileSync(new URL("../../shell/Midas/DictationSidekick.swift", import.meta.url), "utf8");

const loaded = loadToolsScript(toolsText);
if (!("tools" in loaded)) {
  throw new Error(loaded.problem);
}
const tools = loaded.tools;

const NOW = "2026-11-13T22:00:00.000Z";
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

// A run as DictationRunRecord.value writes it after the gate
function gatedRun(fields: Value = {}): Value {
  return {
    at: "2026-11-13T21:30:45.123Z", source: "phrase", raw: "uh tell mom im on my way", cleaned: "Tell Mom I'm on my way.", cleanupMs: 1300,
    firstCall: false, modelStatus: "Available", device: "iPhone17,1", ios: "26.1", build: "29", path: "light", matched: ["uh"], gateMs: 0.04,
    ...fields,
  };
}

// Six gated runs and one from before the gate. Totals per path:
//   skip:    spoken 310 (totalMs), phrase 0 + 0.03       -> 2 runs, avg (310 + 0.03) / 2 = 155.015 -> 155
//   light:   spoken 1,800 (totalMs), phrase 1,300 + 0.04 -> 2 runs, avg 1,550.02 -> 1,550
//   rewrite: phrase 1,401 + 0.5, phrase 1,600 + 0.5      -> 2 runs, avg 1,501 -> 1,501
// Shares: 2 / 6 each = 33.33 -> 33. The old run (no path) counts for neither.
function pathFixture(): Records {
  return [
    { key: "run:1", value: gatedRun({ at: "2026-11-13T21:00:00.000Z", source: "spoken", path: "skip", matched: [], cleanupMs: 0, releaseToRawMs: 300, totalMs: 310, gateMs: 0.02 }) },
    { key: "run:2", value: gatedRun({ at: "2026-11-13T21:01:00.000Z", path: "skip", matched: [], cleanupMs: 0, gateMs: 0.03 }) },
    { key: "run:3", value: gatedRun({ at: "2026-11-13T21:02:00.000Z", source: "spoken", cleanupMs: 1500, releaseToRawMs: 250, totalMs: 1800 }) },
    { key: "run:4", value: gatedRun({ at: "2026-11-13T21:03:00.000Z" }) },
    { key: "run:5", value: gatedRun({ at: "2026-11-13T21:04:00.000Z", path: "rewrite", trigger: "email", matched: [], cleanupMs: 1401, gateMs: 0.5 }) },
    { key: "run:6", value: gatedRun({ at: "2026-11-13T21:05:00.000Z", path: "rewrite", trigger: "list", matched: [], cleanupMs: 1600, gateMs: 0.5 }) },
    { key: "run:0", value: { at: "2026-11-13T20:00:00.000Z", source: "phrase", raw: "x", cleaned: "X.", cleanupMs: 999, firstCall: true } },
  ];
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function logicFromPage(): any {
  const start = html.indexOf("var DictationLogic = (function createDictationLogic() {");
  const end = html.indexOf("\n})();\n", start) + "\n})();\n".length;
  return vm.runInNewContext(html.slice(start, end) + "\n;DictationLogic;", { Intl, Date, Math, JSON, Number, Object, String, Array });
}

const Logic = logicFromPage();

describe("dictation gate: the bundle and the shell agree", () => {
  it("still passes the deploy gate with the settings tools", () => {
    expect(checkBundleFiles(html, manifestText, "dictation", toolsText).problems).toEqual([]);
    const names: string[] = [];
    for (const tool of manifest.agent.tools) {
      names.push(tool.name);
    }
    expect(names).toEqual(["dictation.summary", "dictation.runs", "dictation.settings", "dictation.save_settings"]);
  });

  it("uses the shell's key, limits and paths", () => {
    expect(gateSource).toContain('static let settingsKey = "settings:main"');
    expect(gateSource).toContain("static let maxListItems = 50");
    expect(gateSource).toContain("static let maxPhraseCharacters = 40");
    expect(gateSource).toContain("static let maxTriggers = 20");
    expect(gateSource).toContain("static let maxTriggerCharacters = 30");
    expect(gateSource).toContain("static let maxInstructionCharacters = 4000");
    expect(sidekickSource).toContain("static let maxMatched = 40");
    expect(Logic.SETTINGS_KEY).toBe("settings:main");
    expect(Logic.SETTINGS_LIMITS).toEqual({ listItems: 50, phrase: 40, triggers: 20, trigger: 30, instruction: 4000 });
    expect(Logic.PATHS).toEqual(["skip", "light", "rewrite"]);
    const settingsSchema = manifest.types["settings:"].schema;
    expect(settingsSchema.properties.fillers.maxItems).toBe(50);
    expect(settingsSchema.properties.fillers.items.maxLength).toBe(40);
    expect(settingsSchema.properties.triggers.maxItems).toBe(20);
    expect(settingsSchema.properties.triggers.items.properties.word.maxLength).toBe(30);
    expect(settingsSchema.properties.lightInstruction.maxLength).toBe(4000);
    expect(manifest.types["run:"].schema.properties.matched.maxItems).toBe(40);
  });

  it("built-in trigger words and lists are the brief's start set", () => {
    const defaults = Logic.defaultSettings();
    const words: string[] = [];
    for (const trigger of defaults.triggers) {
      words.push(trigger.word);
    }
    expect(words).toEqual(["email", "formal", "casual", "list", "bullets"]);
    const allFillers = defaults.fillers.concat(defaults.positionFillers);
    for (const filler of ["um", "uh", "erm", "hmm", "like", "you know", "I mean", "sort of", "kind of", "basically", "so"]) {
      expect(allFillers).toContain(filler);
    }
    expect(defaults.positionFillers).toEqual(["like", "so"]);
    expect(defaults.corrections).toEqual(["no wait", "wait no", "scratch that", "I mean", "actually", "sorry", "no no", "make that", "I meant"]);
    expect(defaults.lightInstruction).toContain("Never change pronouns, names, numbers or meaning");
    expect(defaults.lightInstruction).toContain("never add words");
    expect(defaults.lightInstruction).toContain("numbered list");
    // Every built-in string is in the shell's source too (the Swift test compares them whole)
    for (const trigger of defaults.triggers) {
      expect(gateSource).toContain(trigger.instruction);
    }
  });
});

describe("dictation gate: records", () => {
  it("takes runs with each path, a trigger, matched words and a fractional gate time", () => {
    expect(schemaProblem("run:a", gatedRun())).toBeNull();
    expect(schemaProblem("run:b", gatedRun({ path: "skip", matched: [], cleanupMs: 0 }))).toBeNull();
    expect(schemaProblem("run:c", gatedRun({ path: "rewrite", trigger: "email", matched: ["um"] }))).toBeNull();
  });

  it("refuses an unknown path, a long trigger, a matched word that is not text and a negative gate time", () => {
    expect(schemaProblem("run:a", gatedRun({ path: "fast" }))).not.toBeNull();
    expect(schemaProblem("run:a", gatedRun({ trigger: "x".repeat(31) }))).not.toBeNull();
    expect(schemaProblem("run:a", gatedRun({ matched: [3] }))).not.toBeNull();
    expect(schemaProblem("run:a", gatedRun({ gateMs: -1 }))).not.toBeNull();
  });

  it("takes the summary with per-path numbers and refuses a share over 100", () => {
    const paths = {
      skip: { runs: 2, sharePercent: 33, averageTotalMs: 155 },
      light: { runs: 2, sharePercent: 33, averageTotalMs: 1550 },
      rewrite: { runs: 0, sharePercent: 0 },
    };
    expect(schemaProblem("summary:main", { runs: 7, updatedAt: NOW, paths })).toBeNull();
    const tooMuch = { ...paths, skip: { runs: 2, sharePercent: 101 } };
    expect(schemaProblem("summary:main", { runs: 7, updatedAt: NOW, paths: tooMuch })).not.toBeNull();
  });

  it("takes the built-in settings and refuses settings missing a list, with an empty word or an overlong instruction", () => {
    expect(schemaProblem("settings:main", Logic.defaultSettings())).toBeNull();
    const withoutFillers = Logic.defaultSettings();
    delete withoutFillers.fillers;
    expect(schemaProblem("settings:main", withoutFillers)).not.toBeNull();
    expect(schemaProblem("settings:main", { ...Logic.defaultSettings(), corrections: [""] })).not.toBeNull();
    expect(schemaProblem("settings:main", { ...Logic.defaultSettings(), lightInstruction: "x".repeat(4001) })).not.toBeNull();
    expect(schemaProblem("settings:main", { ...Logic.defaultSettings(), triggers: [{ word: "email" }] })).not.toBeNull();
  });
});

describe("dictation gate: settings are checked as the shell checks them", () => {
  it("built-in settings fit; stored ones are trimmed", () => {
    expect(Logic.settingsProblem(Logic.defaultSettings())).toBeNull();
    const stored = { ...Logic.defaultSettings(), fillers: ["  um ", "er"], triggers: [{ word: " memo ", instruction: " Write a memo. " }] };
    const settings = Logic.settingsFrom(stored);
    expect(settings.fillers).toEqual(["um", "er"]);
    expect(settings.triggers).toEqual([{ word: "memo", instruction: "Write a memo." }]);
  });

  it("names the first field that does not fit", () => {
    const base = Logic.defaultSettings();
    expect(Logic.settingsProblem(null)).toBe("settings");
    expect(Logic.settingsProblem({ ...base, fillers: "um" })).toBe("fillers");
    expect(Logic.settingsProblem({ ...base, positionFillers: ["..."] })).toBe("positionFillers");
    expect(Logic.settingsProblem({ ...base, corrections: ["x".repeat(41)] })).toBe("corrections");
    const tooMany: string[] = [];
    for (let index = 0; index < 51; index += 1) {
      tooMany.push("w" + index);
    }
    expect(Logic.settingsProblem({ ...base, fillers: tooMany })).toBe("fillers");
    expect(Logic.settingsProblem({ ...base, triggers: [{ word: "email", instruction: "  " }] })).toBe("triggers");
    expect(Logic.settingsProblem({ ...base, lightInstruction: "" })).toBe("lightInstruction");
  });

  it("empty lists are allowed (no fillers at all)", () => {
    expect(Logic.settingsProblem({ ...Logic.defaultSettings(), fillers: [], triggers: [] })).toBeNull();
  });

  it("missing or not fitting settings fall back to the built-in ones", () => {
    expect(Logic.resolvedSettings(null)).toEqual({ settings: Logic.defaultSettings(), saved: false });
    expect(Logic.resolvedSettings({ fillers: ["um"] })).toEqual({ settings: Logic.defaultSettings(), saved: false });
    const stored = { ...Logic.defaultSettings(), fillers: ["um"] };
    expect(Logic.resolvedSettings(stored)).toEqual({ settings: stored, saved: true });
  });

  it("splits a typed list at commas and new lines", () => {
    expect(Logic.phrasesFromText(" um, uh ,\nyou know,, \n")).toEqual(["um", "uh", "you know"]);
    expect(Logic.phrasesFromText("")).toEqual([]);
  });
});

describe("dictation gate: per-path numbers", () => {
  it("count, share and average total per path over the gated runs only", () => {
    const paths = Logic.pathSummaryOf(Logic.runsOf(pathFixture()));
    expect(paths).toEqual({
      skip: { runs: 2, sharePercent: 33, averageTotalMs: 155 },
      light: { runs: 2, sharePercent: 33, averageTotalMs: 1550 },
      rewrite: { runs: 2, sharePercent: 33, averageTotalMs: 1501 },
    });
  });

  it("a path with no runs has no average; no gated runs gives nothing", () => {
    const records = pathFixture().slice(0, 4);
    const paths = Logic.pathSummaryOf(Logic.runsOf(records));
    expect(paths.rewrite).toEqual({ runs: 0, sharePercent: 0, averageTotalMs: null });
    expect(paths.skip.sharePercent).toBe(50);
    expect(Logic.pathSummaryOf(Logic.runsOf([pathFixture()[6]]))).toBeNull();
  });

  it("the run line names the path and the trigger", () => {
    const runs = Logic.runsOf(pathFixture());
    const lines: string[] = [];
    for (const run of runs) {
      lines.push(Logic.timingsLine(run));
    }
    expect(lines[0]).toBe("Cleanup 1,600 ms · Phrase · Rewrite: list");
    expect(lines[3]).toBe("Cleanup 1,500 ms · Raw 250 ms · Total 1,800 ms · Spoken · Light");
    expect(lines[6]).toBe("Cleanup 999 ms · Phrase · First Call");
  });
});

describe("dictation gate: tools", () => {
  it("summary adds the per-path numbers when runs went through the gate", () => {
    const outcome = call("summary", {}, pathFixture());
    expect(outcome.ops).toEqual([]);
    expect(outcome.result.paths).toEqual({
      skip: { runs: 2, sharePercent: 33, averageTotalMs: 155 },
      light: { runs: 2, sharePercent: 33, averageTotalMs: 1550 },
      rewrite: { runs: 2, sharePercent: 33, averageTotalMs: 1501 },
    });
    expect(outcome.result.text).toContain("Skip 2 runs (33%), avg 155 ms; Light 2 runs (33%), avg 1,550 ms; Rewrite 2 runs (33%), avg 1,501 ms.");
  });

  it("runs carries the path, trigger, matched words and gate time", () => {
    const shown = call("runs", { limit: 1 }, pathFixture()).result.runs as Value[];
    expect(shown[0].path).toBe("rewrite");
    expect(shown[0].trigger).toBe("list");
    expect(shown[0].matched).toEqual([]);
    expect(shown[0].gateMs).toBe(0.5);
  });

  it("settings reads the built-in ones when none are saved, the saved ones otherwise", () => {
    const builtIn = call("settings", {}, []);
    expect(builtIn.ops).toEqual([]);
    expect(builtIn.result.saved).toBe(false);
    expect(builtIn.result.fillers).toEqual(Logic.defaultSettings().fillers);
    expect(builtIn.result.text).toContain("Trigger words: email, formal, casual, list, bullets.");
    const saved = { ...Logic.defaultSettings(), triggers: [{ word: "memo", instruction: "Write a memo." }] };
    const outcome = call("settings", {}, [{ key: "settings:main", value: saved }]);
    expect(outcome.result.saved).toBe(true);
    expect(outcome.result.triggers).toEqual([{ word: "memo", instruction: "Write a memo." }]);
    expect(outcome.result.text).toContain("Trigger words: memo.");
  });

  it("save_settings replaces only the fields given and writes the whole record", () => {
    const input = { fillers: ["um", "er"], positionFillers: null, corrections: null, triggers: null, lightInstruction: null };
    const outcome = call("save_settings", input, []);
    expect(outcome.refused).toBeUndefined();
    expect(outcome.ops?.length).toBe(1);
    const op = outcome.ops?.[0];
    expect(op?.op).toBe("set");
    expect(op?.key).toBe("settings:main");
    expect(op?.value).toEqual({ ...Logic.defaultSettings(), fillers: ["um", "er"] });
    expect(schemaProblem("settings:main", op?.value as Value)).toBeNull();
    expect(outcome.result.text).toBe("Saved fillers");
  });

  it("save_settings keeps what was saved before for the fields not given", () => {
    const saved = { ...Logic.defaultSettings(), corrections: ["oops"] };
    const input = { fillers: null, positionFillers: null, corrections: null, triggers: [{ word: "memo", instruction: "Write a memo." }], lightInstruction: null };
    const outcome = call("save_settings", input, [{ key: "settings:main", value: saved }]);
    expect(outcome.ops?.[0].value.corrections).toEqual(["oops"]);
    expect(outcome.ops?.[0].value.triggers).toEqual([{ word: "memo", instruction: "Write a memo." }]);
  });

  it("save_settings refuses settings that do not fit, and an empty change", () => {
    const bad = call("save_settings", { fillers: [""], positionFillers: null, corrections: null, triggers: null, lightInstruction: null }, []);
    expect(bad.refused).toBe("bad fillers");
    expect(bad.ops).toBeUndefined();
    const nothing = call("save_settings", { fillers: null, positionFillers: null, corrections: null, triggers: null, lightInstruction: null }, []);
    expect(nothing.refused).toBe("nothing to change");
  });
});

/* ---------- The page against a fake shell ---------- */

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

  function tap(action: string, index?: number) {
    const dataset: Value = { action };
    if (index !== undefined) {
      dataset.index = String(index);
    }
    const target = { tagName: "BUTTON", dataset };
    const clickHandler = handlers.get("click") as (event: unknown) => void;
    clickHandler({ target: { closest: () => target } });
  }

  // Typing into a form field: the element the page reads by id
  function type(id: string, text: string) {
    const element = elementById(id) as Value;
    element.value = text;
  }

  return { app, records, sets, mainHtml, tap, type };
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

describe("dictation gate: the page", () => {
  it("shows runs, share and average total per path, and the matched words under a run", async () => {
    const page = loadPage(pathFixture());
    await page.app.whenReady();
    const shown = page.mainHtml();
    expect(shown).toContain('<div class="lab">Paths</div>');
    expect(shown).toContain('<div class="path" data-path="skip"><b>Skip</b><span>2 runs · 33% · Avg 155 ms</span></div>');
    expect(shown).toContain('<div class="path" data-path="light"><b>Light</b><span>2 runs · 33% · Avg 1,550 ms</span></div>');
    expect(shown).toContain('<div class="path" data-path="rewrite"><b>Rewrite</b><span>2 runs · 33% · Avg 1,501 ms</span></div>');
    expect(shown).toContain('<div class="words">uh</div>');
  });

  it("shows no per-path numbers before any run went through the gate", async () => {
    const page = loadPage([pathFixture()[6]]);
    await page.app.whenReady();
    expect(page.mainHtml()).not.toContain("Paths");
  });

  it("opens Settings from the ? menu with the built-in settings when none are saved, and writes nothing", async () => {
    const page = loadPage([]);
    await page.app.whenReady();
    page.tap("toggle-help");
    expect(page.mainHtml()).toContain('data-action="show-settings">Settings</button>');
    page.tap("show-settings");
    const shown = page.mainHtml();
    expect(page.app.state().view).toBe("settings");
    expect(page.app.state().settingsSaved).toBe(false);
    expect(shown).toContain('<textarea class="field" id="set-fillers" autocapitalize="off" spellcheck="false">um, uh, erm, hmm, you know, I mean, sort of, kind of, basically</textarea>');
    expect(shown).toContain('id="set-word-0" value="email"');
    expect(shown).toContain('data-action="save-settings">Save</button>');
    expect(settingsSets(page.sets)).toEqual([]);
  });

  it("Save writes what was typed as settings:main, trimmed, and says Saved", async () => {
    const page = loadPage([]);
    await page.app.whenReady();
    page.tap("show-settings");
    page.type("set-fillers", "um, uh,\n er ");
    page.type("set-word-0", " memo ");
    page.type("set-instruction-0", "Write a memo.");
    await page.app.saveSettings();
    const saved = settingsSets(page.sets);
    expect(saved.length).toBe(1);
    expect(saved[0].fillers).toEqual(["um", "uh", "er"]);
    const triggers = saved[0].triggers as Value[];
    expect(triggers[0]).toEqual({ word: "memo", instruction: "Write a memo." });
    expect(triggers.length).toBe(5);
    expect(page.app.state().settingsSaved).toBe(true);
    expect(page.mainHtml()).toContain('<div class="message">Saved</div>');
  });

  it("Save refuses settings that do not fit and names the field, writing nothing", async () => {
    const page = loadPage([]);
    await page.app.whenReady();
    page.tap("show-settings");
    page.type("set-light", "   ");
    await page.app.saveSettings();
    expect(settingsSets(page.sets)).toEqual([]);
    expect(page.mainHtml()).toContain('<div class="message">Can’t Save Light Cleanup</div>');
  });

  it("Add and Remove change the trigger words, keeping what was typed", async () => {
    const page = loadPage([]);
    await page.app.whenReady();
    page.tap("show-settings");
    page.type("set-word-1", "posh");
    page.tap("add-trigger");
    expect(page.app.state().draft.triggers.length).toBe(6);
    expect(page.app.state().draft.triggers[1].word).toBe("posh");
    page.tap("remove-trigger", 0);
    const words: string[] = [];
    for (const trigger of page.app.state().draft.triggers) {
      words.push(trigger.word);
    }
    expect(words).toEqual(["posh", "casual", "list", "bullets", ""]);
  });

  it("loads saved settings, and Reset puts the built-in ones back in the form until Save", async () => {
    const saved = { ...Logic.defaultSettings(), fillers: ["um"], triggers: [{ word: "memo", instruction: "Write a memo." }] };
    const page = loadPage([{ key: "settings:main", value: saved }]);
    await page.app.whenReady();
    expect(page.app.state().settingsSaved).toBe(true);
    page.tap("show-settings");
    expect(page.mainHtml()).toContain('id="set-word-0" value="memo"');
    expect(page.mainHtml()).not.toContain('value="email"');
    page.tap("reset-settings");
    expect(page.mainHtml()).toContain('id="set-word-0" value="email"');
    expect(settingsSets(page.sets)).toEqual([]);
  });

  it("How Dictation Works names the trigger words", async () => {
    const page = loadPage([]);
    await page.app.whenReady();
    page.tap("show-how");
    expect(page.mainHtml()).toContain("Say email, formal, casual, list, bullets first to rewrite.");
  });
});
