// Dictation gate round 2 on the Dictation Sidekick (TEST, staging only; founder 2026-11-13,
// docs/briefs/dictation-gate-test.md, "Round 2 build"). settings:main gains the test phrases
// ({ text, expect, note? }) and the capitalise list, both optional so a round 1 record still fits
// and falls back to the built-in ones; the built-in phrases and instruction fixes match the shell
// (shell/Midas/DictationGate.swift); runs carry `expect` and the page, the tools and jess count
// the runs that took another path; the page edits the phrases and the capitalise list and saves
// them with the rest of the settings.
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
const projectSource = readFileSync(new URL("../../shell/project.yml", import.meta.url), "utf8");

const loaded = loadToolsScript(toolsText);
if (!("tools" in loaded)) {
  throw new Error(loaded.problem);
}
const tools = loaded.tools;

const NOW = "2026-11-13T23:00:00.000Z";
type Value = Record<string, unknown>;
type Records = Array<{ key: string; value: Value }>;
type Phrase = { text: string; expect: string; note?: string };
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

// The settings a round 1 page saved: no phrases, no capitalise list
function roundOneSettings(): Value {
  const settings = Logic.defaultSettings();
  delete settings.phrases;
  delete settings.capitalise;
  return settings;
}

// A Run All run as DictationRunRecord.value writes it
function runAllRun(fields: Value = {}): Value {
  return {
    at: "2026-11-13T22:00:00.000Z", source: "run-all", raw: "send it friday", cleaned: "Send it Friday.", cleanupMs: 0, firstCall: false,
    modelStatus: "Available", device: "iPhone17,1", ios: "27.0", build: "30", path: "skip", matched: [], gateMs: 0.02, expect: "skip",
    ...fields,
  };
}

// Four runs with an expected path (one wrong), one spoken run without
function expectFixture(): Records {
  return [
    { key: "run:1", value: runAllRun({ at: "2026-11-13T22:00:00.000Z" }) },
    { key: "run:2", value: runAllRun({ at: "2026-11-13T22:01:00.000Z", raw: "um ok", path: "light", matched: ["um"], cleanupMs: 1200, expect: "light" }) },
    { key: "run:3", value: runAllRun({ at: "2026-11-13T22:02:00.000Z", raw: "so we go", path: "light", matched: ["so"], cleanupMs: 1300, expect: "skip" }) },
    { key: "run:4", value: runAllRun({ at: "2026-11-13T22:03:00.000Z", raw: "list a b c", path: "rewrite", trigger: "list", cleanupMs: 1100, expect: "rewrite" }) },
    { key: "run:5", value: runAllRun({ at: "2026-11-13T22:04:00.000Z", source: "spoken", expect: undefined, totalMs: 300, releaseToRawMs: 290 }) },
  ];
}

