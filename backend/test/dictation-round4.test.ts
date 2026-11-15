// Dictation gate round 4 on the Dictation Sidekick (TEST, staging only; founder 2026-11-14,
// docs/briefs/dictation-gate-test.md, "Round 4 build (founder approved 2026-11-14): corrections by
// rule, the model only points"). Cues split in two (`strongCues` the rules may act on, `weakCues`
// for the model pointer only), `anchors` for the anchor rule, the light instruction is the model
// pointer's one line (no examples), twenty phrases (round 3's fifteen, firefox, Tom/Tim and the
// cafe now rule, and five new ones), light runs log `pointer` and `pointerValid`, and the page,
// the summary and the tools show the pointer's valid share. The built-in settings match the
// shell's (shell/Midas/DictationGate.swift). The rules themselves run in the shell and are checked
// there (DictationRound4Tests).
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

const NOW = "2026-11-14T22:00:00.000Z";
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

const STRONG = ["scratch that", "no wait", "wait no", "I mean", "I meant", "make that", "no no"];
const WEAK = ["actually", "sorry"];
const ANCHORS = ["the", "a", "an", "to", "at", "on", "in", "for", "with", "my", "your", "our", "his", "her", "their"];
const POINTER_INSTRUCTION =
  "The words after the bracketed cue may correct words just before it. Give those replaced words exactly as written, or leave it empty when nothing is replaced.";

// The brief's twenty: round 3's fifteen (firefox, Tom/Tim and the cafe now rule), then the five new
const BRIEF_PHRASES: Array<[string, string]> = [
  ["send the deck to Priya by friday", "skip"],
  ["lunch with Maya on tuesday at 12:30", "skip"],
  ["I like the new logo a lot", "skip"],
  ["it was so good to see you yesterday", "skip"],
  ["call David back before 5 tomorrow", "skip"],
  ["uh tell mom im on my way", "rule"],
  ["um pack the charger the passport and the tickets", "rule"],
  ["for the party we need uh cups plates napkins and ice", "rule"],
  ["the call is at 2 no wait 3", "rule"],
  ["order 3 pizzas make that 4", "rule"],
  ["book the table for friday no wait saturday", "rule"],
  ["um be there at 5 no wait 6", "rule"],
  ["the browser is firefox scratch that chrome", "rule"],
  ["send it to Tom I mean Tim", "rule"],
  ["meet at the cafe on 5th street scratch that the library", "rule"],
  ["meet at noon scratch that at 1 pm", "rule"],
  ["invite Ana and Jonas scratch that just Ana", "light"],
  ["I actually like the new plan", "light"],
  ["the meeting is in room 4 sorry room 5", "rule"],
  ["send the file to Sam no wait to Priya", "rule"],
];

// A Run All run as DictationRunRecord.value writes it in build 32
function roundFourRun(fields: Value = {}): Value {
  return {
    at: "2026-11-14T21:00:00.000Z", source: "run-all", raw: "invite Ana and Jonas scratch that just Ana", cleaned: "Invite just Ana.",
    cleanupMs: 850, firstCall: false, modelStatus: "Available", device: "iPhone17,1", ios: "27.0", build: "32", path: "light",
    matched: ["scratch that"], gateMs: 0.04, expect: "light", prewarmed: true, thermal: "nominal", pointer: "Ana and Jonas", pointerValid: true,
    ...fields,
  };
}

// Three light runs with a pointer (valid, valid with no words, not valid), a rule run without one
function pointerFixture(): Records {
  return [
    { key: "run:1", value: roundFourRun({ at: "2026-11-14T21:00:00.000Z" }) },
    { key: "run:2", value: roundFourRun({ at: "2026-11-14T21:01:00.000Z", raw: "I actually like the new plan", cleaned: "I actually like the new plan.", pointer: "" }) },
    { key: "run:3", value: roundFourRun({ at: "2026-11-14T21:02:00.000Z", pointer: "Tom", pointerValid: false, cleanupMs: 900 }) },
    {
      key: "run:4",
      value: roundFourRun({ at: "2026-11-14T21:03:00.000Z", path: "rule", expect: "rule", cleanupMs: 0, pointer: undefined, pointerValid: undefined,
        prewarmed: undefined }),
    },
  ];
}

