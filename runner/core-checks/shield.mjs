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
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { checkPageOpens, checkWidgetRecords } from "./page-check.mjs";
import { openPage } from "./page-open.mjs";
import { checkPrimitiveBlocks } from "./primitive-blocks.mjs";
import { checkRecordsFit } from "./records-fit.mjs";
import { checkSettingsEngine } from "./settings-engine.mjs";
import { compareTools, loadDeterministicTools } from "./tools-compare.mjs";

// False until W5 puts the settings engine in every Sidekick; then true (settings-engine.mjs).
export const SETTINGS_ENGINE_IN_EVERY_SIDEKICK = false;

export const CHECK_IDS = ["page-opens", "tools", "settings-engine", "records-fit", "widget-record", "primitive-blocks"];

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

async function openBothPages({ checkoutRoot, sidekickId, before, after, records, openPageImplementation }) {
  const actions = viewActions(before.manifest, after.manifest);
  const shared = { checkoutRoot, sidekickId, records, actions };
  const beforeResults = await openPageImplementation({ ...shared, html: before.html, manifest: before.manifest });
  const afterResults = await openPageImplementation({ ...shared, html: after.html, manifest: after.manifest });
  return { beforeResults, afterResults };
}

// before/after: { html, manifestText, toolsText } of the copy as the job started and as the agent
// left it. records: the person's records [{ key, value }]. requestedTools: tool names the repair
// request names. Returns { ok, checks: [{ id, ok, problems, notes }], changedTools }.
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
}) {
  const nowIso = now.toISOString();
  const beforeCopy = preparedCopy(before, nowIso);
  const afterCopy = preparedCopy(after, nowIso);
  if (afterCopy.manifest === null) {
    const unreadable = { id: "records-fit", ok: false, problems: ["the new manifest.json is not JSON"], notes: [] };
    return { ok: false, checks: [unreadable], changedTools: [] };
  }
  const bundleTools = await loadBundleTools(checkoutRoot);
  let changedTools = [];

  let pages = null;
  let pageFailure = null;
  try {
    pages = await openBothPages({ checkoutRoot, sidekickId, before: beforeCopy, after: afterCopy, records, openPageImplementation });
  } catch (error) {
    pageFailure = `WebKit could not open the page: ${errorText(error)}`;
  }

  const checks = [];
  checks.push(await runCheck("page-opens", function pageOpensCheck() {
    if (pageFailure !== null) {
      throw new Error(pageFailure);
    }
    return checkPageOpens(pages);
  }));
  checks.push(await runCheck("tools", function toolsCheck() {
    const compared = compareTools({ sidekickId, before: beforeCopy, after: afterCopy, records, requestedTools, nowIso, pageOffersAction: bundleTools.pageOffersAction });
    changedTools = [...new Set(compared.changed)];
    return compared;
  }));
  checks.push(await runCheck("settings-engine", function settingsCheck() {
    return checkSettingsEngine({ sidekickId, before: beforeCopy, after: afterCopy, everyEngine: settingsEngineEverywhere });
  }));
  checks.push(await runCheck("records-fit", function recordsCheck() {
    return checkRecordsFit({ checkoutRoot, records, manifestAfter: afterCopy.manifest });
  }));
  checks.push(await runCheck("widget-record", function widgetCheck() {
    if (pageFailure !== null) {
      throw new Error(pageFailure);
    }
    return checkWidgetRecords(pages);
  }));
  checks.push(await runCheck("primitive-blocks", function blocksCheck() {
    const copy = { sidekickId, html: afterCopy.html, manifest: afterCopy.manifest, toolsText: afterCopy.toolsText, records };
    return checkPrimitiveBlocks({ checkoutRoot, copy });
  }));

  const failed = checks.filter(function didFail(check) {
    return !check.ok;
  });
  return { ok: failed.length === 0, checks, changedTools };
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