describe("dictation round 2: built-in phrases, capitalise list and instructions", () => {
  it("has 29 or more phrases, round 1's nine first, each trigger word twice, no phrase twice", () => {
    const phrases: Phrase[] = Logic.defaultSettings().phrases;
    expect(phrases.length).toBeGreaterThanOrEqual(29);
    expect(phrases.length).toBeLessThanOrEqual(Logic.PHRASE_LIMITS.phrases);
    expect(phrases[0]).toEqual({ text: "um so like be there at 5 no wait 6", expect: "light" });
    expect(phrases[3]).toEqual({ text: "send the deck to Priya and Tomasz by friday", expect: "skip" });
    expect(phrases[8]).toEqual({ text: "list eggs milk bread coffee", expect: "rewrite" });
    const texts = new Set<string>();
    const triggerCounts: Record<string, number> = {};
    for (const phrase of phrases) {
      expect(texts.has(phrase.text)).toBe(false);
      texts.add(phrase.text);
      expect(Logic.PATHS).toContain(phrase.expect);
      const firstWord = phrase.text.split(/[\s:,]+/)[0].toLowerCase();
      if (phrase.expect === "rewrite") {
        triggerCounts[firstWord] = (triggerCounts[firstWord] ?? 0) + 1;
      }
    }
    for (const word of ["email", "formal", "casual", "list", "bullets"]) {
      expect(triggerCounts[word]).toBeGreaterThanOrEqual(2);
    }
  });

  it("every phrase (but the 60-word one, named by constant) is spelled the same in the shell", () => {
    for (const phrase of Logic.defaultSettings().phrases as Phrase[]) {
      if (phrase.note === "60 words") {
        expect(gateSource).toContain('DictationTestPhrase(text: DictationTestPhrases.rambling, expect: .light, note: "60 words")');
        continue;
      }
      const noteText = phrase.note === undefined ? "" : `, note: "${phrase.note}"`;
      expect(gateSource).toContain(`DictationTestPhrase(text: "${phrase.text}", expect: .${phrase.expect}${noteText})`);
    }
  });

  it("capitalises days and months, but not May", () => {
    const capitalise: string[] = Logic.defaultSettings().capitalise;
    for (const word of ["Monday", "Friday", "Sunday", "January", "March", "December"]) {
      expect(capitalise).toContain(word);
    }
    expect(capitalise).not.toContain("May");
    expect(capitalise.length).toBe(18);
  });

  it("the light instruction replaces backtracks and lists only three or more items; list and bullets never use all capitals", () => {
    const defaults = Logic.defaultSettings();
    expect(defaults.lightInstruction).toContain("the words just before the cue are replaced by the words after it. Never keep both");
    expect(defaults.lightInstruction).toContain('"the browser is firefox scratch that chrome" becomes "The browser is Chrome."');
    expect(defaults.lightInstruction).toContain("only when the text is clearly a list of three or more separate items. Never number one or two items.");
    expect(defaults.lightInstruction).not.toContain("When the speaker lists several items in a row");
    for (const line of defaults.lightInstruction.split("\n")) {
      expect(gateSource).toContain(line);
    }
    const byWord: Record<string, string> = {};
    for (const trigger of defaults.triggers) {
      byWord[trigger.word] = trigger.instruction;
    }
    expect(byWord.list).toContain("sentence case");
    expect(byWord.list).toContain("never all capitals");
    expect(byWord.list).not.toContain("Capitalise each item");
    expect(byWord.bullets).toContain("never all capitals");
  });

  it("build 30 and the shell's limits", () => {
    expect(projectSource).toContain('CURRENT_PROJECT_VERSION: "30"');
    expect(gateSource).toContain("static let maxPhrases = 60");
    expect(gateSource).toContain("static let maxPhraseTextCharacters = 1000");
    expect(gateSource).toContain("static let maxNoteCharacters = 200");
    expect(Logic.PHRASE_LIMITS).toEqual({ phrases: 60, text: 1000, note: 200 });
  });
});

describe("dictation round 2: records", () => {
  it("settings with phrases and a capitalise list fit; a round 1 record still fits", () => {
    expect(schemaProblem("settings:main", Logic.defaultSettings())).toBeNull();
    expect(schemaProblem("settings:main", roundOneSettings())).toBeNull();
    expect(schemaProblem("settings:main", { ...roundOneSettings(), phrases: [{ text: "hi", expect: "skip", note: "x" }], capitalise: [] })).toBeNull();
  });

  it("refuses an empty phrase list, an unknown path, a phrase without text, long text or note, and an empty capitalise word", () => {
    const base = roundOneSettings();
    expect(schemaProblem("settings:main", { ...base, phrases: [] })).not.toBeNull();
    expect(schemaProblem("settings:main", { ...base, phrases: [{ text: "hi", expect: "fast" }] })).not.toBeNull();
    expect(schemaProblem("settings:main", { ...base, phrases: [{ expect: "skip" }] })).not.toBeNull();
    expect(schemaProblem("settings:main", { ...base, phrases: [{ text: "x".repeat(1001), expect: "skip" }] })).not.toBeNull();
    expect(schemaProblem("settings:main", { ...base, phrases: [{ text: "hi", expect: "skip", note: "x".repeat(201) }] })).not.toBeNull();
    expect(schemaProblem("settings:main", { ...base, capitalise: [""] })).not.toBeNull();
    const sixtyOne: Phrase[] = [];
    for (let index = 0; index < 61; index += 1) {
      sixtyOne.push({ text: "p" + index, expect: "skip" });
    }
    expect(schemaProblem("settings:main", { ...base, phrases: sixtyOne })).not.toBeNull();
  });

  it("a run carries the expected path; an unknown one is refused", () => {
    expect(schemaProblem("run:a", runAllRun())).toBeNull();
    expect(schemaProblem("run:a", runAllRun({ expect: "fast" }))).not.toBeNull();
  });
});

