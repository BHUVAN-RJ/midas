// The shield: core checks owned by Midas that run on every repair (founder D3, 2026-11-13;
// docs/briefs/repair-lanes.md W1). They live in the platform checkout (runner/core-checks/), are
// loaded from there by the runner and by the agent's check tool, and are never copied into the
// person's copy or the job folder, so no repair agent and no Sidekick guardian can change them.
//
//   page-opens        the new page opens in WebKit with the person's records; its first view and
//                     every view a tool's page control opens draw with no new error
//   tools             every tool answers as before on the person's records unless the request
//                     names it; no tool removed; every tool's page control still on the page
//   settings-engine   set_setting and settings:self are kept (D1)
//   records-fit       every record the person has fits the new schema
//   widget-record     every widget record the page wrote is still written
//   primitive-blocks  the primitive's block checks, where it defines any
//
// Preferences (colour, wording, position, show or hide) never become checks (D3).
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { checkPageOpens, checkWidgetRecords } from "./page-check.mjs";
import { ALL_STEP_KINDS, STEP_KIND_OPEN, STEP_KIND_VIEWS, STEP_KIND_WIDGET, openPage } from "./page-open.mjs";
import { checkPrimitiveBlocks } from "./primitive-blocks.mjs";
import { checkRecordsFit } from "./records-fit.mjs";
import { checkSettingsEngine } from "./settings-engine.mjs";
import { compareTools, loadDeterministicTools } from "./tools-compare.mjs";

// W5 put the settings engine in Reminders, Care, Water and To-Do (2026-11-13): a copy of one of
// them without it fails (settings-engine.mjs). It applies to every Sidekick whose base in this
// checkout has a settings catalogue; one without (Money today) is only held to "never lose it".
export const SETTINGS_ENGINE_IN_EVERY_SIDEKICK = true;

// Whether the base Sidekick in the platform checkout has a settings catalogue (manifest "settings")
export function baseHasSettingsCatalogue(checkoutRoot, sidekickId) {
  const manifestPath = join(checkoutRoot, "sidekicks", sidekickId, "manifest.json");
  if (!existsSync(manifestPath)) {
    return false;
  }
  try {
    const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
    return manifest !== null && typeof manifest === "object" && manifest.settings !== undefined;
  } catch {
    return false;
  }
}

export const CHECK_IDS = ["page-opens", "tools", "settings-engine", "records-fit", "widget-record", "primitive-blocks"];

// Publish first (founder, 2026-11-13; docs/briefs/repair-lanes.md W7). The shield runs in two
// parts. "fast" protects the person and runs before the pointer flips (about 1-2 s): the first
// view opens, every tool answers as before, the settings engine is kept, every record fits, the
// primitive's block checks pass. "slow" runs after the person already has the update: a tap on
// every page control a tool names, and the widget record (about 15-20 s for To-Do); when it fails
// the runner rolls the copy back at once. "all" is both, as one run (W1, before the split).
export const PART_FAST = "fast";
export const PART_SLOW = "slow";
export const PART_ALL = "all";
export const PART_CHECK_IDS = {
  [PART_FAST]: ["page-opens", "tools", "settings-engine", "records-fit", "primitive-blocks"],
  [PART_SLOW]: ["page-views", "widget-record"],
  [PART_ALL]: CHECK_IDS,
};
// How many WebKit programs share one page's taps in the slow part (each opens its own WKWebView)
export const SLOW_PAGE_PROGRAMS = 3;

const PAGE_ACTIONS_KEY = "midas/page-actions";

async function loadBundleTools(checkoutRoot) {
  const bundleToolsPath = join(checkoutRoot, "backend", "scripts", "bundle-tools.mjs");
  return import(pathToFileURL(bundleToolsPath).href);
}

function parsedManifest(manifestText) {
  try {
    return JSON.parse(manifestText);
  } catch {
    return null;
  }
}

// { html, manifestText, toolsText } -> the same plus manifest and loadedTools
function preparedCopy(copy, nowIso) {
  return {
    html: copy.html,
    manifestText: copy.manifestText,
    toolsText: copy.toolsText ?? null,
    manifest: parsedManifest(copy.manifestText),
    loadedTools: loadDeterministicTools(copy.toolsText ?? null, nowIso),
  };
}

// The page controls to tap, one view each: every control a tool names, old manifest or new
export function viewActions(beforeManifest, afterManifest) {
  const actions = [];
  for (const manifest of [beforeManifest, afterManifest]) {
    const tools = Array.isArray(manifest?.agent?.tools) ? manifest.agent.tools : [];
    for (const tool of tools) {
      const named = tool?._meta?.[PAGE_ACTIONS_KEY];
      for (const action of Array.isArray(named) ? named : []) {
        if (typeof action === "string" && !actions.includes(action)) {
          actions.push(action);
        }
      }
    }
  }
  return actions;
}

function errorText(error) {
  return error && error.message ? error.message : String(error);
}

// A check that throws fails, with what it threw: a broken check never reads as a pass
async function runCheck(id, checkFunction) {
  try {
    const outcome = await checkFunction();
    return { id, ok: outcome.problems.length === 0, problems: outcome.problems, notes: outcome.notes ?? [] };
  } catch (error) {
    return { id, ok: false, problems: [`the check could not run: ${errorText(error)}`], notes: [] };
  }
}

