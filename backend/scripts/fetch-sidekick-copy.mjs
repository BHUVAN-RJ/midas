// Usage, from backend/:
//   node scripts/fetch-sidekick-copy.mjs <sidekick-id> --env staging|live --user <user-id> --out <dir>
// Downloads one user's current copy of a Sidekick into <dir>: index.html, manifest.json,
// version.json and tests/ (the copy's test files, its TEST_CHANGES.md and tests/index.json).
// This is what the repair runner starts a job from (founder, 2026-10-13: tests move every copy
// forward). A user with no copy yet gets the base's current version, and the output says so.
// Read-only: nothing is written to R2.
import { mkdirSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { TESTS_FOLDER, USER_ID_PATTERN, pointerKeyFor, storePrefix, testFileKey, testsIndexKey } from "./bundle-tools.mjs";
import { environmentFromArgs, positionalArgs } from "./environments.mjs";
import { captureWrangler } from "./wrangler.mjs";

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
const [sidekickId, ...extraArgs] = remainingArgs;

if (environment === null || !sidekickId || !/^[a-z0-9-]{1,40}$/.test(sidekickId) || extraArgs.length > 0 || !userId || !outDirectory) {
  stop(USAGE);
}
if (!USER_ID_PATTERN.test(userId)) {
  stop("user id must be letters, digits, dash or underscore (the id from the users table, not the name)");
}

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

for (const fileName of ["index.html", "manifest.json", "version.json"]) {
  const body = readRemoteText(`${copy.prefix}/${version}/${fileName}`);
  if (body === null) {
    stop(`${copy.prefix} ${version} is missing ${fileName}`);
  }
  writeFileSync(join(targetDirectory, fileName), body);
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
console.log(`fetched ${sidekickId} ${version} from ${source} on ${environment.name} into ${targetDirectory}: page, manifest, ${testFileCount} test file(s)`);