describe("dictation round 2: settings are checked as the shell checks them", () => {
  it("a record without phrases or capitalise is saved settings with the built-in ones", () => {
    const resolved = Logic.resolvedSettings(roundOneSettings());
    expect(resolved.saved).toBe(true);
    expect(resolved.settings.phrases).toEqual(Logic.defaultSettings().phrases);
    expect(resolved.settings.capitalise).toEqual(Logic.defaultSettings().capitalise);
  });

  it("trims phrases, drops an empty or null note and keeps the capitalise list as given", () => {
    const stored = {
      ...roundOneSettings(),
      capitalise: [" Sunday "],
      phrases: [{ text: " hi there ", expect: "skip", note: "  " }, { text: "um ok", expect: "light", note: " filler " }, { text: "list a b c", expect: "rewrite", note: null }],
    };
    const settings = Logic.settingsFrom(stored);
    expect(settings.capitalise).toEqual(["Sunday"]);
    expect(settings.phrases).toEqual([
      { text: "hi there", expect: "skip" },
      { text: "um ok", expect: "light", note: "filler" },
      { text: "list a b c", expect: "rewrite" },
    ]);
  });

  it("names phrases or capitalise when they do not fit, and falls back to the built-in settings", () => {
    const base = roundOneSettings();
    const badPhrases = [[], "send it", null, ["send it"], [{ text: "send it", expect: "fast" }], [{ text: "  ", expect: "skip" }],
      [{ text: "send it", expect: "skip", note: 3 }], [{ text: "send it", expect: "skip", note: "x".repeat(201) }]];
    for (const phrases of badPhrases) {
      expect(Logic.settingsProblem({ ...base, phrases })).toBe("phrases");
      expect(Logic.resolvedSettings({ ...base, phrases })).toEqual({ settings: Logic.defaultSettings(), saved: false });
    }
    expect(Logic.settingsProblem({ ...base, capitalise: [""] })).toBe("capitalise");
    expect(Logic.settingsProblem({ ...base, capitalise: "Friday" })).toBe("capitalise");
  });
});

describe("dictation round 2: wrong paths", () => {
  it("counts the runs with an expected path and those that took another", () => {
    const runs = Logic.runsOf(expectFixture());
    expect(Logic.wrongPathOf(runs)).toEqual({ checked: 4, wrong: 1 });
    expect(Logic.wrongPathOf(Logic.runsOf([expectFixture()[4]]))).toEqual({ checked: 0, wrong: 0 });
  });

  it("the run line says the expected path only when it was missed", () => {
    const runs = Logic.runsOf(expectFixture());
    const byKey: Record<string, string> = {};
    for (const run of runs) {
      byKey[run.key] = Logic.timingsLine(run);
    }
    expect(byKey["run:3"]).toBe("Cleanup 1,300 ms · Run All · Light · Expected Skip");
    expect(byKey["run:2"]).toBe("Cleanup 1,200 ms · Run All · Light");
  });

  it("summary and runs tools carry the wrong-path count and each run's expected path", () => {
    const summary = call("summary", {}, expectFixture());
    expect(summary.result.wrongPath).toEqual({ checked: 4, wrong: 1 });
    expect(summary.result.text).toContain("Wrong path 1 of 4 runs.");
    const shown = call("runs", { limit: 5 }, expectFixture()).result.runs as Value[];
    expect(shown[1].expect).toBe("rewrite");
    expect(shown[0].expect).toBeUndefined();
    expect(call("summary", {}, []).result.wrongPath).toBeUndefined();
  });
});

