// Dictation gate round 3 on the Dictation Sidekick (TEST, staging only; founder 2026-11-14,
// docs/briefs/dictation-gate-test.md, "Round 3 build (founder approved 2026-11-14): do less, rules
// first"). A fourth path, `rule` (fillers removed or a simple correction applied, no model); the
// built-in settings cut down (four fillers, no position fillers, no trigger words, a one-line light
// instruction with no examples, fifteen phrases, Run All ×3 from settings:main's `repeat`); runs
// log `prewarmed` and `thermal`, and the page, the summary and the tools show the share of runs per
// heat state. The built-in settings match the shell's (shell/Midas/DictationGate.swift).
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

const NOW = "2026-11-14T20:00:00.000Z";
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

// The fifteen phrases of the brief, in its order, with the path each takes
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
  ["the browser is firefox scratch that chrome", "light"],
  ["send it to Tom I mean Tim", "light"],
  ["meet at the cafe on 5th street scratch that the library", "light"],
];

// A Run All run as DictationRunRecord.value writes it in build 31
function roundThreeRun(fields: Value = {}): Value {
  return {
    at: "2026-11-14T19:00:00.000Z", source: "run-all", raw: "um ok", cleaned: "Ok.", cleanupMs: 0, firstCall: false,
    modelStatus: "Available", device: "iPhone17,1", ios: "27.0", build: "31", path: "rule", matched: ["um"], gateMs: 0.03, expect: "rule",
    thermal: "nominal",
    ...fields,
  };
}

// Five runs: three nominal, one fair, one serious (a light run with a prewarmed session), one run
// from build 30 with no heat logged
function heatFixture(): Records {
  return [
    { key: "run:1", value: roundThreeRun({ at: "2026-11-14T19:00:00.000Z" }) },
    { key: "run:2", value: roundThreeRun({ at: "2026-11-14T19:01:00.000Z", path: "skip", matched: [], expect: "skip" }) },
    { key: "run:3", value: roundThreeRun({ at: "2026-11-14T19:02:00.000Z", path: "rule", thermal: "nominal" }) },
    { key: "run:4", value: roundThreeRun({ at: "2026-11-14T19:03:00.000Z", path: "light", cleanupMs: 900, prewarmed: true, thermal: "fair", expect: "light" }) },
    { key: "run:5", value: roundThreeRun({ at: "2026-11-14T19:04:00.000Z", path: "light", cleanupMs: 1500, prewarmed: false, thermal: "serious", expect: "light" }) },
    { key: "run:6", value: roundThreeRun({ at: "2026-11-14T18:00:00.000Z", path: "light", cleanupMs: 2000, thermal: undefined, build: "30", expect: "light" }) },
  ];
}

describe("dictation round 3: the built-in settings", () => {
  it("are the brief's fifteen phrases, in order, each with its path", () => {
    const phrases: Phrase[] = Logic.defaultSettings().phrases;
    const pairs: Array<[string, string]> = [];
    for (const phrase of phrases) {
      pairs.push([phrase.text, phrase.expect]);
    }
    expect(pairs).toEqual(BRIEF_PHRASES);
  });

  it("every phrase is spelled the same in the shell", () => {
    for (const phrase of Logic.defaultSettings().phrases as Phrase[]) {
      const noteText = phrase.note === undefined ? "" : `, note: "${phrase.note}"`;
      expect(gateSource).toContain(`DictationTestPhrase(text: "${phrase.text}", expect: .${phrase.expect}${noteText})`);
    }
  });

  it("four fillers, no position fillers, the brief's corrections, no trigger words, Run All ×3", () => {
    const defaults = Logic.defaultSettings();
    expect(defaults.fillers).toEqual(["um", "uh", "erm", "hmm"]);
    expect(defaults.positionFillers).toEqual([]);
    expect(defaults.corrections).toEqual(["no wait", "wait no", "scratch that", "make that", "I mean", "I meant", "actually", "sorry"]);
    expect(defaults.triggers).toEqual([]);
    expect(defaults.repeat).toBe(3);
    expect(gateSource).toContain('fillers: ["um", "uh", "erm", "hmm"],');
    expect(gateSource).toContain("positionFillers: [],");
    expect(gateSource).toContain('corrections: ["no wait", "wait no", "scratch that", "make that", "I mean", "I meant", "actually", "sorry"],');
    expect(gateSource).toContain("triggers: [],");
    expect(gateSource).toContain("static let builtInRepeat = 3");
    expect(gateSource).toContain("static let maxRepeat = 20");
    expect(Logic.REPEAT_LIMITS).toEqual({ min: 1, max: 20, builtIn: 3 });
  });

  it("the light instruction is one line with no examples, the same in the shell", () => {
    const instruction: string = Logic.defaultSettings().lightInstruction;
    expect(instruction).toBe("Remove the correction and the words it replaces. Change nothing else. Reply with the text only.");
    expect(instruction).not.toContain("\n");
    expect(instruction).not.toContain('"');
    expect(instruction).not.toContain("becomes");
    expect(gateSource).toContain(`static let builtInLightInstruction = "${instruction}"`);
  });

  it("build 31", () => {
    expect(projectSource).toContain('CURRENT_PROJECT_VERSION: "31"');
    expect(projectSource).not.toContain('CURRENT_PROJECT_VERSION: "30"');
  });
});