function runByKey(records: Records, key: string) {
  for (const run of Logic.runsOf(records)) {
    if (run.key === key) {
      return run;
    }
  }
  return null;
}

describe("dictation round 4: the built-in settings", () => {
  it("are the brief's twenty phrases, in order, each with its path", () => {
    const pairs: Array<[string, string]> = [];
    for (const phrase of Logic.defaultSettings().phrases as Phrase[]) {
      pairs.push([phrase.text, phrase.expect]);
    }
    expect(pairs).toEqual(BRIEF_PHRASES);
    expect(Logic.defaultSettings().repeat).toBe(3);
  });

  it("every phrase is spelled the same in the shell", () => {
    for (const phrase of Logic.defaultSettings().phrases as Phrase[]) {
      const noteText = phrase.note === undefined ? "" : `, note: "${phrase.note}"`;
      expect(gateSource).toContain(`DictationTestPhrase(text: "${phrase.text}", expect: .${phrase.expect}${noteText})`);
    }
  });

  it("strong cues, weak cues and anchors are the brief's, the same in the shell; corrections holds every cue", () => {
    const defaults = Logic.defaultSettings();
    expect(defaults.strongCues).toEqual(STRONG);
    expect(defaults.weakCues).toEqual(WEAK);
    expect(defaults.anchors).toEqual(ANCHORS);
    expect(defaults.corrections).toEqual(STRONG.concat(WEAK));
    expect(gateSource).toContain('static let builtInStrongCues = ["scratch that", "no wait", "wait no", "I mean", "I meant", "make that", "no no"]');
    expect(gateSource).toContain('static let builtInWeakCues = ["actually", "sorry"]');
    expect(gateSource).toContain(
      'static let builtInAnchors = ["the", "a", "an", "to", "at", "on", "in", "for", "with", "my", "your", "our", "his", "her", "their"]',
    );
    expect(gateSource).toContain("corrections: builtInStrongCues + builtInWeakCues,");
  });

  it("the light instruction is the pointer's one line with no examples, the same in the shell", () => {
    const instruction: string = Logic.defaultSettings().lightInstruction;
    expect(instruction).toBe(POINTER_INSTRUCTION);
    expect(instruction).not.toContain("\n");
    expect(instruction).not.toContain('"');
    expect(instruction).not.toContain("→");
    expect(gateSource).toContain(`static let builtInLightInstruction = "${instruction}"`);
  });

  it("build 32", () => {
    expect(projectSource).toContain('CURRENT_PROJECT_VERSION: "32"');
    expect(projectSource).not.toContain('CURRENT_PROJECT_VERSION: "31"');
  });
});

describe("dictation round 4: records", () => {
  it("a light run may log the pointer's words and whether they fit", () => {
    expect(schemaProblem("run:a", roundFourRun())).toBeNull();
    expect(schemaProblem("run:a", roundFourRun({ pointer: "", pointerValid: true }))).toBeNull();
    expect(schemaProblem("run:a", roundFourRun({ pointerValid: "yes" }))).not.toBeNull();
    expect(schemaProblem("run:a", roundFourRun({ pointer: 3 }))).not.toBeNull();
    expect(schemaProblem("run:a", roundFourRun({ pointer: "x".repeat(401) }))).not.toBeNull();
    expect(schemaProblem("run:a", roundFourRun({ pointer: "x".repeat(400) }))).toBeNull();
  });

  it("the built-in settings fit, and so does a round 3 record without the new lists", () => {
    const defaults = Logic.defaultSettings();
    expect(schemaProblem("settings:main", defaults)).toBeNull();
    const roundThree = { ...defaults };
    delete roundThree.strongCues;
    delete roundThree.weakCues;
    delete roundThree.anchors;
    expect(schemaProblem("settings:main", roundThree)).toBeNull();
    expect(schemaProblem("settings:main", { ...defaults, anchors: [""] })).not.toBeNull();
    expect(schemaProblem("settings:main", { ...defaults, strongCues: ["x".repeat(41)] })).not.toBeNull();
  });

  it("a summary with the pointer's numbers fits", () => {
    const summary = { runs: 3, updatedAt: NOW, pointer: { runs: 3, valid: 2, empty: 1, sharePercent: 67 } };
    expect(schemaProblem("summary:main", summary)).toBeNull();
    expect(schemaProblem("summary:main", { ...summary, pointer: { runs: 3, valid: 2, empty: 1, sharePercent: 101 } })).not.toBeNull();
    expect(schemaProblem("summary:main", { ...summary, pointer: { runs: 3, valid: 2 } })).not.toBeNull();
  });
});

