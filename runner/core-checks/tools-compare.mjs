// Tools before and after (docs/briefs/repair-lanes.md W1; founder D3, 2026-11-13): every jess tool
// of the copy as it was, run on a copy of the person's records with the old and the new tools.js,
// must answer the same unless the repair request names that tool; every tool stays (D1: "remove"
// means hide, the tool answers "turned off"), and every page control a tool names is still on
// the new page.
//
// tools.js runs as on the phone and in the jess re-run (runner/lib/jess-rerun.mjs): node:vm, no
// network, no store. Here the clock is fixed and Math.random is seeded, both reset before each
// call, so the old and the new code see the same time and the same "random" ids.
import vm from "node:vm";
import { sampleInputs } from "./tool-inputs.mjs";

const TOOLS_GLOBAL = "MidasSidekickTools";
const RUN_TIMEOUT_MS = 2000;
const PAGE_ACTIONS_KEY = "midas/page-actions";
// How much of a differing answer the problem text quotes
const QUOTE_LIMIT = 240;

// Defines a fixed Date and a seeded Math.random inside the tools' context, and a reset for both.
const DETERMINISM_PRELUDE = `
(function makeDeterministic(fixedTime) {
  var RealDate = Date;
  function FixedDate() {
    var dateArguments = Array.prototype.slice.call(arguments);
    if (!(this instanceof FixedDate)) {
      return new RealDate(fixedTime).toString();
    }
    if (dateArguments.length === 0) {
      return new RealDate(fixedTime);
    }
    return new (Function.prototype.bind.apply(RealDate, [null].concat(dateArguments)))();
  }
  FixedDate.prototype = RealDate.prototype;
  FixedDate.now = function fixedNow() { return fixedTime; };
  FixedDate.parse = RealDate.parse;
  FixedDate.UTC = RealDate.UTC;
  globalThis.Date = FixedDate;
  var seed = 1;
  Math.random = function seededRandom() {
    seed = (seed * 16807) % 2147483647;
    return (seed - 1) / 2147483646;
  };
  globalThis.__shieldReset = function resetSeed() { seed = 1; };
})(__SHIELD_FIXED_TIME__);
`;

function isPlainObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

// tools.js in a fresh context with a fixed clock. Returns { tools, reset } or { problem }.
export function loadDeterministicTools(toolsText, nowIso) {
  if (typeof toolsText !== "string") {
    return { problem: "there is no tools.js" };
  }
  const sandbox = { console: { log() {}, warn() {}, error() {} } };
  vm.createContext(sandbox);
  const prelude = DETERMINISM_PRELUDE.replace("__SHIELD_FIXED_TIME__", String(Date.parse(nowIso)));
  const capture = `\n;globalThis.__tools = typeof ${TOOLS_GLOBAL} === "undefined" ? null : ${TOOLS_GLOBAL};`;
  try {
    vm.runInContext(prelude, sandbox, { timeout: RUN_TIMEOUT_MS });
    vm.runInContext(toolsText + capture, sandbox, { timeout: RUN_TIMEOUT_MS });
  } catch (error) {
    return { problem: `tools.js does not run: ${error && error.message ? error.message : String(error)}` };
  }
  const tools = sandbox.__tools;
  if (!isPlainObject(tools) || !isPlainObject(tools.handlers)) {
    return { problem: `tools.js sets no ${TOOLS_GLOBAL} with handlers` };
  }
  return { tools, reset: sandbox.__shieldReset };
}

// Object keys sorted at every level, so two equal answers always print the same
export function stableText(value) {
  if (Array.isArray(value)) {
    const parts = value.map(stableText);
    return `[${parts.join(",")}]`;
  }
  if (isPlainObject(value)) {
    const names = Object.keys(value).sort();
    const parts = names.map(function pairText(name) {
      return `${JSON.stringify(name)}:${stableText(value[name])}`;
    });
    return `{${parts.join(",")}}`;
  }
  const text = JSON.stringify(value);
  return text === undefined ? "undefined" : text;
}

function throughJson(value) {
  const text = JSON.stringify(value);
  return text === undefined ? null : JSON.parse(text);
}

// One handler call, as text: its answer, or what it threw
export function answerText({ loaded, verb, input, records, nowIso }) {
  const handler = loaded.tools.handlers[verb];
  if (typeof handler !== "function") {
    return null;
  }
  loaded.reset();
  try {
    const reply = handler(throughJson(input), throughJson(records), nowIso);
    return stableText(throughJson(reply));
  } catch (error) {
    return `threw: ${error && error.message ? error.message : String(error)}`;
  }
}

