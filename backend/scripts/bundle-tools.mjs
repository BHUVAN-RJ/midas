// Pure helpers for deploying a Sidekick bundle; kept apart from the wrangler calls so they
// can be tested. A bundle is one index.html with inline scripts and styles only.
import { createHash } from "node:crypto";

const INLINE_SCRIPT_PATTERN = /<script>([\s\S]*?)<\/script>/g;
// Code-loading and long-lived-connection primitives the deploy gate rejects (PRODUCT.md,
// "Contract enforcement"). "<script " catches any script tag with attributes, including src.
const FORBIDDEN_PATTERNS = [
  { name: "script tag with attributes", pattern: /<script\s/i },
  { name: "import", pattern: /\bimport\s*\(|\bimport\s+[\w{*'"]/ },
  { name: "require", pattern: /\brequire\s*\(/ },
  { name: "WebSocket", pattern: /\bWebSocket\b/ },
];

export function findForbiddenPrimitives(html) {
  const violations = [];
  for (const forbidden of FORBIDDEN_PATTERNS) {
    if (forbidden.pattern.test(html)) {
      violations.push(forbidden.name);
    }
  }
  return violations;
}

// CSP hash sources for every inline script, in the form script-src expects.
export function inlineScriptHashes(html) {
  const hashes = [];
  for (const scriptMatch of html.matchAll(INLINE_SCRIPT_PATTERN)) {
    const scriptText = scriptMatch[1];
    const digest = createHash("sha256").update(scriptText, "utf8").digest("base64");
    hashes.push(`'sha256-${digest}'`);
  }
  return hashes;
}

// Versions sort by deploy time and carry a content prefix so two deploys never collide.
export function bundleVersion(html, deployedAt) {
  const contentPrefix = createHash("sha256").update(html, "utf8").digest("hex").slice(0, 8);
  const timestamp = deployedAt.toISOString().replace(/[-:.]/g, "");
  return `${timestamp}-${contentPrefix}`;
}

const HEX_COLOR_PATTERN = /^#[0-9A-Fa-f]{6}$/;
const RECORD_TYPE_PATTERN = /^[a-z0-9-]{1,40}$/;

// Checks manifest.json (PRODUCT.md D6: id, name, icon as SF Symbol plus background color,
// reads). Returns a list of problems; empty means valid.
export function validateManifest(manifest, sidekickId) {
  if (typeof manifest !== "object" || manifest === null || Array.isArray(manifest)) {
    return ["manifest must be a JSON object"];
  }
  const problems = [];
  if (manifest.id !== sidekickId) {
    problems.push(`id must be "${sidekickId}"`);
  }
  if (typeof manifest.name !== "string" || manifest.name.trim().length === 0) {
    problems.push("name must be a non-empty string");
  }
  const icon = manifest.icon;
  if (typeof icon !== "object" || icon === null) {
    problems.push("icon must be { symbol, background }");
  } else {
    if (typeof icon.symbol !== "string" || icon.symbol.length === 0) {
      problems.push("icon.symbol must be an SF Symbol name");
    }
    if (!HEX_COLOR_PATTERN.test(icon.background ?? "")) {
      problems.push("icon.background must be a color like #FF9500");
    }
  }
  if (!Array.isArray(manifest.reads) || !manifest.reads.every(isRecordType)) {
    problems.push("reads must be a list of record types, e.g. [\"reminder\"]");
  }
  return problems;
}

function isRecordType(value) {
  return typeof value === "string" && RECORD_TYPE_PATTERN.test(value);
}

// Identifies what was deployed, independent of when: the same page and manifest give the same
// hash on staging and on live. The two texts are hashed with their lengths so they cannot run
// into each other.
export function bundleContentHash(html, manifestText) {
  const hasher = createHash("sha256");
  hasher.update(`${html.length}:`, "utf8");
  hasher.update(html, "utf8");
  hasher.update(`${manifestText.length}:`, "utf8");
  hasher.update(manifestText, "utf8");
  return hasher.digest("hex");
}

// Live only takes what staging already runs. Returns the reason to refuse, or null to go ahead.
// stagingPointer is staging's current.json, or null if staging has never had this Sidekick.
export function liveDeployRefusal(stagingPointer, contentHash) {
  if (stagingPointer === null) {
    return "staging has no version of this Sidekick; deploy to staging first";
  }
  if (stagingPointer.contentHash !== contentHash) {
    return "staging runs a different version; deploy this one to staging first and try it there";
  }
  return null;
}

// ---- Per-user copies (repair, 2026-10-13) --------------------------------------------------
// Every user has their own copy of a Sidekick under sidekicks/<id>/users/<user_id>/: a pointer
// current.json and immutable versions, mirroring the base layout at sidekicks/<id>/. A repair
// moves one user's pointer; the base is changed only by the founder. A base deploy then updates
// every user copy that is still an untouched copy of a base version and lists the repaired ones.

// User ids are 22 characters of base64url (auth.ts randomId); the pattern allows nothing that
// could leave the users/ prefix.
export const USER_ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;

// The R2 key prefix for the base ("sidekicks/<id>") or for one user's copy.
export function storePrefix(sidekickId, userId = null) {
  if (userId === null) {
    return `sidekicks/${sidekickId}`;
  }
  if (!USER_ID_PATTERN.test(userId)) {
    throw new Error("bad user id");
  }
  return `sidekicks/${sidekickId}/users/${userId}`;
}

export function pointerKeyFor(sidekickId, userId = null) {
  return `${storePrefix(sidekickId, userId)}/current.json`;
}

// The objects one deploy writes, in the order they must go up: the version's files first, the
// pointer last, so the pointer never names a missing file. Refuses to reuse a version name that
// already exists, so stored versions stay immutable. baseVersion is the base version this copy
// derives from (null for a base deploy); contentHash tells a later base deploy whether the copy
// is untouched. A user copy that mirrors a base version is named after it (version given), so the
// pointer says which base it is.
// testFiles is the list of { name, body } stored with the version (an empty list writes an empty
// index); null means the caller stores no tests at all (the deploy script always passes a list).
export function planDeploy({ sidekickId, userId = null, html, manifestText, testFiles = null, deployedAt, deployedAtSeq = null, baseVersion = null, existingVersions = [], version = null }) {
  if (version === null) {
    version = bundleVersion(html, deployedAt);
  }
  if (existingVersions.includes(version)) {
    throw new Error(`version ${version} already exists; versions are immutable`);
  }
  const scriptHashes = inlineScriptHashes(html);
  const contentHash = bundleContentHash(html, manifestText);
  const pointer = { version, scriptHashes, contentHash, baseVersion };
  const storedTestNames = testFiles === null ? null : testFileNames(testFiles);
  const versionRecord = { version, scriptHashes, contentHash, baseVersion, forUser: userId, deployedAt: deployedAt.toISOString(), deployedAtSeq, testFiles: storedTestNames };
  const prefix = storePrefix(sidekickId, userId);
  const testPuts = testFiles === null ? [] : planTestFiles(prefix, version, testFiles);
  const puts = [
    { key: `${prefix}/${version}/index.html`, body: html, contentType: "text/html; charset=utf-8" },
    { key: `${prefix}/${version}/manifest.json`, body: manifestText, contentType: "application/json" },
    ...testPuts,
    { key: `${prefix}/${version}/version.json`, body: JSON.stringify(versionRecord), contentType: "application/json" },
    { key: pointerKeyFor(sidekickId, userId), body: JSON.stringify(pointer), contentType: "application/json" },
  ];
  return { version, scriptHashes, contentHash, pointer, puts };
}

// ---- Tests stored with each version (founder, 2026-10-13: "tests move every copy forward") ----
// A version's tests and their change log live under <prefix>/<version>/tests/<name>, listed in
// <prefix>/<version>/tests/index.json so a script can fetch them without listing the bucket.
// Nothing under tests/ is ever served to the phone: the bundle route reads only index.html.

export const TESTS_FOLDER = "tests";
export const TESTS_INDEX_FILE = "index.json";
export const TEST_LOG_FILE = "TEST_CHANGES.md";
// A plain file name: no path separators, so a test file can never land outside tests/.
export const TEST_FILE_NAME_PATTERN = /^[A-Za-z0-9][A-Za-z0-9_.-]{0,120}$/;

export function testFileKey(prefix, version, fileName) {
  if (!TEST_FILE_NAME_PATTERN.test(fileName) || fileName === TESTS_INDEX_FILE) {
    throw new Error(`bad test file name: ${fileName}`);
  }
  return `${prefix}/${version}/${TESTS_FOLDER}/${fileName}`;
}

export function testsIndexKey(prefix, version) {
  return `${prefix}/${version}/${TESTS_FOLDER}/${TESTS_INDEX_FILE}`;
}

export function testFileNames(testFiles) {
  const names = [];
  for (const testFile of testFiles) {
    names.push(testFile.name);
  }
  return names;
}

// The puts for a version's tests: every file, then the index naming them. An empty list writes
// an empty index, so a fetch can tell "no tests" from "tests missing".
export function planTestFiles(prefix, version, testFiles) {
  const puts = [];
  for (const testFile of testFiles) {
    puts.push({ key: testFileKey(prefix, version, testFile.name), body: testFile.body, contentType: "text/plain; charset=utf-8" });
  }
  const index = { files: testFileNames(testFiles) };
  puts.push({ key: testsIndexKey(prefix, version), body: JSON.stringify(index), contentType: "application/json" });
  return puts;
}

// The base Sidekick's tests in the repo: backend/test/<id>-*.test.ts plus the repo's test change
// log. testDirectoryEntries is the file list of backend/test; the log text may be null.
export function baseTestFileNames(sidekickId, testDirectoryEntries) {
  const names = [];
  const prefix = `${sidekickId}-`;
  for (const entryName of testDirectoryEntries) {
    if (entryName.startsWith(prefix) && entryName.endsWith(".test.ts")) {
      names.push(entryName);
    }
  }
  names.sort();
  return names;
}

// After a base deploy: which user copies follow it. A copy follows when its content is exactly
// the base version it was copied from (nothing repaired in it). baseContentHashes maps base
// version -> contentHash. A copy that was repaired, or whose origin cannot be checked, is left
// alone and listed for the founder.
export function sortUserCopies(userCopies, baseContentHashes) {
  const untouched = [];
  const left = [];
  for (const userCopy of userCopies) {
    const pointer = userCopy.pointer;
    const originHash = pointer.baseVersion === null || pointer.baseVersion === undefined ? undefined : baseContentHashes[pointer.baseVersion];
    if (originHash === undefined) {
      left.push({ userId: userCopy.userId, version: pointer.version, reason: "origin unknown" });
    } else if (pointer.contentHash === originHash) {
      untouched.push({ userId: userCopy.userId, version: pointer.version, baseVersion: pointer.baseVersion });
    } else {
      left.push({ userId: userCopy.userId, version: pointer.version, reason: `repaired on base ${pointer.baseVersion}` });
    }
  }
  return { untouched, left };
}

// Reads a Sidekick's index.html and manifest.json from a directory and runs the deploy gate.
// Returns { html, manifestText, manifest } or { problems }.
export function checkBundleFiles(html, manifestText, sidekickId) {
  const problems = [];
  const violations = findForbiddenPrimitives(html);
  if (violations.length > 0) {
    problems.push(`deploy gate rejected ${sidekickId}: ${violations.join(", ")}`);
  }
  let manifest = null;
  try {
    manifest = JSON.parse(manifestText);
  } catch {
    problems.push("manifest.json is not JSON");
    return { problems };
  }
  const manifestProblems = validateManifest(manifest, sidekickId);
  if (manifestProblems.length > 0) {
    problems.push(`manifest.json: ${manifestProblems.join("; ")}`);
  }
  return { problems, manifest };
}