describe("dictation round 4: cue lists are read as the shell reads them", () => {
  it("a round 3 record splits its corrections: actually and sorry weak, the rest strong; anchors built in", () => {
    const roundThree = { ...Logic.defaultSettings(), corrections: ["no wait", "scratch that", "Sorry", "hold on"] };
    delete roundThree.strongCues;
    delete roundThree.weakCues;
    delete roundThree.anchors;
    const settings = Logic.settingsFrom(roundThree);
    expect(settings.strongCues).toEqual(["no wait", "scratch that", "hold on"]);
    expect(settings.weakCues).toEqual(["Sorry"]);
    expect(settings.anchors).toEqual(ANCHORS);
    expect(settings.corrections).toEqual(["no wait", "scratch that", "Sorry", "hold on"]);
  });

  it("the two lists count when together they are the corrections, in any order or case", () => {
    const stored = { ...Logic.defaultSettings(), strongCues: ["hold on"], weakCues: ["actually", "well"], corrections: ["WELL", "hold on", "actually"] };
    const settings = Logic.settingsFrom(stored);
    expect(settings.strongCues).toEqual(["hold on"]);
    expect(settings.weakCues).toEqual(["actually", "well"]);
  });

  it("corrections changed by an older writer win over lists that no longer match", () => {
    const stored = { ...Logic.defaultSettings(), corrections: ["oops", "sorry"] };
    const settings = Logic.settingsFrom(stored);
    expect(settings.strongCues).toEqual(["oops"]);
    expect(settings.weakCues).toEqual(["sorry"]);
    expect(settings.corrections).toEqual(["oops", "sorry"]);
  });

  it("names the list that does not fit and falls back to the built-in settings", () => {
    const base = Logic.defaultSettings();
    const cases: Array<[Value, string]> = [
      [{ strongCues: [""] }, "strongCues"],
      [{ weakCues: "sorry" }, "weakCues"],
      [{ anchors: ["x".repeat(41)] }, "anchors"],
      [{ strongCues: new Array(30).fill("a"), weakCues: new Array(21).fill("b") }, "weakCues"],
    ];
    for (const [change, field] of cases) {
      const stored = { ...base, fillers: ["er"], ...change };
      expect(Logic.settingsProblem(stored)).toBe(field);
      expect(Logic.resolvedSettings(stored)).toEqual({ settings: Logic.defaultSettings(), saved: false });
    }
    const fifty = { ...base, strongCues: new Array(30).fill("a"), weakCues: new Array(20).fill("b"), corrections: new Array(50).fill("a") };
    expect(Logic.settingsProblem(fifty)).toBeNull();
  });
});

describe("dictation round 4: runs and the pointer's numbers", () => {
  it("reads the pointer and says it on the run line", () => {
    const records = pointerFixture();
    expect(runByKey(records, "run:1").pointer).toBe("Ana and Jonas");
    expect(runByKey(records, "run:1").pointerValid).toBe(true);
    expect(Logic.timingsLine(runByKey(records, "run:1"))).toBe("Cleanup 850 ms · Run All · Light · Prewarmed · Heat Nominal · Pointer: Ana and Jonas");
    expect(Logic.timingsLine(runByKey(records, "run:2"))).toBe("Cleanup 850 ms · Run All · Light · Prewarmed · Heat Nominal · Pointer: None");
    expect(Logic.timingsLine(runByKey(records, "run:3"))).toBe("Cleanup 900 ms · Run All · Light · Prewarmed · Heat Nominal · Pointer Invalid: Tom");
    expect(runByKey(records, "run:4").pointerValid).toBeNull();
    expect(Logic.timingsLine(runByKey(records, "run:4"))).toBe("Cleanup 0 ms · Run All · Rule · Heat Nominal");
  });

  it("counts valid and empty pointers over the runs that logged one", () => {
    expect(Logic.pointerSummaryOf(Logic.runsOf(pointerFixture()))).toEqual({ runs: 3, valid: 2, empty: 1, sharePercent: 67 });
    expect(Logic.pointerSummaryOf(Logic.runsOf([pointerFixture()[3]]))).toBeNull();
  });
});