function verbOf(toolName, sidekickId) {
  const prefix = `${sidekickId}.`;
  return toolName.startsWith(prefix) ? toolName.slice(prefix.length) : "";
}

function toolsOf(manifest) {
  const tools = manifest?.agent?.tools;
  return Array.isArray(tools) ? tools.filter(isPlainObject) : [];
}

function pageActionsOf(tool) {
  const actions = isPlainObject(tool._meta) ? tool._meta[PAGE_ACTIONS_KEY] : undefined;
  return Array.isArray(actions) ? actions : [];
}

function quoted(text) {
  return text.length > QUOTE_LIMIT ? `${text.slice(0, QUOTE_LIMIT)}…` : text;
}

// Every page control a tool names must be on the page: the new manifest's tools, and the old
// manifest's controls for every tool the request did not name.
function pageControlProblems({ beforeTools, afterTools, afterHtml, requestedTools, pageOffersAction }) {
  const problems = [];
  for (const tool of afterTools) {
    for (const action of pageActionsOf(tool)) {
      if (!pageOffersAction(afterHtml, action)) {
        problems.push(`${tool.name}: its page control "${action}" is not on the new page`);
      }
    }
  }
  for (const tool of beforeTools) {
    if (requestedTools.includes(tool.name)) {
      continue;
    }
    for (const action of pageActionsOf(tool)) {
      const alreadyListed = problems.some(function namesAction(problem) {
        return problem.includes(`"${action}"`);
      });
      if (!alreadyListed && !pageOffersAction(afterHtml, action)) {
        problems.push(`${tool.name}: its page control "${action}" was on the page and is gone`);
      }
    }
  }
  return problems;
}

// before/after: { manifest, toolsText, html }. records: the person's [{ key, value }].
// requestedTools: tool names the repair request names (their answers may change).
// pageOffersAction: the deploy gate's own test for a page control (backend/scripts/bundle-tools.mjs).
// Returns { problems, notes, changed: [tool names whose answers changed] }.
export function compareTools({ sidekickId, before, after, records, requestedTools = [], nowIso, pageOffersAction }) {
  const problems = [];
  const notes = [];
  const changed = [];
  const beforeTools = toolsOf(before.manifest);
  const afterTools = toolsOf(after.manifest);
  if (beforeTools.length === 0) {
    notes.push("the copy had no jess tools before the repair");
    return { problems, notes, changed };
  }
  const afterNames = afterTools.map(function nameOf(tool) {
    return tool.name;
  });
  for (const tool of beforeTools) {
    if (!afterNames.includes(tool.name)) {
      problems.push(`${tool.name} was removed; a feature is hidden by a setting, its tool stays and answers "turned off" (D1)`);
    }
  }
  problems.push(...pageControlProblems({ beforeTools, afterTools, afterHtml: after.html, requestedTools, pageOffersAction }));

  const oldLoaded = loadDeterministicTools(before.toolsText, nowIso);
  if (oldLoaded.problem) {
    notes.push(`the old tools.js could not be run (${oldLoaded.problem}); answers not compared`);
    return { problems, notes, changed };
  }
  const newLoaded = loadDeterministicTools(after.toolsText, nowIso);
  if (newLoaded.problem) {
    problems.push(`new ${newLoaded.problem}`);
    return { problems, notes, changed };
  }

  for (const tool of beforeTools) {
    const verb = verbOf(tool.name, sidekickId);
    if (typeof oldLoaded.tools.handlers[verb] !== "function" || !afterNames.includes(tool.name)) {
      continue;
    }
    if (typeof newLoaded.tools.handlers[verb] !== "function") {
      problems.push(`${tool.name}: the new tools.js has no handler "${verb}"`);
      continue;
    }
    const cases = sampleInputs({ tool, records, nowIso });
    for (const sample of cases) {
      const oldAnswer = answerText({ loaded: oldLoaded, verb, input: sample.input, records, nowIso });
      const newAnswer = answerText({ loaded: newLoaded, verb, input: sample.input, records, nowIso });
      if (oldAnswer === newAnswer) {
        continue;
      }
      changed.push(tool.name);
      if (requestedTools.includes(tool.name)) {
        notes.push(`${tool.name} answers differently (${sample.label}); the request names it`);
      } else {
        problems.push(`${tool.name} answers differently on the person's records (${sample.label}) and the request does not name it. Before: ${quoted(oldAnswer)} After: ${quoted(newAnswer)}`);
      }
      // One differing case per tool is enough to say so
      break;
    }
  }
  return { problems, notes, changed };
}