describe("dictation round 2: tools", () => {
  it("settings shows the capitalise list and the phrases", () => {
    const outcome = call("settings", {}, []);
    expect(outcome.result.phrases).toEqual(Logic.defaultSettings().phrases);
    expect(outcome.result.capitalise).toEqual(Logic.defaultSettings().capitalise);
    expect(outcome.result.text).toContain("Capitalise: Monday, Tuesday,");
    expect(outcome.result.text).toContain("Test phrases: " + Logic.defaultSettings().phrases.length + ".");
  });

  it("save_settings replaces the phrases and the capitalise list, keeping the rest", () => {
    const saved = { ...roundOneSettings(), fillers: ["er"] };
    const input = { fillers: null, positionFillers: null, corrections: null, triggers: null, lightInstruction: null,
      capitalise: ["Friday", " Sam "], phrases: [{ text: "call sam friday", expect: "skip", note: null }, { text: "er hi", expect: "light", note: "filler" }] };
    const outcome = call("save_settings", input, [{ key: "settings:main", value: saved }]);
    expect(outcome.refused).toBeUndefined();
    const value = outcome.ops?.[0].value as Value;
    expect(value.fillers).toEqual(["er"]);
    expect(value.capitalise).toEqual(["Friday", "Sam"]);
    expect(value.phrases).toEqual([{ text: "call sam friday", expect: "skip" }, { text: "er hi", expect: "light", note: "filler" }]);
    expect(schemaProblem("settings:main", value)).toBeNull();
    expect(outcome.result.text).toBe("Saved capitalise list, test phrases");
  });

  it("save_settings refuses phrases that do not fit", () => {
    const input = { fillers: null, positionFillers: null, corrections: null, triggers: null, lightInstruction: null, capitalise: null,
      phrases: [{ text: "hi", expect: "fast", note: null }] };
    const outcome = call("save_settings", input, []);
    expect(outcome.refused).toBe("bad phrases");
    expect(outcome.result.text).toBe("Can’t save test phrases");
  });

  it("the save tool's input lists the new fields as required and nullable", () => {
    let saveTool: Value | null = null;
    for (const tool of manifest.agent.tools) {
      if (tool.name === "dictation.save_settings") {
        saveTool = tool;
      }
    }
    const schema = (saveTool as Value).inputSchema as { required: string[]; properties: Record<string, { type: string[] }> };
    expect(schema.required).toContain("phrases");
    expect(schema.required).toContain("capitalise");
    expect(schema.properties.phrases.type).toEqual(["array", "null"]);
    expect(checkBundleFiles(html, manifestText, "dictation", toolsText).problems).toEqual([]);
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

function draftTexts(page: ReturnType<typeof loadPage>) {
  const texts: string[] = [];
  for (const phrase of page.app.state().draft.phrases) {
    texts.push(phrase.text);
  }
  return texts;
}

describe("dictation round 2: the page", () => {
  it("shows the wrong-path count with the per-path numbers", async () => {
    const page = loadPage(expectFixture());
    await page.app.whenReady();
    expect(page.mainHtml()).toContain('<div class="path wrong" data-path="wrong"><b>Wrong Path</b><span>1 of 4 runs</span></div>');
  });

  it("shows no wrong-path row when no run had an expected path", async () => {
    const page = loadPage([expectFixture()[4]]);
    await page.app.whenReady();
    expect(page.mainHtml()).toContain('<div class="lab">Paths</div>');
    expect(page.mainHtml()).not.toContain("Wrong Path");
  });

  it("Settings shows the capitalise list and a row per phrase with its expected path", async () => {
    const page = loadPage([]);
    await page.app.whenReady();
    page.tap("show-settings");
    const shown = page.mainHtml();
    expect(shown).toContain('<div class="lab">Capitalise</div>');
    expect(shown).toContain('id="set-capitalise" autocapitalize="off" spellcheck="false">Monday, Tuesday, Wednesday');
    expect(shown).toContain('<div class="lab">Phrases</div>');
    expect(shown).toContain('id="set-phrase-0" autocapitalize="off" spellcheck="false">um so like be there at 5 no wait 6</textarea>');
    expect(shown).toContain('<option value="light" selected>Light</option>');
    expect(shown).toContain('id="set-note-7" value="backtrack"');
    expect(shown).toContain('data-action="add-phrase">Add Phrase</button>');
    expect(settingsSets(page.sets)).toEqual([]);
  });

  it("Save writes the edited phrases and capitalise list with the rest of the settings", async () => {
    const page = loadPage([]);
    await page.app.whenReady();
    page.tap("show-settings");
    page.type("set-capitalise", "Friday,\n Sam ");
    page.type("set-phrase-0", " call sam friday ");
    page.type("set-expect-0", "skip");
    page.type("set-note-0", " names ");
    await page.app.saveSettings();
    const saved = settingsSets(page.sets);
    expect(saved.length).toBe(1);
    expect(saved[0].capitalise).toEqual(["Friday", "Sam"]);
    const phrases = saved[0].phrases as Phrase[];
    expect(phrases[0]).toEqual({ text: "call sam friday", expect: "skip", note: "names" });
    expect(phrases[1]).toEqual({ text: "uh tell mom im on my way", expect: "light" });
    expect(phrases.length).toBe(Logic.defaultSettings().phrases.length);
    expect(saved[0].fillers).toEqual(Logic.defaultSettings().fillers);
    expect(page.mainHtml()).toContain('<div class="message">Saved</div>');
  });

  it("Add Phrase and Remove change the list, keeping what was typed; an empty new phrase is refused on Save", async () => {
    const page = loadPage([]);
    await page.app.whenReady();
    page.tap("show-settings");
    const count = page.app.state().draft.phrases.length;
    page.type("set-phrase-1", "hello there");
    page.tap("add-phrase");
    expect(draftTexts(page).length).toBe(count + 1);
    expect(draftTexts(page)[1]).toBe("hello there");
    expect(page.app.state().draft.phrases[count]).toEqual({ text: "", expect: "skip", note: "" });
    await page.app.saveSettings();
    expect(settingsSets(page.sets)).toEqual([]);
    expect(page.mainHtml()).toContain('<div class="message">Can’t Save Phrases</div>');
    page.tap("remove-phrase", count);
    page.tap("remove-phrase", 0);
    expect(draftTexts(page).length).toBe(count - 1);
    expect(draftTexts(page)[0]).toBe("hello there");
    await page.app.saveSettings();
    expect(settingsSets(page.sets).length).toBe(1);
  });

  it("loads a round 1 record with the built-in phrases, and Reset brings back the built-in phrases", async () => {
    const saved = { ...roundOneSettings(), phrases: [{ text: "only one", expect: "skip" }] };
    const page = loadPage([{ key: "settings:main", value: saved }]);
    await page.app.whenReady();
    page.tap("show-settings");
    expect(draftTexts(page)).toEqual(["only one"]);
    page.tap("reset-settings");
    expect(draftTexts(page).length).toBe(Logic.defaultSettings().phrases.length);
    expect(settingsSets(page.sets)).toEqual([]);
    const roundOne = loadPage([{ key: "settings:main", value: roundOneSettings() }]);
    await roundOne.app.whenReady();
    expect(roundOne.app.state().settingsSaved).toBe(true);
    expect(roundOne.app.state().settings.phrases).toEqual(Logic.defaultSettings().phrases);
  });
});
