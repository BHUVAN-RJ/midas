// Usage, from backend/:
//   node scripts/plan-user-copies.mjs --env staging|live [--sidekick <id>] [--out <dir>]
// Lists every user copy of every Sidekick in the repo (or one) on that environment and says what
// each needs to be on today's data rules (CONCERNS 8, founder 2026-10-19): follows the base,
// repaired and fine, repaired with a mechanical gap (an older store helper, a manifest without
// types), or repaired with retired shapes (needs its repair carried onto today's base). Then it
// prints the exact commands, including the records migration's own dry run.
// READ-ONLY on the remote: it reads D1 assignments and R2 copies and writes nothing there. With
// --out it writes each mechanically upgraded copy (index.html, manifest.json, tests/) into
// <dir>/<sidekick>/<user>/ on this Mac, ready for the printed deploy command.
import { existsSync, mkdirSync, readdirSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { pointerKeyFor, storePrefix, testFileKey, testsIndexKey } from "./bundle-tools.mjs";
import { rowsFromWranglerJson, sqlLiteral } from "./db-tools.mjs";
import { environmentFromArgs, positionalArgs } from "./environments.mjs";
import { currentStoreHelper } from "./store-helper.mjs";
import { planUserCopy } from "./user-copy-plan.mjs";
import { captureWrangler } from "./wrangler.mjs";

const USAGE = "usage: node scripts/plan-user-copies.mjs --env staging|live [--sidekick <id>] [--out <dir>]";

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

function repoSidekickIds() {
  const sidekicksFolder = new URL("../../sidekicks/", import.meta.url);
  const entries = readdirSync(sidekicksFolder, { withFileTypes: true });
  const ids = [];
  for (const entry of entries) {
    if (entry.isDirectory()) {
      ids.push(entry.name);
    }
  }
  ids.sort();
  return ids;
}

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

// The copy's stored tests (and log), as [{ name, body }]; empty when it has none.
function readCopyTests(readers, prefix, version) {
  const indexText = readers.readRemoteText(testsIndexKey(prefix, version));
  if (indexText === null) {
    return [];
  }
  const tests = [];
  for (const fileName of JSON.parse(indexText).files) {
    const body = readers.readRemoteText(testFileKey(prefix, version, fileName));
    if (body === null) {
      stop(`${prefix} ${version} is missing test file ${fileName}`);
    }
    tests.push({ name: fileName, body });
  }
  return tests;
}

function writeUpgradedFolder(outRoot, sidekickId, userId, upgraded, tests) {
  const folder = join(outRoot, sidekickId, userId);
  if (existsSync(folder)) {
    stop(`${folder} already exists; remove it or pick another --out`);
  }
  mkdirSync(join(folder, "tests"), { recursive: true });
  writeFileSync(join(folder, "index.html"), upgraded.html);
  writeFileSync(join(folder, "manifest.json"), upgraded.manifestText);
  for (const test of tests) {
    writeFileSync(join(folder, "tests", test.name), test.body);
  }
  return folder;
}

function planSidekick({ environment, readers, sidekickId, helperText, outRoot }) {
  const basePrefix = storePrefix(sidekickId);
  const basePointer = readers.readRemoteJson(pointerKeyFor(sidekickId));
  if (basePointer === null) {
    console.log(`${sidekickId}: no base on ${environment.name}; skipped`);
    return [];
  }
  const baseManifest = readers.readRemoteJson(`${basePrefix}/${basePointer.version}/manifest.json`);
  const assignmentRows = readers.queryRemote(`SELECT user_id FROM assignments WHERE sidekick_id = ${sqlLiteral(sidekickId)} ORDER BY user_id`);
  console.log(`${sidekickId}: base ${basePointer.version}, ${assignmentRows.length} assigned user(s)`);

  const baseContentHashes = {};
  const plans = [];
  for (const row of assignmentRows) {
    const userId = row.user_id;
    const prefix = storePrefix(sidekickId, userId);
    const pointer = readers.readRemoteJson(pointerKeyFor(sidekickId, userId));
    const copy = { userId, pointer, html: "", manifestText: "{}" };
    let tests = [];
    if (pointer !== null) {
      copy.html = readers.readRemoteText(`${prefix}/${pointer.version}/index.html`) ?? "";
      copy.manifestText = readers.readRemoteText(`${prefix}/${pointer.version}/manifest.json`) ?? "{}";
      tests = readCopyTests(readers, prefix, pointer.version);
      const baseVersion = pointer.baseVersion;
      if (baseVersion && !(baseVersion in baseContentHashes)) {
        const record = readers.readRemoteJson(`${basePrefix}/${baseVersion}/version.json`);
        if (record?.contentHash) {
          baseContentHashes[baseVersion] = record.contentHash;
        }
      }
    }
    const plan = planUserCopy({ sidekickId, envName: environment.name, copy, base: { pointer: basePointer, manifest: baseManifest }, baseContentHashes, helperText });
    const versionText = pointer === null ? "no copy" : `copy ${pointer.version} (from base ${pointer.baseVersion ?? "unknown"})`;
    const gapsText = plan.gaps.length === 0 ? "no gaps" : plan.gaps.join(", ");
    console.log(`  ${userId}: ${plan.state}, ${versionText}, ${gapsText}`);
    if (plan.upgraded !== null && outRoot !== null) {
      const folder = writeUpgradedFolder(outRoot, sidekickId, userId, plan.upgraded, tests);
      console.log(`    upgraded copy written to ${folder}`);
    }
    for (const action of plan.actions) {
      const shown = outRoot === null ? action : action.replace("<out>", outRoot);
      console.log(`    ${shown}`);
    }
    plans.push(plan);
  }
  return plans;
}

const isRunDirectly = import.meta.url === pathToFileURL(process.argv[1]).href;
if (isRunDirectly) {
  const commandArgs = process.argv.slice(2);
  const environment = environmentFromArgs(commandArgs);
  const remainingArgs = positionalArgs(commandArgs);
  const onlySidekick = takeOption(remainingArgs, "sidekick");
  const outOption = takeOption(remainingArgs, "out");
  if (environment === null || remainingArgs.length > 0) {
    stop(USAGE);
  }
  const sidekickIds = onlySidekick === null ? repoSidekickIds() : [onlySidekick];
  const readers = makeReaders(environment);
  const helperText = currentStoreHelper();
  const outRoot = outOption === null ? null : resolve(outOption);

  console.log(`user copies on ${environment.name} (read-only; nothing is written remotely)`);
  let actionCount = 0;
  for (const sidekickId of sidekickIds) {
    const plans = planSidekick({ environment, readers, sidekickId, helperText, outRoot });
    for (const plan of plans) {
      actionCount += plan.actions.length;
    }
  }
  console.log("");
  console.log(`${actionCount} copy action(s) above. Records: node scripts/migrate-records.mjs --env ${environment.name} --dry-run`);
}
