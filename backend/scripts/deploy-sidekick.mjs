// Usage, from backend/:
//   node scripts/deploy-sidekick.mjs <sidekick-id> --env staging|live
//       Base deploy: uploads ../sidekicks/<id>/index.html and manifest.json as a new immutable
//       version, moves the base pointer, then updates every user copy that is still an untouched
//       copy of a base version. Repaired copies are left alone and listed. Live refuses unless
//       staging already runs exactly this page and manifest.
//   node scripts/deploy-sidekick.mjs <sidekick-id> --env staging|live --user <user-id> [--dir <path>]
//       One user's copy (repair, 2026-10-13): uploads the files (from <path>, default
//       ../sidekicks/<id>/) into sidekicks/<id>/users/<user-id>/ and moves only that user's
//       pointer. The base is never written. No staging step (founder, 2026-10-13: D).
//   node scripts/deploy-sidekick.mjs <sidekick-id> --env staging|live --user <user-id> --from-base
//       Copies the base's current version into that user's store: the way back from a repair,
//       or pushing a base fix to one user by hand.
// Old versions always stay in R2.
// Tests travel with every version (founder, 2026-10-13): a base deploy uploads
// backend/test/<id>-*.test.ts and the repo's TEST_CHANGES.md under <version>/tests/; a --dir
// deploy uploads <dir>/tests/*; --from-base and untouched-copy updates carry the base's tests.
// Nothing under tests/ is served to the phone. Fetch a copy with scripts/fetch-sidekick-copy.mjs.
import { fileURLToPath } from "node:url";
import { existsSync, readdirSync, readFileSync, writeFileSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import {
  TEST_FILE_NAME_PATTERN,
  TEST_LOG_FILE,
  TESTS_FOLDER,
  TESTS_INDEX_FILE,
  USER_ID_PATTERN,
  baseTestFileNames,
  bundleContentHash,
  checkBundleFiles,
  liveDeployRefusal,
  planDeploy,
  pointerKeyFor,
  sortUserCopies,
  storePrefix,
  testFileKey,
  testsIndexKey,
} from "./bundle-tools.mjs";
import { ENVIRONMENTS, environmentFromArgs, positionalArgs } from "./environments.mjs";
import { rowsFromWranglerJson, sqlLiteral } from "./db-tools.mjs";
import { captureWrangler, runWrangler } from "./wrangler.mjs";

const USAGE = [
  "usage: node scripts/deploy-sidekick.mjs <sidekick-id> --env staging|live",
  "       node scripts/deploy-sidekick.mjs <sidekick-id> --env staging|live --user <user-id> [--dir <path>]",
  "       node scripts/deploy-sidekick.mjs <sidekick-id> --env staging|live --user <user-id> --from-base",
].join("\n");

function stop(message) {
  console.error(message);
  process.exit(1);
}

// Returns the value after "--<name>" and removes both from the list; null when absent.
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

const commandArgs = process.argv.slice(2);
const environment = environmentFromArgs(commandArgs);
const remainingArgs = positionalArgs(commandArgs);
const userId = takeOption(remainingArgs, "user");
const sourceDirectory = takeOption(remainingArgs, "dir");
const fromBase = takeFlag(remainingArgs, "from-base");
const [sidekickId, ...extraArgs] = remainingArgs;

if (environment === null || !sidekickId || !/^[a-z0-9-]{1,40}$/.test(sidekickId) || extraArgs.length > 0) {
  stop(USAGE);
}
if (userId !== null && !USER_ID_PATTERN.test(userId)) {
  stop("user id must be letters, digits, dash or underscore (the id from the users table, not the name)");
}
if (userId === null && (sourceDirectory !== null || fromBase)) {
  stop("--dir and --from-base go with --user; the base deploys from sidekicks/<id>/ only");
}
if (fromBase && sourceDirectory !== null) {
  stop("--from-base takes no --dir");
}

// ---- remote helpers ---------------------------------------------------------------------------

function readRemoteJson(bucketName, key) {
  try {
    const text = captureWrangler(["r2", "object", "get", `${bucketName}/${key}`, "--pipe", "--remote"]);
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function readRemoteText(bucketName, key) {
  try {
    return captureWrangler(["r2", "object", "get", `${bucketName}/${key}`, "--pipe", "--remote"]);
  } catch {
    return null;
  }
}

const scratchDirectory = mkdtempSync(join(tmpdir(), "sidekick-"));
let scratchCounter = 0;

function putObject(key, body, contentType) {
  scratchCounter += 1;
  const filePath = join(scratchDirectory, `object-${scratchCounter}`);
  writeFileSync(filePath, body);
  runWrangler(["r2", "object", "put", `${environment.bucket}/${key}`, "--file", filePath, "--content-type", contentType, "--remote"]);
}

function executePlan(plan) {
  for (const put of plan.puts) {
    putObject(put.key, put.body, put.contentType);
  }
}

function queryRemote(sql) {
  try {
    const outputText = captureWrangler(["d1", "execute", environment.database, "--remote", "--json", "--command", sql, ...environment.wranglerEnvArgs]);
    return rowsFromWranglerJson(outputText);
  } catch {
    return null;
  }
}

// The op-log sequence at deploy time (D5), so code and data can be rolled back together. Null
// if the ops table does not exist yet in this environment.
function readCurrentSeq() {
  const rows = queryRemote("SELECT COALESCE(MAX(seq), 0) AS seq FROM ops");
  return rows?.[0]?.seq ?? null;
}

// ---- the bundle files -------------------------------------------------------------------------

function readBundleFiles(directoryPath) {
  const html = readFileSync(join(directoryPath, "index.html"), "utf8");
  const manifestText = readFileSync(join(directoryPath, "manifest.json"), "utf8");
  const checked = checkBundleFiles(html, manifestText, sidekickId);
  if (checked.problems.length > 0) {
    stop(checked.problems.join("\n"));
  }
  return { html, manifestText };
}

const defaultDirectory = fileURLToPath(new URL(`../../sidekicks/${sidekickId}/`, import.meta.url));
const repoTestDirectory = fileURLToPath(new URL("../test/", import.meta.url));
const repoRootDirectory = fileURLToPath(new URL("../../", import.meta.url));
const repoTestLogPath = join(repoRootDirectory, TEST_LOG_FILE);

function readTestFile(directoryPath, fileName) {
  if (!TEST_FILE_NAME_PATTERN.test(fileName)) {
    stop(`bad test file name: ${fileName}`);
  }
  return { name: fileName, body: readFileSync(join(directoryPath, fileName), "utf8") };
}

// The base Sidekick's tests from the repo: backend/test/<id>-*.test.ts plus the repo test log.
function readBaseTestFiles() {
  const testFiles = [];
  for (const fileName of baseTestFileNames(sidekickId, readdirSync(repoTestDirectory))) {
    testFiles.push(readTestFile(repoTestDirectory, fileName));
  }
  if (existsSync(repoTestLogPath)) {
    testFiles.push({ name: TEST_LOG_FILE, body: readFileSync(repoTestLogPath, "utf8") });
  }
  if (testFiles.length === 0) {
    console.warn(`warning: no tests named ${sidekickId}-*.test.ts in backend/test; the version goes up with no tests`);
  }
  return testFiles;
}

// A job folder's tests: every file in <dir>/tests/ (the index is rebuilt, never copied).
function readDirectoryTestFiles(directoryPath) {
  const testsPath = join(directoryPath, TESTS_FOLDER);
  if (!existsSync(testsPath)) {
    stop(`${testsPath} is missing; a user copy deploys its tests with the page (founder, 2026-10-13)`);
  }
  const testFiles = [];
  for (const fileName of readdirSync(testsPath).sort()) {
    if (fileName !== TESTS_INDEX_FILE) {
      testFiles.push(readTestFile(testsPath, fileName));
    }
  }
  if (testFiles.length === 0) {
    stop(`${testsPath} is empty; a user copy deploys its tests with the page`);
  }
  return testFiles;
}

// The tests stored with a version in R2, via its index.
function readRemoteTestFiles(prefix, version) {
  const index = readRemoteJson(environment.bucket, testsIndexKey(prefix, version));
  if (index === null) {
    return [];
  }
  const testFiles = [];
  for (const fileName of index.files) {
    const body = readRemoteText(environment.bucket, testFileKey(prefix, version, fileName));
    if (body === null) {
      stop(`${prefix} ${version} is missing test file ${fileName}`);
    }
    testFiles.push({ name: fileName, body });
  }
  return testFiles;
}

// ---- --from-base: copy the base's current version into one user's store -----------------------

function deployUserFromBase() {
  const basePointer = readRemoteJson(environment.bucket, pointerKeyFor(sidekickId));
  if (basePointer === null) {
    stop(`${environment.name} has no base version of ${sidekickId}`);
  }
  const basePrefix = storePrefix(sidekickId);
  const html = readRemoteText(environment.bucket, `${basePrefix}/${basePointer.version}/index.html`);
  const manifestText = readRemoteText(environment.bucket, `${basePrefix}/${basePointer.version}/manifest.json`);
  if (html === null || manifestText === null) {
    stop(`base ${sidekickId} ${basePointer.version} is missing its files on ${environment.name}`);
  }
  const testFiles = readRemoteTestFiles(basePrefix, basePointer.version);
  if (testFiles.length === 0) {
    console.warn(`warning: base ${basePointer.version} has no stored tests; the copy gets none`);
  }
  // The copy keeps the base version's name so the pointer says which base it is.
  const plan = planDeploy({ sidekickId, userId, html, manifestText, testFiles, deployedAt: new Date(), deployedAtSeq: readCurrentSeq(), baseVersion: basePointer.version, version: basePointer.version });
  executePlan(plan);
  console.log(`${sidekickId} for user ${userId} on ${environment.name} is now the base version ${basePointer.version} with ${testFiles.length} test file(s)`);
}

// ---- --user: one user's copy from local files -------------------------------------------------

function deployUserCopy() {
  const directoryPath = sourceDirectory === null ? defaultDirectory : resolve(sourceDirectory);
  const { html, manifestText } = readBundleFiles(directoryPath);
  // From a job folder, the tests are the folder's; from the repo, the base Sidekick's.
  const testFiles = sourceDirectory === null ? readBaseTestFiles() : readDirectoryTestFiles(directoryPath);
  const basePointer = readRemoteJson(environment.bucket, pointerKeyFor(sidekickId));
  const previousPointer = readRemoteJson(environment.bucket, pointerKeyFor(sidekickId, userId));
  // The copy records the base it builds on: the user's previous copy's base, else the current base.
  const baseVersion = previousPointer?.baseVersion ?? basePointer?.version ?? null;
  const plan = planDeploy({ sidekickId, userId, html, manifestText, testFiles, deployedAt: new Date(), deployedAtSeq: readCurrentSeq(), baseVersion });
  executePlan(plan);
  console.log(`deployed ${sidekickId} ${plan.version} for user ${userId} to ${environment.name} with ${plan.scriptHashes.length} script hash(es) and ${testFiles.length} test file(s); base untouched`);
}

// ---- base deploy, then the untouched user copies ---------------------------------------------

function userIdsAssigned() {
  const rows = queryRemote(`SELECT user_id FROM assignments WHERE sidekick_id = ${sqlLiteral(sidekickId)} ORDER BY user_id`);
  if (rows === null) {
    return [];
  }
  return rows.map(rowUserId);
}

function rowUserId(row) {
  return row.user_id;
}

// Every user with a copy, with their pointer.
function readUserCopies() {
  const userCopies = [];
  for (const assignedUserId of userIdsAssigned()) {
    const pointer = readRemoteJson(environment.bucket, pointerKeyFor(sidekickId, assignedUserId));
    if (pointer !== null) {
      userCopies.push({ userId: assignedUserId, pointer });
    }
  }
  return userCopies;
}

// contentHash of each base version a user copy names, read from the base's version.json files.
function baseContentHashesFor(userCopies) {
  const hashes = {};
  for (const userCopy of userCopies) {
    const baseVersion = userCopy.pointer.baseVersion;
    if (!baseVersion || baseVersion in hashes) {
      continue;
    }
    const record = readRemoteJson(environment.bucket, `${storePrefix(sidekickId)}/${baseVersion}/version.json`);
    if (record?.contentHash) {
      hashes[baseVersion] = record.contentHash;
    }
  }
  return hashes;
}

function deployBase() {
  const { html, manifestText } = readBundleFiles(defaultDirectory);
  const contentHash = bundleContentHash(html, manifestText);
  if (environment.name === "live") {
    const stagingPointer = readRemoteJson(ENVIRONMENTS.staging.bucket, pointerKeyFor(sidekickId));
    const refusal = liveDeployRefusal(stagingPointer, contentHash);
    if (refusal !== null) {
      stop(`live deploy refused: ${refusal}`);
    }
  }
  const testFiles = readBaseTestFiles();
  const deployedAt = new Date();
  const deployedAtSeq = readCurrentSeq();
  const plan = planDeploy({ sidekickId, html, manifestText, testFiles, deployedAt, deployedAtSeq });
  executePlan(plan);
  console.log(`deployed ${sidekickId} ${plan.version} to ${environment.name} with ${plan.scriptHashes.length} script hash(es) and ${testFiles.length} test file(s)`);

  // Untouched user copies follow the base, tests included; repaired ones are the founder's to merge.
  const userCopies = readUserCopies();
  const sorted = sortUserCopies(userCopies, baseContentHashesFor(userCopies));
  for (const untouched of sorted.untouched) {
    const userPlan = planDeploy({ sidekickId, userId: untouched.userId, html, manifestText, testFiles, deployedAt, deployedAtSeq, baseVersion: plan.version, version: plan.version });
    executePlan(userPlan);
    console.log(`  updated copy of user ${untouched.userId} (was base ${untouched.baseVersion})`);
  }
  for (const left of sorted.left) {
    console.log(`  LEFT user ${left.userId} on ${left.version}: ${left.reason}; needs merge`);
  }
  console.log(`user copies: ${sorted.untouched.length} updated, ${sorted.left.length} left, ${userIdsAssigned().length} assigned`);
}

if (userId !== null && fromBase) {
  deployUserFromBase();
} else if (userId !== null) {
  deployUserCopy();
} else {
  deployBase();
}