// The runs one page needs for a part, as [{ actions, kinds }]: one WebKit program each
export function pageRunsFor(part, actions, programs = SLOW_PAGE_PROGRAMS) {
  if (part === PART_FAST) {
    return [{ actions: [], kinds: [STEP_KIND_OPEN] }];
  }
  if (part === PART_ALL) {
    return [{ actions, kinds: ALL_STEP_KINDS }];
  }
  // The slow part: the widget step with the first share of the taps, the other shares alone
  const runCount = Math.max(1, Math.min(programs, actions.length));
  const shareSize = Math.ceil(actions.length / runCount);
  const runs = [];
  for (let index = 0; index < runCount; index += 1) {
    const share = actions.slice(index * shareSize, (index + 1) * shareSize);
    const kinds = index === 0 ? [STEP_KIND_WIDGET, STEP_KIND_VIEWS] : [STEP_KIND_VIEWS];
    runs.push({ actions: share, kinds });
  }
  return runs;
}

async function openOnePage({ shared, copy, runs, openPageImplementation }) {
  const runResults = await Promise.all(runs.map(function openOneRun(run) {
    return openPageImplementation({ ...shared, html: copy.html, manifest: copy.manifest, actions: run.actions, kinds: run.kinds });
  }));
  return runResults.flat();
}

// The old and the new page, opened at the same time (each in its own WebKit program)
async function openBothPages({ checkoutRoot, sidekickId, before, after, records, openPageImplementation, part = PART_ALL }) {
  const actions = viewActions(before.manifest, after.manifest);
  const runs = pageRunsFor(part, actions);
  const shared = { checkoutRoot, sidekickId, records };
  const [beforeResults, afterResults] = await Promise.all([
    openOnePage({ shared, copy: before, runs, openPageImplementation }),
    openOnePage({ shared, copy: after, runs, openPageImplementation }),
  ]);
  return { beforeResults, afterResults };
}

// before/after: { html, manifestText, toolsText } of the copy as the job started and as the agent
// left it. records: the person's records [{ key, value }]. requestedTools: tool names the repair
// request names. part: "fast", "slow" or "all" (PART_CHECK_IDS). Returns { ok, part, checks: [{ id,
// ok, problems, notes }], changedTools }.
export async function runShield({
  checkoutRoot,
  sidekickId,
  before,
  after,
  records,
  requestedTools = [],
  now = new Date(),
  openPageImplementation = openPage,
  settingsEngineEverywhere = SETTINGS_ENGINE_IN_EVERY_SIDEKICK,
  part = PART_ALL,
}) {
  if (!Object.hasOwn(PART_CHECK_IDS, part)) {
    throw new Error(`unknown shield part "${part}"`);
  }
  const nowIso = now.toISOString();
  const beforeCopy = preparedCopy(before, nowIso);
  const afterCopy = preparedCopy(after, nowIso);
  if (afterCopy.manifest === null) {
    const unreadable = { id: "records-fit", ok: false, problems: ["the new manifest.json is not JSON"], notes: [] };
    return { ok: false, part, checks: [unreadable], changedTools: [] };
  }
  const bundleTools = await loadBundleTools(checkoutRoot);
  const wanted = PART_CHECK_IDS[part];
  let changedTools = [];

  let pages = null;
  let pageFailure = null;
  try {
    pages = await openBothPages({ checkoutRoot, sidekickId, before: beforeCopy, after: afterCopy, records, openPageImplementation, part });
  } catch (error) {
    pageFailure = `WebKit could not open the page: ${errorText(error)}`;
  }
  function pageResultsOrThrow() {
    if (pageFailure !== null) {
      throw new Error(pageFailure);
    }
    return pages;
  }

  const checkFunctions = {
    "page-opens": function pageOpensCheck() {
      return checkPageOpens(pageResultsOrThrow());
    },
    // The slow part's page check: the widget step and every tapped view
    "page-views": function pageViewsCheck() {
      return checkPageOpens(pageResultsOrThrow());
    },
    tools: function toolsCheck() {
      const compared = compareTools({ sidekickId, before: beforeCopy, after: afterCopy, records, requestedTools, nowIso, pageOffersAction: bundleTools.pageOffersAction });
      changedTools = [...new Set(compared.changed)];
      return compared;
    },
    "settings-engine": function settingsCheck() {
      const everyEngine = settingsEngineEverywhere && baseHasSettingsCatalogue(checkoutRoot, sidekickId);
      return checkSettingsEngine({ sidekickId, before: beforeCopy, after: afterCopy, everyEngine });
    },
    "records-fit": function recordsCheck() {
      return checkRecordsFit({ checkoutRoot, records, manifestAfter: afterCopy.manifest });
    },
    "widget-record": function widgetCheck() {
      return checkWidgetRecords(pageResultsOrThrow());
    },
    "primitive-blocks": function blocksCheck() {
      const copy = { sidekickId, html: afterCopy.html, manifest: afterCopy.manifest, toolsText: afterCopy.toolsText, records };
      return checkPrimitiveBlocks({ checkoutRoot, copy });
    },
  };

  const checks = [];
  for (const checkId of wanted) {
    checks.push(await runCheck(checkId, checkFunctions[checkId]));
  }

  const failed = checks.filter(function didFail(check) {
    return !check.ok;
  });
  return { ok: failed.length === 0, part, checks, changedTools };
}

// The shield's problems as one list of lines, "<check>: <problem>"
export function shieldProblems(result) {
  const lines = [];
  for (const check of result.checks) {
    for (const problem of check.problems) {
      lines.push(`shield ${check.id}: ${problem}`);
    }
  }
  return lines;
}

// A readable report for the log folder and the agent: one line per check, then its details
export function shieldReport(result) {
  const lines = [];
  for (const check of result.checks) {
    lines.push(`${check.ok ? "✓" : "✕"} ${check.id}`);
    for (const problem of check.problems) {
      lines.push(`    ✕ ${problem}`);
    }
    for (const note of check.notes) {
      lines.push(`    · ${note}`);
    }
  }
  if (result.changedTools.length > 0) {
    lines.push(`tools whose answers changed: ${result.changedTools.join(", ")}`);
  }
  return lines.join("\n");
}
