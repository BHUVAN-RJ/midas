// Usage, from backend/:
//   node scripts/bring-settings-engine.mjs --env staging --out <dir> [--sidekick <id>]            (dry run)
//   node scripts/bring-settings-engine.mjs --env staging --out <dir> [--sidekick <id>] --publish
//
// Brings the settings engine (repair lanes W5, founder D1 2026-11-13) to every person's own
// repaired copy. A base deploy moves only the base and the copies that still follow it; a repaired
// copy (its own version pointer, e.g. the founder's To-Do with Make It Yours removed by repair
// 42396937) stays on its own version and would never get the engine. For each such copy this:
//
//   1. reads the copy's index.html, manifest.json, tools.js and tests, and the person's records
//      (read-only, as plan-user-copies.mjs does);
//   2. adds the engine while keeping the person's changes (bringEngineToCopy below): the engine
//      block and the base's catalogue pasted after the store helper with the generic wiring,
//      the same block and attachTools in tools.js, the catalogue keys added to the "settings:"
//      type, and set_setting when the copy has lost it or never had it. Only catalogue entries
//      the copy can still honour are kept: a part drawn by a selector whose classes and ids are
//      still in the page, a value the page reads only when the page still names it. Everything
//      else of the copy stays exactly as it was;
//   3. runs the deploy gate and the shield (runner/core-checks, from this checkout) on the
//      upgraded copy against the copy as it is, with the person's own records;
//   4. writes every upgraded copy to <out>/<sidekick>/<user>/ (the deploy-sidekick.mjs --dir
//      layout, tests included) and prints what passed, what failed and why.
//
// Dry run (the default) writes nothing remotely. With --publish, each copy that passed is
// published as that person's next version (deploy-sidekick.mjs --user <id> --dir <folder>); a
// copy that failed anything is listed and left untouched. The lead runs this at the deploy step,
// staging first.
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { TOOLS_FILE, pointerKeyFor, storePrefix, testFileKey, testsIndexKey } from "./bundle-tools.mjs";
import { rowsFromWranglerJson, sqlLiteral } from "./db-tools.mjs";
import { environmentFromArgs, positionalArgs } from "./environments.mjs";
import {
  MidasSettings,
  findEngineBlock,
  hasSettingTool,
  manifestWithSettings,
  pageWithEngine,
  setSettingTool,
  textOutsideEngine,
  toolsWithEngine,
} from "./settings-engine-tools.mjs";
import { captureWrangler } from "./wrangler.mjs";

export const REPO_ROOT = resolve(fileURLToPath(new URL("../..", import.meta.url)));
const USAGE = "usage: node scripts/bring-settings-engine.mjs --env staging --out <dir> [--sidekick <id>] [--publish]";