describe("dictation round 3: records", () => {
  it("a run may take the rule path, log prewarmed and its heat", () => {
    expect(schemaProblem("run:a", roundThreeRun())).toBeNull();
    expect(schemaProblem("run:a", roundThreeRun({ path: "light", expect: "rule", prewarmed: true, thermal: "critical" }))).toBeNull();
    expect(schemaProblem("run:a", roundThreeRun({ thermal: "hot" }))).not.toBeNull();
    expect(schemaProblem("run:a", roundThreeRun({ prewarmed: "yes" }))).not.toBeNull();
    expect(schemaProblem("run:a", roundThreeRun({ path: "fast" }))).not.toBeNull();
  });

  it("settings carry rule phrases and a repeat from 1 to 20; a round 2 record without repeat still fits", () => {
    const defaults = Logic.defaultSettings();
    expect(schemaProblem("settings:main", defaults)).toBeNull();
    const withoutRepeat = { ...defaults };
    delete withoutRepeat.repeat;
    expect(schemaProblem("settings:main", withoutRepeat)).toBeNull();
    expect(schemaProblem("settings:main", { ...defaults, repeat: 1 })).toBeNull();
    expect(schemaProblem("settings:main", { ...defaults, repeat: 20 })).toBeNull();
    expect(schemaProblem("settings:main", { ...defaults, repeat: 0 })).not.toBeNull();
    expect(schemaProblem("settings:main", { ...defaults, repeat: 21 })).not.toBeNull();
    expect(schemaProblem("settings:main", { ...defaults, repeat: 2.5 })).not.toBeNull();
    expect(schemaProblem("settings:main", { ...defaults, phrases: [{ text: "um ok", expect: "rule" }] })).toBeNull();
  });

  it("a summary with the rule path and the heat shares fits", () => {
    const summary = {
      runs: 2, updatedAt: NOW,
      paths: { skip: { runs: 0, sharePercent: 0 }, rule: { runs: 2, sharePercent: 100, averageTotalMs: 0 }, light: { runs: 0, sharePercent: 0 },
        rewrite: { runs: 0, sharePercent: 0 } },
      thermal: { nominal: { runs: 1, sharePercent: 50 }, fair: { runs: 1, sharePercent: 50 }, serious: { runs: 0, sharePercent: 0 },
        critical: { runs: 0, sharePercent: 0 } },
    };
    expect(schemaProblem("summary:main", summary)).toBeNull();
    expect(schemaProblem("summary:main", { ...summary, thermal: { nominal: { runs: 1, sharePercent: 101 } } })).not.toBeNull();
  });
});

describe("dictation round 3: settings are checked as the shell checks them", () => {
  it("a record without repeat is saved settings with Run All ×3", () => {
    const stored = { ...Logic.defaultSettings(), fillers: ["er"] };
    delete stored.repeat;
    const resolved = Logic.resolvedSettings(stored);
    expect(resolved.saved).toBe(true);
    expect(resolved.settings.fillers).toEqual(["er"]);
    expect(resolved.settings.repeat).toBe(3);
  });

  it("names a repeat that does not fit and falls back to the built-in settings", () => {
    for (const repeat of [0, 21, 2.5, "3", null, -1]) {
      const stored = { ...Logic.defaultSettings(), fillers: ["er"], repeat };
      expect(Logic.settingsProblem(stored)).toBe("repeat");
      expect(Logic.resolvedSettings(stored)).toEqual({ settings: Logic.defaultSettings(), saved: false });
    }
    expect(Logic.settingsFrom({ ...Logic.defaultSettings(), repeat: 7 }).repeat).toBe(7);
  });
});

