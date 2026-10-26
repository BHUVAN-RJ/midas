// Usage, from backend/:
//   node scripts/stage-user-copy.mjs <sidekick-id> <copy-name> --out <dir>
// Builds the folder deploy-sidekick.mjs --user <user-id> --dir <dir> uploads, for a user copy kept
// by hand in the repo (founder, 2026-10-25, first: Boomi's Reminders) under
// copies/<sidekick-id>/<copy-name>/:
//   sidekick/index.html, manifest.json, tools.js   the copy's page and its jess tools
//   tests/*.test.ts                                tests of this copy only
//   copy.json                                      { "sidekick", "for", "baseTests": [...] }
// The staged folder holds the page files, and in tests/ the base tests copy.json names (read from
// backend/test at staging time, so a base test fix reaches the copy on its next deploy), the
// copy's own tests and the repo's TEST_CHANGES.md, the same log a base deploy carries.
// Writes only <dir>. The repo is never written.
import { cpSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { TEST_LOG_FILE, TESTS_FOLDER, TOOLS_FILE } from "./bundle-tools.mjs";

export const REPO_ROOT = resolve(fileURLToPath(new URL("../..", import.meta.url)));
export const COPY_FILE = "copy.json";
const PAGE_FILES = ["index.html", "manifest.json", TOOLS_FILE];
const COPY_NAME_PATTERN = /^[a-z0-9][a-z0-9-]{0,60}$/;

export function copyFolderFor(repoRoot, sidekickId, copyName) {
  return join(repoRoot, "copies", sidekickId, copyName);
}

// copy.json, checked: it names this Sidekick, and each base test is one of that Sidekick's tests in backend/test
export function readCopyDescription(repoRoot, sidekickId, copyName) {
  if (!COPY_NAME_PATTERN.test(copyName)) {
    throw new Error(`bad copy name: ${copyName}`);
  }
  const copyFolder = copyFolderFor(repoRoot, sidekickId, copyName);
  const description = JSON.parse(readFileSync(join(copyFolder, COPY_FILE), "utf8"));
  if (description.sidekick !== sidekickId) {
    throw new Error(`${COPY_FILE} names sidekick ${description.sidekick}, not ${sidekickId}`);
  }
  const baseTests = Array.isArray(description.baseTests) ? description.baseTests : [];
  const repoTestFolder = join(repoRoot, "backend", "test");
  for (const fileName of baseTests) {
    const isOwnTest = fileName.startsWith(`${sidekickId}-`) && fileName.endsWith(".test.ts");
    if (!isOwnTest || !existsSync(join(repoTestFolder, fileName))) {
      throw new Error(`${COPY_FILE} base test ${fileName} is not a ${sidekickId} test in backend/test`);
    }
  }
  return { sidekick: description.sidekick, for: description.for ?? null, baseTests };
}

/* Stages the copy into outDir (replaced). pageFolderName "" gives the deploy layout (page files at
   the top, deploy-sidekick.mjs --dir); "sidekick" gives the repair runner's job layout (check.mjs).
   Returns the list of test file names staged. */
export function stageUserCopy({ repoRoot = REPO_ROOT, sidekickId, copyName, outDir, pageFolderName = "" }) {
  const description = readCopyDescription(repoRoot, sidekickId, copyName);
  const copyFolder = copyFolderFor(repoRoot, sidekickId, copyName);
  rmSync(outDir, { recursive: true, force: true });
  const pageFolder = join(outDir, pageFolderName);
  mkdirSync(pageFolder, { recursive: true });
  for (const fileName of PAGE_FILES) {
    const sourcePath = join(copyFolder, "sidekick", fileName);
    if (existsSync(sourcePath)) {
      cpSync(sourcePath, join(pageFolder, fileName));
    }
  }

  const testsFolder = join(outDir, TESTS_FOLDER);
  mkdirSync(testsFolder, { recursive: true });
  const staged = [];
  const repoTestFolder = join(repoRoot, "backend", "test");
  for (const fileName of description.baseTests) {
    cpSync(join(repoTestFolder, fileName), join(testsFolder, fileName));
    staged.push(fileName);
  }
  const ownTestsFolder = join(copyFolder, TESTS_FOLDER);
  const ownTestNames = existsSync(ownTestsFolder) ? readdirSync(ownTestsFolder).sort() : [];
  for (const fileName of ownTestNames) {
    if (staged.includes(fileName)) {
      throw new Error(`copy test ${fileName} has the same name as a base test`);
    }
    cpSync(join(ownTestsFolder, fileName), join(testsFolder, fileName));
    staged.push(fileName);
  }
  const repoTestLog = join(repoRoot, TEST_LOG_FILE);
  if (existsSync(repoTestLog)) {
    cpSync(repoTestLog, join(testsFolder, TEST_LOG_FILE));
  }
  return staged;
}

function runFromCommandLine() {
  const args = process.argv.slice(2);
  const outIndex = args.indexOf("--out");
  const outDir = outIndex === -1 ? null : args[outIndex + 1];
  const positional = outIndex === -1 ? args : args.slice(0, outIndex).concat(args.slice(outIndex + 2));
  const [sidekickId, copyName] = positional;
  if (!sidekickId || !copyName || !outDir) {
    console.error("usage: node scripts/stage-user-copy.mjs <sidekick-id> <copy-name> --out <dir>");
    process.exit(1);
  }
  const outPath = resolve(outDir);
  const staged = stageUserCopy({ sidekickId, copyName, outDir: outPath });
  console.log(`staged ${sidekickId} copy ${copyName} in ${outPath} with ${staged.length} test file(s)`);
  console.log(`next: node scripts/deploy-sidekick.mjs ${sidekickId} --env <staging|live> --user <user-id> --dir ${outPath}`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  runFromCommandLine();
}