describe("dictation round 4: tools", () => {
  it("summary carries the pointer's numbers", () => {
    const outcome = call("summary", {}, pointerFixture());
    expect(outcome.result.pointer).toEqual({ runs: 3, valid: 2, empty: 1, sharePercent: 67 });
    expect(outcome.result.text).toContain("Pointer valid 2 of 3 (67%), no words 1.");
    expect(call("summary", {}, [pointerFixture()[3]]).result.pointer).toBeUndefined();
  });

  it("runs shows the pointer on light runs only", () => {
    const shown = call("runs", { limit: 4 }, pointerFixture()).result.runs as Value[];
    expect(shown[0].pointer).toBeUndefined();
    expect(shown[0].pointerValid).toBeUndefined();
    expect(shown[1]).toMatchObject({ pointer: "Tom", pointerValid: false });
    expect(shown[2]).toMatchObject({ pointer: "", pointerValid: true });
    expect(shown[3]).toMatchObject({ pointer: "Ana and Jonas", pointerValid: true });
  });

  it("settings shows the strong and weak cues and the anchors", () => {
    const outcome = call("settings", {}, []);
    expect(outcome.result.strongCues).toEqual(STRONG);
    expect(outcome.result.weakCues).toEqual(WEAK);
    expect(outcome.result.anchors).toEqual(ANCHORS);
    expect(outcome.result.text).toContain(`Strong cues: ${STRONG.join(", ")}. Weak cues: actually, sorry. Anchors: ${ANCHORS.join(", ")}.`);
    expect(outcome.result.text).toContain("Test phrases: 20. Run All repeats: 3.");
  });

  it("save_settings changes the weak cues only, and corrections follow the two lists", () => {
    const input = { fillers: null, positionFillers: null, strongCues: null, weakCues: ["actually", "sorry", "well"], anchors: null, triggers: null,
      lightInstruction: null, capitalise: null, phrases: null, repeat: null };
    const outcome = call("save_settings", input, []);
    expect(outcome.refused).toBeUndefined();
    expect(outcome.result.text).toBe("Saved weak cues");
    const value = outcome.ops?.[0].value as Value;
    expect(value.weakCues).toEqual(["actually", "sorry", "well"]);
    expect(value.strongCues).toEqual(STRONG);
    expect(value.corrections).toEqual(STRONG.concat(["actually", "sorry", "well"]));
    expect(value.anchors).toEqual(ANCHORS);
    expect(schemaProblem("settings:main", value)).toBeNull();
    // What was saved reads back with the new weak cue
    expect(Logic.settingsFrom(value).weakCues).toEqual(["actually", "sorry", "well"]);
  });

  it("save_settings refuses anchors that do not fit", () => {
    const input = { fillers: null, positionFillers: null, strongCues: null, weakCues: null, anchors: [" "], triggers: null, lightInstruction: null,
      capitalise: null, phrases: null, repeat: null };
    const outcome = call("save_settings", input, []);
    expect(outcome.refused).toBe("bad anchors");
    expect(outcome.result.text).toBe("Can’t save anchors");
    expect(outcome.ops).toBeUndefined();
  });

  it("the save tool takes the two cue lists and the anchors, required and nullable, in place of corrections", () => {
    let saveTool: Value | null = null;
    for (const tool of manifest.agent.tools) {
      if (tool.name === "dictation.save_settings") {
        saveTool = tool;
      }
    }
    const schema = (saveTool as Value).inputSchema as { required: string[]; properties: Record<string, { type: string[] }> };
    for (const field of ["strongCues", "weakCues", "anchors"]) {
      expect(schema.required).toContain(field);
      expect(schema.properties[field].type).toEqual(["array", "null"]);
    }
    expect(schema.properties.corrections).toBeUndefined();
    expect(schema.required).not.toContain("corrections");
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

  function tap(action: string) {
    const target = { tagName: "BUTTON", dataset: { action } };
    const clickHandler = handlers.get("click") as (event: unknown) => void;
    clickHandler({ target: { closest: () => target } });
  }

  // Typing into a form field: the element the page reads by id
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

describe("dictation round 4: the page", () => {
  it("shows the pointer's valid share after the paths, before the heat", async () => {
    const page = loadPage(pointerFixture());
    await page.app.whenReady();
    const shown = page.mainHtml();
    expect(shown).toContain(
      '<div class="lab">Pointer</div><div class="card"><div class="path" data-pointer="valid"><b>Valid</b><span>2 of 3 runs · 67%</span></div>'
        + '<div class="path wrong" data-pointer="invalid"><b>Invalid</b><span>1</span></div>'
        + '<div class="path" data-pointer="empty"><b>No Words</b><span>1</span></div></div>',
    );
    expect(shown.indexOf('<div class="lab">Paths</div>')).toBeLessThan(shown.indexOf('<div class="lab">Pointer</div>'));
    expect(shown.indexOf('<div class="lab">Pointer</div>')).toBeLessThan(shown.indexOf('<div class="lab">Heat</div>'));
    expect(shown).toContain("Pointer Invalid: Tom");
  });

  it("shows no pointer card when no run logged a pointer", async () => {
    const page = loadPage([pointerFixture()[3]]);
    await page.app.whenReady();
    expect(page.mainHtml()).toContain('<div class="lab">Paths</div>');
    expect(page.mainHtml()).not.toContain('<div class="lab">Pointer</div>');
  });

  it("Settings shows strong cues, weak cues and anchors in place of corrections", async () => {
    const page = loadPage([]);
    await page.app.whenReady();
    page.tap("show-settings");
    const shown = page.mainHtml();
    expect(shown).toContain(`<div class="lab">Strong Cues</div><textarea class="field" id="set-strong" autocapitalize="off" spellcheck="false">${STRONG.join(", ")}</textarea>`);
    expect(shown).toContain('<div class="lab">Weak Cues</div><textarea class="field" id="set-weak" autocapitalize="off" spellcheck="false">actually, sorry</textarea>');
    expect(shown).toContain(`<div class="lab">Anchors</div><textarea class="field" id="set-anchors" autocapitalize="off" spellcheck="false">${ANCHORS.join(", ")}</textarea>`);
    expect(shown).not.toContain('id="set-corrections"');
    expect(shown).toContain('id="set-phrase-19" autocapitalize="off" spellcheck="false">send the file to Sam no wait to Priya</textarea>');
    expect(settingsSets(page.sets)).toEqual([]);
  });

  it("Save writes the typed cue lists and anchors, with corrections holding both lists", async () => {
    const page = loadPage([]);
    await page.app.whenReady();
    page.tap("show-settings");
    page.type("set-strong", "scratch that, hold on");
    page.type("set-weak", " actually ,\nwell ");
    page.type("set-anchors", "the, to");
    await page.app.saveSettings();
    const saved = settingsSets(page.sets);
    expect(saved.length).toBe(1);
    expect(saved[0].strongCues).toEqual(["scratch that", "hold on"]);
    expect(saved[0].weakCues).toEqual(["actually", "well"]);
    expect(saved[0].anchors).toEqual(["the", "to"]);
    expect(saved[0].corrections).toEqual(["scratch that", "hold on", "actually", "well"]);
    expect(page.app.state().settings.weakCues).toEqual(["actually", "well"]);
    expect(page.mainHtml()).toContain('<div class="message">Saved</div>');
  });

  it("Save refuses anchors that do not fit and writes nothing", async () => {
    const page = loadPage([]);
    await page.app.whenReady();
    page.tap("show-settings");
    page.type("set-anchors", "the, " + "x".repeat(41));
    await page.app.saveSettings();
    expect(settingsSets(page.sets)).toEqual([]);
    expect(page.mainHtml()).toContain('<div class="message">Can’t Save Anchors</div>');
  });

  it("loads a round 3 record as saved, its corrections split", async () => {
    const roundThree = { ...Logic.defaultSettings(), corrections: ["no wait", "sorry"] };
    delete roundThree.strongCues;
    delete roundThree.weakCues;
    delete roundThree.anchors;
    const page = loadPage([{ key: "settings:main", value: roundThree }]);
    await page.app.whenReady();
    expect(page.app.state().settingsSaved).toBe(true);
    expect(page.app.state().settings.strongCues).toEqual(["no wait"]);
    expect(page.app.state().settings.weakCues).toEqual(["sorry"]);
    expect(page.app.state().settings.anchors).toEqual(ANCHORS);
  });
});