describe("dictation round 3: runs, paths and heat", () => {
  it("reads prewarmed and the heat, and says them on the run line", () => {
    const runs = Logic.runsOf(heatFixture());
    const byKey: Record<string, { prewarmed: boolean | null; thermal: string | null; line: string }> = {};
    for (const run of runs) {
      byKey[run.key] = { prewarmed: run.prewarmed, thermal: run.thermal, line: Logic.timingsLine(run) };
    }
    expect(byKey["run:4"]).toEqual({ prewarmed: true, thermal: "fair", line: "Cleanup 900 ms · Run All · Light · Prewarmed · Heat Fair" });
    expect(byKey["run:5"].line).toBe("Cleanup 1,500 ms · Run All · Light · Heat Serious");
    expect(byKey["run:1"].line).toBe("Cleanup 0 ms · Run All · Rule · Heat Nominal");
    expect(byKey["run:6"]).toEqual({ prewarmed: null, thermal: null, line: "Cleanup 2,000 ms · Run All · Light" });
  });

  it("counts the rule path with the others", () => {
    const paths = Logic.pathSummaryOf(Logic.runsOf(heatFixture()));
    expect(Object.keys(paths)).toEqual(["skip", "rule", "light", "rewrite"]);
    expect(paths.rule).toEqual({ runs: 2, sharePercent: 33, averageTotalMs: 0 });
    expect(paths.light).toEqual({ runs: 3, sharePercent: 50, averageTotalMs: 1467 });
    expect(paths.skip).toEqual({ runs: 1, sharePercent: 17, averageTotalMs: 0 });
  });

  it("shares runs per heat state over the runs that logged it", () => {
    const heat = Logic.thermalSummaryOf(Logic.runsOf(heatFixture()));
    expect(heat).toEqual({
      nominal: { runs: 3, sharePercent: 60 }, fair: { runs: 1, sharePercent: 20 }, serious: { runs: 1, sharePercent: 20 },
      critical: { runs: 0, sharePercent: 0 },
    });
    expect(Logic.thermalSummaryOf(Logic.runsOf([heatFixture()[5]]))).toBeNull();
  });
});