// STAGING ONLY (founder, 2026-11-14; docs/briefs/repair-lanes.md): no live upgrade of people's
// copies until the founder says live. Live is refused outright, dry run included; lifting this is
// the founder's call, in this function.
export const LIVE_REFUSAL = "refused: --env live. Staging only until the founder says live (founder, 2026-11-14).";
export function refusalForEnvironment(environment) {
  if (environment !== null && environment.name === "live") {
    return LIVE_REFUSAL;
  }
  return null;
}
// Class and id names in a selector: ".streak-chip svg, .first .mark" -> streak-chip, first, mark
const SELECTOR_NAME_PATTERN = /[.#]([A-Za-z_][A-Za-z0-9_-]*)/g;

function stop(message) {
  console.error(message);
  process.exit(1);
}

function takeOption(args, name) {
  const flagIndex = args.indexOf(`--${name}`);
  if (flagIndex === -1) {
    return null;
  }
  const value = args[flagIndex + 1];
  args.splice(flagIndex, 2);
  return value ?? "";
}

function takeFlag(args, name) {
  const flagIndex = args.indexOf(`--${name}`);
  if (flagIndex === -1) {
    return false;
  }
  args.splice(flagIndex, 1);
  return true;
}

/* ---------- Which catalogue entries a copy can honour ---------- */

function selectorNames(selector) {
  const names = [];
  for (const match of selector.matchAll(SELECTOR_NAME_PATTERN)) {
    names.push(match[1]);
  }
  return names;
}

// A part drawn by a selector is kept when every class and id it names is still in the page (the
// repair may have removed the part). A value the page reads (no selector) is kept only when the
// page still names its key: a copy made before the engine has no date-format code, for example.
export function entryFitsCopy(entry, pageText) {
  if (typeof entry.selector === "string") {
    const names = selectorNames(entry.selector);
    return names.every(function nameInPage(name) {
      return pageText.includes(name);
    });
  }
  if (entry.key.includes(".")) {
    return false;
  }
  const keyPattern = new RegExp(`\\b${entry.key}\\b`);
  return keyPattern.test(pageText);
}

export function catalogueForCopy(baseCatalogue, html) {
  const pageText = textOutsideEngine(html);
  const kept = [];
  const dropped = [];
  for (const entry of baseCatalogue.entries) {
    if (entryFitsCopy(entry, pageText)) {
      kept.push(entry);
    } else {
      dropped.push(entry.key);
    }
  }
  const catalogue = { entries: kept };
  if (baseCatalogue.alsoSet !== undefined) {
    catalogue.alsoSet = baseCatalogue.alsoSet;
  }
  return { catalogue, dropped };
}

/* ---------- One copy ---------- */

function hasOwnSetSettingHandler(toolsText) {
  return /\bset_setting\s*:/.test(textOutsideEngine(toolsText));
}

// copy: { html, manifestText, toolsText|null }. baseManifest: the base's manifest (with
// "settings"). Returns { status: "current" | "upgraded" | "cannot", upgraded?, dropped, problem? }.
// Pure: no I/O.
export function bringEngineToCopy({ sidekickId, copy, baseManifest }) {
  const baseCatalogue = baseManifest?.settings;
  if (MidasSettings.catalogueProblems(baseCatalogue).length > 0) {
    return { status: "cannot", problem: "the base has no settings catalogue", dropped: [] };
  }
  let manifest;
  try {
    manifest = JSON.parse(copy.manifestText);
  } catch {
    return { status: "cannot", problem: "manifest.json is not JSON", dropped: [] };
  }
  if (copy.toolsText === null || copy.toolsText === undefined) {
    return { status: "cannot", problem: "the copy has no tools.js", dropped: [] };
  }
  const hasEngine = findEngineBlock(copy.html) !== null && hasSettingTool(manifest, sidekickId) && MidasSettings.catalogueProblems(manifest.settings).length === 0;
  if (hasEngine) {
    return { status: "current", dropped: [] };
  }
  const { catalogue, dropped } = catalogueForCopy(baseCatalogue, copy.html);
  if (catalogue.entries.length === 0) {
    return { status: "cannot", problem: "no part of the catalogue is still on the page", dropped };
  }
  const page = pageWithEngine(copy.html, catalogue);
  if (page.status === "no-store-helper") {
    return { status: "cannot", problem: "the page has no store helper to put the engine after", dropped };
  }
  // A copy that still has its own set_setting (To-Do's Make It Yours) keeps it for the values the
  // page reads; the engine takes the parts it draws
  const ownKeys = [];
  if (hasOwnSetSettingHandler(copy.toolsText)) {
    for (const entry of catalogue.entries) {
      if (typeof entry.selector !== "string" && !entry.key.includes(".")) {
        ownKeys.push(entry.key);
      }
    }
  }
  const toolsOptions = ownKeys.length > 0 ? { ownKeys } : {};
  const tools = toolsWithEngine(copy.toolsText, sidekickId, catalogue, toolsOptions);
  if (tools.status === "no-export") {
    return { status: "cannot", problem: "tools.js does not end with the MidasSidekickTools export", dropped };
  }
  const nextManifest = manifestWithSettings(manifest, catalogue);
  if (!hasSettingTool(nextManifest, sidekickId)) {
    nextManifest.agent = nextManifest.agent ?? { tools: [] };
    nextManifest.agent.tools.push(setSettingTool(sidekickId, catalogue));
  }
  const upgraded = { html: page.html, manifestText: `${JSON.stringify(nextManifest, null, 2)}\n`, toolsText: tools.toolsText };
  return { status: "upgraded", upgraded, dropped };
}

/* ---------- Checks: the deploy gate and the shield ---------- */

// Returns { ok, problems, report }. A check that cannot run fails.
export async function checkUpgradedCopy({ checkoutRoot = REPO_ROOT, sidekickId, before, after, records, openPageImplementation }) {
  const checkModule = await import(pathToFileURL(join(checkoutRoot, "runner", "lib", "check.mjs")).href);
  const gate = await checkModule.gateProblems({ checkoutRoot, sidekickId, html: after.html, manifestText: after.manifestText, toolsText: after.toolsText });
  if (gate.length > 0) {
    return { ok: false, problems: gate, report: "deploy gate refused" };
  }
  const shield = await checkModule.loadShield(checkoutRoot);
  const options = { checkoutRoot, sidekickId, before, after, records, requestedTools: [`${sidekickId}.set_setting`] };
  if (openPageImplementation !== undefined) {
    options.openPageImplementation = openPageImplementation;
  }
  const result = await shield.runShield(options);
  return { ok: result.ok, problems: shield.shieldProblems(result), report: shield.shieldReport(result) };
}

/* ---------- Reading the remote (read-only) ---------- */

function makeReaders(environment) {
  function readRemoteText(key) {
    try {
      return captureWrangler(["r2", "object", "get", `${environment.bucket}/${key}`, "--pipe", "--remote"]);
    } catch {
      return null;
    }
  }
  function readRemoteJson(key) {
    const text = readRemoteText(key);
    return text === null ? null : JSON.parse(text);
  }
  function queryRemote(sql) {
    const output = captureWrangler(["d1", "execute", environment.database, "--remote", "--json", "--command", sql, ...environment.wranglerEnvArgs]);
    return rowsFromWranglerJson(output);
  }
  return { readRemoteText, readRemoteJson, queryRemote };
}

function readCopyTests(readers, prefix, version) {
  const indexText = readers.readRemoteText(testsIndexKey(prefix, version));
  if (indexText === null) {
    return [];
  }
  const tests = [];
  for (const fileName of JSON.parse(indexText).files) {
    const body = readers.readRemoteText(testFileKey(prefix, version, fileName));
    if (body !== null) {
      tests.push({ name: fileName, body });
    }
  }
  return tests;
}

function readUserRecords(readers, sidekickId, userId) {
  const sql = [
    "SELECT key, value FROM (SELECT key, value, deleted, MAX(seq) AS seq FROM ops",
    `WHERE user_id = ${sqlLiteral(userId)} AND sidekick_id = ${sqlLiteral(sidekickId)} GROUP BY key)`,
    "WHERE deleted = 0 ORDER BY key",
  ].join(" ");
  const records = [];
  for (const row of readers.queryRemote(sql)) {
    records.push({ key: row.key, value: JSON.parse(row.value) });
  }
  return records;
}

// The copy folder deploy-sidekick.mjs --dir uploads: page files at the top, tests/ beside them
export function writeCopyFolder(folder, upgraded, tests) {
  mkdirSync(join(folder, "tests"), { recursive: true });
  writeFileSync(join(folder, "index.html"), upgraded.html);
  writeFileSync(join(folder, "manifest.json"), upgraded.manifestText);
  writeFileSync(join(folder, TOOLS_FILE), upgraded.toolsText);
  for (const test of tests) {
    writeFileSync(join(folder, "tests", test.name), test.body);
  }
}

// Every Sidekick whose manifest carries a settings catalogue: since the founder's 2026-11-22 decision
// (settings engine core in every Sidekick, D1 2026-11-13) that is Money, Reminder Test and Sounds
// too, next to Reminders, Care, Water and To-Do. With no --sidekick the script walks all of them;
// --sidekick names one.
export function sidekicksWithCatalogue(sidekicksFolder = join(REPO_ROOT, "sidekicks")) {
  const ids = [];
  for (const entry of readdirSync(sidekicksFolder, { withFileTypes: true })) {
    const manifestPath = join(sidekicksFolder, entry.name, "manifest.json");
    if (entry.isDirectory() && existsSync(manifestPath)) {
      const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
      if (manifest.settings !== undefined) {
        ids.push(entry.name);
      }
    }
  }
  ids.sort();
  return ids;
}

async function bringSidekick({ environment, readers, sidekickId, outRoot, publish }) {
  const basePointer = readers.readRemoteJson(pointerKeyFor(sidekickId));
  if (basePointer === null) {
    console.log(`${sidekickId}: no base on ${environment.name}; skipped`);
    return { passed: 0, failed: 0 };
  }
  // The base as deployed must already carry the catalogue: deploy the base first
  const baseManifest = readers.readRemoteJson(`${storePrefix(sidekickId)}/${basePointer.version}/manifest.json`);
  if (baseManifest?.settings === undefined) {
    console.log(`${sidekickId}: base ${basePointer.version} on ${environment.name} has no settings catalogue; deploy the base first`);
    return { passed: 0, failed: 0 };
  }
  const users = readers.queryRemote(`SELECT user_id FROM assignments WHERE sidekick_id = ${sqlLiteral(sidekickId)} ORDER BY user_id`);
  let passed = 0;
  let failed = 0;
  for (const row of users) {
    const userId = row.user_id;
    const pointer = readers.readRemoteJson(pointerKeyFor(sidekickId, userId));
    if (pointer === null || pointer.version === basePointer.version) {
      continue;
    }
    const prefix = storePrefix(sidekickId, userId);
    const copy = {
      html: readers.readRemoteText(`${prefix}/${pointer.version}/index.html`) ?? "",
      manifestText: readers.readRemoteText(`${prefix}/${pointer.version}/manifest.json`) ?? "{}",
      toolsText: pointer.tools ? readers.readRemoteText(`${prefix}/${pointer.version}/${TOOLS_FILE}`) : null,
    };
    const brought = bringEngineToCopy({ sidekickId, copy, baseManifest });
    const label = `  ${userId} (copy ${pointer.version})`;
    if (brought.status === "current") {
      console.log(`${label}: has the engine already`);
      continue;
    }
    if (brought.status === "cannot") {
      console.log(`${label}: FAILED, left untouched: ${brought.problem}`);
      failed += 1;
      continue;
    }
    const records = readUserRecords(readers, sidekickId, userId);
    const check = await checkUpgradedCopy({ sidekickId, before: copy, after: brought.upgraded, records });
    const droppedText = brought.dropped.length === 0 ? "" : ` (not on this copy: ${brought.dropped.join(", ")})`;
    const folder = join(outRoot, sidekickId, userId);
    writeCopyFolder(folder, brought.upgraded, readCopyTests(readers, prefix, pointer.version));
    if (!check.ok) {
      console.log(`${label}: FAILED, left untouched: ${check.problems.join("; ")}`);
      console.log(`    upgraded copy for a look: ${folder}`);
      failed += 1;
      continue;
    }
    passed += 1;
    console.log(`${label}: passed gate and shield${droppedText}`);
    if (!publish) {
      console.log(`    dry run; to publish: cd ${join(REPO_ROOT, "backend")} && node scripts/deploy-sidekick.mjs ${sidekickId} --env ${environment.name} --user ${userId} --dir ${folder}`);
      continue;
    }
    const deploy = spawnSync("node", ["scripts/deploy-sidekick.mjs", sidekickId, "--env", environment.name, "--user", userId, "--dir", folder], { cwd: join(REPO_ROOT, "backend"), stdio: "inherit" });
    console.log(deploy.status === 0 ? "    published as this person's next version" : "    publish FAILED; the person stays on their copy");
  }
  return { passed, failed };
}

const isRunDirectly = process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href;
if (isRunDirectly) {
  const commandArgs = process.argv.slice(2);
  const environment = environmentFromArgs(commandArgs);
  const remainingArgs = positionalArgs(commandArgs);
  const onlySidekick = takeOption(remainingArgs, "sidekick");
  const outOption = takeOption(remainingArgs, "out");
  const publish = takeFlag(remainingArgs, "publish");
  if (environment === null || outOption === null || outOption === "" || remainingArgs.length > 0) {
    stop(USAGE);
  }
  const refusal = refusalForEnvironment(environment);
  if (refusal !== null) {
    stop(refusal);
  }
  const outRoot = resolve(outOption);
  if (existsSync(outRoot) && readdirSync(outRoot).length > 0) {
    stop(`${outRoot} is not empty; pick a new --out`);
  }
  const readers = makeReaders(environment);
  const catalogued = sidekicksWithCatalogue();
  if (onlySidekick !== null && !catalogued.includes(onlySidekick)) {
    stop(`${onlySidekick} has no settings catalogue in this checkout; Sidekicks with one: ${catalogued.join(", ")}`);
  }
  const sidekickIds = onlySidekick === null ? catalogued : [onlySidekick];
  console.log(`settings engine for repaired copies on ${environment.name} (${publish ? "PUBLISH" : "dry run: nothing is written remotely"})`);
  let passedTotal = 0;
  let failedTotal = 0;
  for (const sidekickId of sidekickIds) {
    const counts = await bringSidekick({ environment, readers, sidekickId, outRoot, publish });
    passedTotal += counts.passed;
    failedTotal += counts.failed;
  }
  console.log("");
  console.log(`${passedTotal} copy(ies) passed, ${failedTotal} failed and left untouched.`);
}
