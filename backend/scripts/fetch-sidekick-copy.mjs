// Usage, from backend/:
//   node scripts/fetch-sidekick-copy.mjs <sidekick-id> --env staging|live --user <user-id> --out <dir>
// Downloads one user's current copy of a Sidekick into <dir>: index.html, manifest.json, tools.js (when it has one),
// version.json and tests/ (the copy's test files, its TEST_CHANGES.md and tests/index.json).
// This is what the repair runner starts a job from (founder, 2026-10-13: tests move every copy
// forward). A user with no copy yet gets the base's current version, and the output says so.
// Read-only: nothing is written to R2.
import { mkdirSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { TESTS_FOLDER, TOOLS_FILE, USER_ID_PATTERN, pointerKeyFor, storePrefix, testFileKey, testsIndexKey } from "./bundle-tools.mjs";
import { environmentFromArgs, positionalArgs } from "./environments.mjs";
import { captureWrangler, captureWranglerAsync, PARALLEL_WRANGLER_CALLS, runWithLimit } from "./wrangler.mjs";

const USAGE = "usage: node scripts/fetch-sidekick-copy.mjs <sidekick-id> --env staging|live --user <user-id> --out <dir>";

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

const commandArgs = process.argv.slice(2);
const environment = environmentFromArgs(commandArgs);
const remainingArgs = positionalArgs(commandArgs);
const userId = takeOption(remainingArgs, "user");
const outDirectory = takeOption(remainingArgs, "out");
// --parallel (runner speed trial, 2026-11-02): the copy's files come down several at a time.
const parallelFlagIndex = remainingArgs.indexOf("--parallel");
const parallel = parallelFlagIndex !== -1;
if (parallel) {
  remainingArgs.splice(parallelFlagIndex, 1);
}
const [sidekickId, ...extraArgs] = remainingArgs;

if (environment === null || !sidekickId || !/^[a-z0-9-]{1,40}$/.test(sidekickId) || extraArgs.length > 0 || !userId || !outDirectory) {
  stop(USAGE);
}
if (!USER_ID_PATTERN.test(userId)) {
  stop("user id must be letters, digits, dash or underscore (the id from the users table, not the name)");
}

// Bodies already brought down by prefetch (--parallel); null when the object is missing.
const prefetched = new Map();

async function readRemoteTextAsync(key) {
  try {
    return await captureWranglerAsync(["r2", "object", "get", `${environment.bucket}/${key}`, "--pipe", "--remote"]);
  } catch {
    return null;
  }
}

// Brings several objects down together; readRemoteText then answers from memory.
async function prefetch(keys) {
  const bodies = await runWithLimit(keys, PARALLEL_WRANGLER_CALLS, readRemoteTextAsync);
  for (let index = 0; index < keys.length; index += 1) {
    prefetched.set(keys[index], bodies[index]);
  }
}

function readRemoteText(key) {
  if (prefetched.has(key)) {
    return prefetched.get(key);
  }
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

// The user's own pointer, else the base's.
function resolveCopy() {
  const ownPrefix = storePrefix(sidekickId, userId);
  const ownPointer = readRemoteJson(pointerKeyFor(sidekickId, userId));
  if (ownPointer !== null) {
    return { pointer: ownPointer, prefix: ownPrefix, scope: "user" };
  }
  const basePointer = readRemoteJson(pointerKeyFor(sidekickId));
  if (basePointer === null) {
    stop(`${environment.name} has no version of ${sidekickId} for user ${userId} and no base`);
  }
  return { pointer: basePointer, prefix: storePrefix(sidekickId), scope: "base" };
}

const copy = resolveCopy();
const version = copy.pointer.version;
const targetDirectory = resolve(outDirectory);
mkdirSync(join(targetDirectory, TESTS_FOLDER), { recursive: true });

if (parallel) {
  const firstKeys = [];
  for (const fileName of ["index.html", "manifest.json", "version.json"]) {
    firstKeys.push(`${copy.prefix}/${version}/${fileName}`);
  }
  if (copy.pointer.tools) {
    firstKeys.push(`${copy.prefix}/${version}/${TOOLS_FILE}`);
  }
  firstKeys.push(testsIndexKey(copy.prefix, version));
  await prefetch(firstKeys);
  const prefetchedIndex = prefetched.get(testsIndexKey(copy.prefix, version));
  if (prefetchedIndex !== null) {
    const testKeys = [];
    for (const fileName of JSON.parse(prefetchedIndex).files) {
      testKeys.push(testFileKey(copy.prefix, version, fileName));
    }
    await prefetch(testKeys);
  }
}

for (const fileName of ["index.html", "manifest.json", "version.json"]) {
  const body = readRemoteText(`${copy.prefix}/${version}/${fileName}`);
  if (body === null) {
    stop(`${copy.prefix} ${version} is missing ${fileName}`);
  }
  writeFileSync(join(targetDirectory, fileName), body);
}

// tools.js travels with the page when the version has one (jess router, 2026-10-21)
let toolsNote = "";
if (copy.pointer.tools) {
  const toolsText = readRemoteText(`${copy.prefix}/${version}/${TOOLS_FILE}`);
  if (toolsText === null) {
    stop(`${copy.prefix} ${version} is missing ${TOOLS_FILE}`);
  }
  writeFileSync(join(targetDirectory, TOOLS_FILE), toolsText);
  toolsNote = ", tools";
}

const indexText = readRemoteText(testsIndexKey(copy.prefix, version));
let testFileCount = 0;
if (indexText === null) {
  console.warn(`warning: ${copy.prefix} ${version} has no stored tests`);
  writeFileSync(join(targetDirectory, TESTS_FOLDER, "index.json"), JSON.stringify({ files: [] }));
} else {
  const index = JSON.parse(indexText);
  for (const fileName of index.files) {
    const body = readRemoteText(testFileKey(copy.prefix, version, fileName));
    if (body === null) {
      stop(`${copy.prefix} ${version} is missing test file ${fileName}`);
    }
    writeFileSync(join(targetDirectory, TESTS_FOLDER, fileName), body);
    testFileCount += 1;
  }
  writeFileSync(join(targetDirectory, TESTS_FOLDER, "index.json"), indexText);
}

const source = copy.scope === "user" ? `user ${userId}'s copy` : `the base (user ${userId} has no copy yet)`;
console.log(`fetched ${sidekickId} ${version} from ${source} on ${environment.name} into ${targetDirectory}: page, manifest${toolsNote}, ${testFileCount} test file(s)`);