describe("dictation round 3: tools", () => {
  it("summary carries the heat shares and the rule path", () => {
    const outcome = call("summary", {}, heatFixture());
    expect(outcome.result.thermal).toEqual(Logic.thermalSummaryOf(Logic.runsOf(heatFixture())));
    expect(outcome.result.text).toContain("Rule 2 runs (33%), avg 0 ms;");
    expect(outcome.result.text).toContain("Heat nominal 60%, fair 20%, serious 20%, critical 0%.");
    expect(call("summary", {}, [heatFixture()[5]]).result.thermal).toBeUndefined();
  });

  it("runs shows prewarmed and the heat when logged", () => {
    const shown = call("runs", { limit: 6 }, heatFixture()).result.runs as Value[];
    expect(shown[1].prewarmed).toBe(true);
    expect(shown[1].thermal).toBe("fair");
    expect(shown[0].prewarmed).toBe(false);
    expect(shown[5].thermal).toBeUndefined();
    expect(shown[5].prewarmed).toBeUndefined();
  });

  it("settings shows repeat, and says none for empty lists", () => {
    const outcome = call("settings", {}, []);
    expect(outcome.result.repeat).toBe(3);
    expect(outcome.result.text).toContain("By position: none.");
    expect(outcome.result.text).toContain("Trigger words: none.");
    expect(outcome.result.text).toContain("Test phrases: 15. Run All repeats: 3.");
  });

  it("save_settings changes repeat only, and refuses one that does not fit", () => {
    const saved = { ...Logic.defaultSettings(), fillers: ["er"] };
    const input = { fillers: null, positionFillers: null, corrections: null, triggers: null, lightInstruction: null, capitalise: null, phrases: null,
      repeat: 5 };
    const outcome = call("save_settings", input, [{ key: "settings:main", value: saved }]);
    expect(outcome.refused).toBeUndefined();
    const value = outcome.ops?.[0].value as Value;
    expect(value.repeat).toBe(5);
    expect(value.fillers).toEqual(["er"]);
    expect(schemaProblem("settings:main", value)).toBeNull();
    expect(outcome.result.text).toBe("Saved run all repeats");
    const tooMany = call("save_settings", { ...input, repeat: 21 }, []);
    expect(tooMany.refused).toBe("bad repeat");
    expect(tooMany.result.text).toBe("Can’t save run all repeats");
  });

  it("the save tool's input lists repeat as required and nullable, and rule as a phrase path", () => {
    let saveTool: Value | null = null;
    for (const tool of manifest.agent.tools) {
      if (tool.name === "dictation.save_settings") {
        saveTool = tool;
      }
    }
    const schema = (saveTool as Value).inputSchema as {
      required: string[];
      properties: Record<string, { type: string[]; items?: { properties: Record<string, { enum?: string[] }> } }>;
    };
    expect(schema.required).toContain("repeat");
    expect(schema.properties.repeat.type).toEqual(["integer", "null"]);
    expect(schema.properties.phrases.items?.properties.expect.enum).toEqual(["skip", "rule", "light", "rewrite"]);
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

describe("dictation round 3: the page", () => {
  it("shows the rule path with the others and the heat shares", async () => {
    const page = loadPage(heatFixture());
    await page.app.whenReady();
    const shown = page.mainHtml();
    expect(shown).toContain('<div class="path" data-path="rule"><b>Rule</b><span>2 runs · 33% · Avg 0 ms</span></div>');
    expect(shown).toContain('<div class="lab">Heat</div>');
    expect(shown).toContain('<div class="path" data-heat="nominal"><b>Nominal</b><span>3 runs · 60%</span></div>');
    expect(shown).toContain('<div class="path" data-heat="fair"><b>Fair</b><span>1 run · 20%</span></div>');
    expect(shown.indexOf('data-path="rule"')).toBeLessThan(shown.indexOf('data-path="light"'));
    expect(shown.indexOf('<div class="lab">Paths</div>')).toBeLessThan(shown.indexOf('<div class="lab">Heat</div>'));
  });

  it("shows no heat card when no run logged the heat", async () => {
    const page = loadPage([heatFixture()[5]]);
    await page.app.whenReady();
    expect(page.mainHtml()).toContain('<div class="lab">Paths</div>');
    expect(page.mainHtml()).not.toContain("Heat");
  });

  it("Settings shows the repeat count and a Rule choice for each phrase", async () => {
    const page = loadPage([]);
    await page.app.whenReady();
    page.tap("show-settings");
    const shown = page.mainHtml();
    expect(shown).toContain('<div class="lab">Run All Repeats</div><input class="field" id="set-repeat" type="number" inputmode="numeric" min="1" max="20" value="3"');
    expect(shown).toContain('<option value="rule" selected>Rule</option>');
    expect(shown).toContain('id="set-phrase-5" autocapitalize="off" spellcheck="false">uh tell mom im on my way</textarea>');
    expect(settingsSets(page.sets)).toEqual([]);
  });

  it("Save writes the typed repeat with the rest of the settings", async () => {
    const page = loadPage([]);
    await page.app.whenReady();
    page.tap("show-settings");
    page.type("set-repeat", " 5 ");
    await page.app.saveSettings();
    const saved = settingsSets(page.sets);
    expect(saved.length).toBe(1);
    expect(saved[0].repeat).toBe(5);
    expect(saved[0].phrases).toEqual(Logic.defaultSettings().phrases);
    expect(page.app.state().settings.repeat).toBe(5);
    expect(page.mainHtml()).toContain('<div class="message">Saved</div>');
  });

  it("Save refuses a repeat that does not fit and writes nothing", async () => {
    for (const typed of ["0", "21", "two", "2.5", ""]) {
      const page = loadPage([]);
      await page.app.whenReady();
      page.tap("show-settings");
      page.type("set-repeat", typed);
      await page.app.saveSettings();
      expect(settingsSets(page.sets)).toEqual([]);
      expect(page.mainHtml()).toContain('<div class="message">Can’t Save Run All Repeats</div>');
    }
  });

  it("loads a round 2 record without repeat as saved, with Run All ×3", async () => {
    const roundTwo = { ...Logic.defaultSettings(), fillers: ["er"] };
    delete roundTwo.repeat;
    const page = loadPage([{ key: "settings:main", value: roundTwo }]);
    await page.app.whenReady();
    expect(page.app.state().settingsSaved).toBe(true);
    expect(page.app.state().settings.repeat).toBe(3);
    expect(page.app.state().settings.fillers).toEqual(["er"]);
  });
});
