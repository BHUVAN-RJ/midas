// Pure helpers for deploying a Sidekick bundle; kept apart from the wrangler calls so they
// can be tested. A bundle is one index.html with inline scripts and styles only.
import { createHash } from "node:crypto";
import vm from "node:vm";

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
    // The tile in dark mode (founder, 2026-10-31; docs/ICONS.md). Optional so a manifest from
    // before build 22 still deploys; when given it must be a colour.
    if (icon.backgroundDark !== undefined && !HEX_COLOR_PATTERN.test(String(icon.backgroundDark))) {
      problems.push("icon.backgroundDark must be a color like #B36800");
    }
  }
  if (!Array.isArray(manifest.reads) || !manifest.reads.every(isRecordType)) {
    problems.push("reads must be a list of record types, e.g. [\"reminder\"]");
  }
  if (manifest.types !== undefined) {
    problems.push(...typesBlockProblems(manifest.types, sidekickId));
  }
  // The Sidekick's tools for jess and outside agents (founder, 2026-10-21); tools.js itself is
  // checked with the files (sidekick-tools.mjs, sidekickToolsProblems)
  if (manifest.agent !== undefined) {
    problems.push(...agentBlockProblems(manifest.agent, sidekickId));
  }
  return problems;
}

// Key prefixes the shell owns in every Sidekick (shell/sdk/shell-types.js); a manifest may not
// redeclare them. Listed here, not imported: this file also runs in the repair runner's scratch
// checkouts, which hold backend/scripts only. A test keeps the two lists equal.
export const SHELL_TYPE_PREFIXES = ["widget:", "request:"];
const TYPE_NAME_PATTERN = /^[a-z][a-z0-9-]*\.[a-z][A-Za-z0-9-]*$/;
const KEY_PREFIX_PATTERN = /^[a-z][a-z0-9-]*:$/;

// The manifest's record types (unified data, founder 2026-10-15: schemas live in manifest.json).
// Every prefix maps to { $type: "<sidekickId>.<name>", schema }: the prefix ends with ":", the
// type name is unique and in the Sidekick's namespace, the schema is an object schema.
export function typesBlockProblems(types, sidekickId) {
  if (typeof types !== "object" || types === null || Array.isArray(types)) {
    return ["types must be an object of key prefixes"];
  }
  const problems = [];
  const seenTypeNames = [];
  for (const prefix of Object.keys(types)) {
    const entry = types[prefix];
    if (!KEY_PREFIX_PATTERN.test(prefix)) {
      problems.push(`types: "${prefix}" must be a key prefix like "reminder:"`);
    }
    if (SHELL_TYPE_PREFIXES.includes(prefix)) {
      problems.push(`types: "${prefix}" is a shell type and cannot be redeclared`);
    }
    if (typeof entry !== "object" || entry === null || Array.isArray(entry)) {
      problems.push(`types["${prefix}"] must be { "$type", "schema" }`);
      continue;
    }
    if (typeof entry.$type !== "string" || !TYPE_NAME_PATTERN.test(entry.$type)) {
      problems.push(`types["${prefix}"].$type must be <sidekick>.<name>, like "reminders.item"`);
      continue;
    }
    if (seenTypeNames.includes(entry.$type)) {
      problems.push(`types["${prefix}"].$type "${entry.$type}" is used by another prefix`);
    }
    seenTypeNames.push(entry.$type);
    const schema = entry.schema;
    if (typeof schema !== "object" || schema === null || schema.type !== "object") {
      problems.push(`types["${prefix}"].schema must be a JSON Schema with "type": "object"`);
    }
    const typeName = entry.$type;
    const namespaces = sidekickNamespaces(sidekickId);
    let hasOwnNamespace = false;
    for (const namespace of namespaces) {
      if (typeName.startsWith(`${namespace}.`)) {
        hasOwnNamespace = true;
      }
    }
    if (!hasOwnNamespace) {
      problems.push(`types["${prefix}"].$type must start with "${namespaces.join('." or "')}."`);
    }
  }
  return problems;
}

// The namespaces a Sidekick's types may use: its id, and the first word of a hyphenated id
// ("care-reminders" -> "care", plan section 4). Both are accepted.
export function sidekickNamespaces(sidekickId) {
  const firstWord = sidekickId.split("-")[0];
  if (firstWord === sidekickId) {
    return [sidekickId];
  }
  return [sidekickId, firstWord];
}

function isRecordType(value) {
  return typeof value === "string" && RECORD_TYPE_PATTERN.test(value);
}

// Identifies what was deployed, independent of when: the same page and manifest give the same
// hash on staging and on live. The texts are hashed with their lengths so they cannot run into
// each other. tools.js (jess router, 2026-10-21) counts only when the Sidekick has one, so every
// version deployed before it keeps its hash.
export function bundleContentHash(html, manifestText, toolsText = null) {
  const hasher = createHash("sha256");
  hasher.update(`${html.length}:`, "utf8");
  hasher.update(html, "utf8");
  hasher.update(`${manifestText.length}:`, "utf8");
  hasher.update(manifestText, "utf8");
  if (toolsText !== null && toolsText !== undefined) {
    hasher.update(`tools.js ${toolsText.length}:`, "utf8");
    hasher.update(toolsText, "utf8");
  }
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
// toolsText is the Sidekick's tools.js, or null when it has none; it goes up beside index.html.
export function planDeploy({ sidekickId, userId = null, html, manifestText, toolsText = null, testFiles = null, deployedAt, deployedAtSeq = null, baseVersion = null, existingVersions = [], version = null }) {
  if (version === null) {
    version = bundleVersion(html, deployedAt);
  }
  if (existingVersions.includes(version)) {
    throw new Error(`version ${version} already exists; versions are immutable`);
  }
  const scriptHashes = inlineScriptHashes(html);
  const hasTools = toolsText !== null && toolsText !== undefined;
  const contentHash = bundleContentHash(html, manifestText, hasTools ? toolsText : null);
  const pointer = { version, scriptHashes, contentHash, baseVersion };
  const storedTestNames = testFiles === null ? null : testFileNames(testFiles);
  const versionRecord = { version, scriptHashes, contentHash, baseVersion, forUser: userId, deployedAt: deployedAt.toISOString(), deployedAtSeq, testFiles: storedTestNames };
  if (hasTools) {
    pointer.tools = TOOLS_FILE;
    versionRecord.tools = TOOLS_FILE;
  }
  const prefix = storePrefix(sidekickId, userId);
  const testPuts = testFiles === null ? [] : planTestFiles(prefix, version, testFiles);
  const toolsPuts = hasTools ? [{ key: `${prefix}/${version}/${TOOLS_FILE}`, body: toolsText, contentType: TOOLS_CONTENT_TYPE }] : [];
  const puts = [
    { key: `${prefix}/${version}/index.html`, body: html, contentType: "text/html; charset=utf-8" },
    { key: `${prefix}/${version}/manifest.json`, body: manifestText, contentType: "application/json" },
    ...toolsPuts,
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

// Runs the deploy gate over a Sidekick's index.html, manifest.json and tools.js (null when it
// has none). Returns { problems, manifest }.
export function checkBundleFiles(html, manifestText, sidekickId, toolsText = null) {
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
  // The agent block itself is in validateManifest; here, tools.js and the two together
  for (const toolsProblem of sidekickToolsProblems(manifest, toolsText, html, sidekickId)) {
    if (!toolsProblem.startsWith("manifest.json: ")) {
      problems.push(toolsProblem);
    }
  }
  return { problems, manifest };
}

/* ---------- A Sidekick's tools ---------- */

// Checks for a Sidekick's agent block (manifest.json "agent") and its tools.js (jess router,
// founder 2026-10-21: every action a person can take in a Sidekick is a tool, MCP-style; every
// builder keeps them true). Used by the deploy gate (bundle-tools.mjs) and so by the repair
// runner, which refuses a copy whose tools do not validate.
//
// The agent block:
//   { description, rules: [..], notFor: [..], examples: [..],
//     tools: [{ name: "<sidekickId>.<verb>", description, inputSchema,
//               _meta: { "midas/page-actions": ["<control>", ..], "midas/when"?: "<property>" } }] }
// A tool is only an action a person can take on the page (founder, 2026-10-21): "midas/page-actions"
// names the page's controls for it, each a data-action value or a page function name, and every
// one must be in index.html. The repair runner uses the same names to check that a removed tool's
// action is gone from the page (schema-change.mjs).
// A tool is an MCP tool (name, description, inputSchema). inputSchema stays inside the JSON Schema
// subset every provider's strict mode accepts (midas-intel docs/research/agent-ready/
// data-format-interop-standards.md, section 5): objects with additionalProperties false and every
// property required, nullable unions, enum, const, items, $defs and $ref without recursion. Ranges
// and lengths are not allowed there; handlers check them.
//
// tools.js: a plain script with one global, MidasSidekickTools = { context(records, now),
// handlers: { <verb>(input, records, now) } }. Blocks between "copied from index.html" markers
// must appear in index.html character for character.
// Kept in this file, not imported: the runner's tests copy bundle-tools.mjs alone into scratch
// checkouts. sidekick-tools.mjs re-exports these for readers who look for them by name.

export const TOOLS_FILE = "tools.js";
export const TOOLS_CONTENT_TYPE = "text/javascript; charset=utf-8";
export const TOOLS_GLOBAL = "MidasSidekickTools";
export const WHEN_META_KEY = "midas/when";
export const PAGE_ACTIONS_META_KEY = "midas/page-actions";
// OpenAI-style function names allow letters, digits, "_" and "-", up to 64; the dot becomes "__"
// on the wire, so <sidekickId>__<verb> must fit.
export const WIRE_NAME_LIMIT = 64;
export const COPY_BEGIN = "/* copied from index.html: begin */";
export const COPY_END = "/* copied from index.html: end */";

const VERB_PATTERN = /^[a-z][a-z0-9_]{0,39}$/;
const MAX_TOOLS = 60;
const MAX_TEXT = 1000;
const MAX_LIST = 40;
const MAX_SCHEMA_DEPTH = 10;
const MAX_ENUM = 1000;
const SCHEMA_TYPES = ["object", "array", "string", "integer", "number", "boolean", "null"];
const ALLOWED_KEYWORDS = ["type", "properties", "required", "additionalProperties", "items", "enum", "const", "anyOf", "$ref", "$defs", "description", "format"];
const ALLOWED_FORMATS = ["date-time", "date", "time"];
const DEFS_PREFIX = "#/$defs/";
const LOAD_TIMEOUT_MS = 2000;
const PAGE_ACTION_PATTERN = /^[A-Za-z][A-Za-z0-9_-]{0,60}$/;
const MAX_PAGE_ACTIONS = 10;

// What tools.js may not do: load code, reach the network or the store. Handlers return changes.
const FORBIDDEN_IN_TOOLS = [
  { name: "import", pattern: /\bimport\s*\(|\bimport\s+[\w{*'"]/ },
  { name: "require", pattern: /\brequire\s*\(/ },
  { name: "WebSocket", pattern: /\bWebSocket\b/ },
  { name: "fetch", pattern: /\bfetch\s*\(/ },
  { name: "XMLHttpRequest", pattern: /\bXMLHttpRequest\b/ },
  { name: "store", pattern: /\bstore\.(set|get|update|delete|query|putFile|fileUrl)\s*\(/ },
  { name: "eval", pattern: /\beval\s*\(|\bnew\s+Function\b/ },
];

function isPlainObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isText(value, limit = MAX_TEXT) {
  return typeof value === "string" && value.trim().length > 0 && value.length <= limit;
}

function textListProblems(value, field) {
  if (!Array.isArray(value) || value.length > MAX_LIST) {
    return [`agent.${field} must be a list of up to ${MAX_LIST} lines`];
  }
  for (const line of value) {
    if (!isText(line)) {
      return [`agent.${field} must hold non-empty lines of up to ${MAX_TEXT} characters`];
    }
  }
  return [];
}

/* ---------- inputSchema: the strict-mode subset ---------- */

function typesOf(schema) {
  if (Array.isArray(schema.type)) {
    return schema.type;
  }
  return schema.type === undefined ? [] : [schema.type];
}

function defNameOf(ref) {
  return typeof ref === "string" && ref.startsWith(DEFS_PREFIX) ? ref.slice(DEFS_PREFIX.length) : null;
}

// Every problem with one schema node, its children checked too. defs are the root's $defs;
// refChain holds the $defs being expanded, so a $ref back into one of them is recursion.
function schemaNodeProblems(schema, path, defs, refChain, depth) {
  if (!isPlainObject(schema)) {
    return [`${path} must be a schema object`];
  }
  if (depth > MAX_SCHEMA_DEPTH) {
    return [`${path} is nested deeper than ${MAX_SCHEMA_DEPTH}`];
  }
  const problems = [];
  for (const keyword of Object.keys(schema)) {
    if (!ALLOWED_KEYWORDS.includes(keyword)) {
      problems.push(`${path} uses "${keyword}", which strict tool schemas do not accept`);
    }
  }
  if (schema.$defs !== undefined && depth > 0) {
    problems.push(`${path}: $defs only at the top of inputSchema`);
  }
  if (schema.format !== undefined && !ALLOWED_FORMATS.includes(schema.format)) {
    problems.push(`${path}: format must be one of ${ALLOWED_FORMATS.join(", ")}`);
  }
  if (schema.$ref !== undefined) {
    const name = defNameOf(schema.$ref);
    if (name === null || !isPlainObject(defs) || !isPlainObject(defs[name])) {
      problems.push(`${path}: $ref must name an entry of $defs`);
    } else if (refChain.includes(name)) {
      problems.push(`${path}: $ref "${schema.$ref}" is recursive`);
    } else {
      problems.push(...schemaNodeProblems(defs[name], `${DEFS_PREFIX}${name}`, defs, refChain.concat([name]), depth + 1));
    }
    if (Object.keys(schema).length > 1 && !(Object.keys(schema).length === 2 && schema.description !== undefined)) {
      problems.push(`${path}: $ref stands alone (a description at most)`);
    }
    return problems;
  }
  if (schema.anyOf !== undefined) {
    if (!Array.isArray(schema.anyOf) || schema.anyOf.length < 2 || schema.anyOf.length > 16) {
      problems.push(`${path}.anyOf must list 2 to 16 schemas`);
      return problems;
    }
    if (depth === 0) {
      problems.push(`${path}: the top of inputSchema must be an object, not anyOf`);
    }
    for (let index = 0; index < schema.anyOf.length; index += 1) {
      problems.push(...schemaNodeProblems(schema.anyOf[index], `${path}.anyOf[${index}]`, defs, refChain, depth + 1));
    }
    return problems;
  }
  const types = typesOf(schema);
  if (types.length === 0 && schema.const === undefined && schema.enum === undefined) {
    problems.push(`${path} needs a type`);
  }
  for (const type of types) {
    if (!SCHEMA_TYPES.includes(type)) {
      problems.push(`${path}: unknown type "${type}"`);
    }
  }
  if (schema.enum !== undefined && (!Array.isArray(schema.enum) || schema.enum.length === 0 || schema.enum.length > MAX_ENUM)) {
    problems.push(`${path}.enum must list 1 to ${MAX_ENUM} values`);
  }
  if (types.includes("object")) {
    problems.push(...objectSchemaProblems(schema, path, defs, refChain, depth));
  }
  if (types.includes("array")) {
    if (schema.items === undefined) {
      problems.push(`${path}: an array needs items`);
    } else {
      problems.push(...schemaNodeProblems(schema.items, `${path}.items`, defs, refChain, depth + 1));
    }
  }
  return problems;
}

function objectSchemaProblems(schema, path, defs, refChain, depth) {
  const problems = [];
  if (schema.additionalProperties !== false) {
    problems.push(`${path}: an object needs "additionalProperties": false`);
  }
  if (!isPlainObject(schema.properties)) {
    problems.push(`${path}: an object needs properties`);
    return problems;
  }
  const names = Object.keys(schema.properties);
  const required = Array.isArray(schema.required) ? schema.required : [];
  const missing = [];
  for (const name of names) {
    if (!required.includes(name)) {
      missing.push(name);
    }
  }
  if (missing.length > 0 || required.length !== names.length) {
    problems.push(`${path}: every property must be required (optional ones are nullable); not required: ${missing.join(", ") || "(extra names in required)"}`);
  }
  for (const name of names) {
    problems.push(...schemaNodeProblems(schema.properties[name], `${path}.${name}`, defs, refChain, depth + 1));
  }
  return problems;
}

export function inputSchemaProblems(inputSchema, path = "inputSchema") {
  if (!isPlainObject(inputSchema) || inputSchema.type !== "object") {
    return [`${path} must be an object schema`];
  }
  const defs = inputSchema.$defs;
  if (defs !== undefined && !isPlainObject(defs)) {
    return [`${path}.$defs must be an object`];
  }
  return schemaNodeProblems(inputSchema, path, defs, [], 0);
}

/* ---------- The agent block ---------- */

function escapedForPattern(text) {
  return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// The page still offers a control: as data-action="<name>", as a handler's action === '<name>',
// or as function <name>( for a control without a data-action (a drag, a press-and-hold)
export function pageOffersAction(html, action) {
  const name = escapedForPattern(action);
  const offered = new RegExp(`data-action=["']${name}["']|action === ["']${name}["']|function ${name}\\s*\\(`);
  return offered.test(html);
}

// The page controls a tool names, or [] when it names none
export function pageActionsOf(tool) {
  const actions = isPlainObject(tool) && isPlainObject(tool._meta) ? tool._meta[PAGE_ACTIONS_META_KEY] : undefined;
  return Array.isArray(actions) ? actions : [];
}

function pageActionsProblems(tool, path) {
  const actions = isPlainObject(tool._meta) ? tool._meta[PAGE_ACTIONS_META_KEY] : undefined;
  if (!Array.isArray(actions) || actions.length === 0 || actions.length > MAX_PAGE_ACTIONS) {
    return [`${path}._meta["${PAGE_ACTIONS_META_KEY}"] must name 1 to ${MAX_PAGE_ACTIONS} of the page's controls for this action (only actions a person can take on the page are tools)`];
  }
  for (const action of actions) {
    if (typeof action !== "string" || !PAGE_ACTION_PATTERN.test(action)) {
      return [`${path}._meta["${PAGE_ACTIONS_META_KEY}"] must hold data-action values or page function names`];
    }
  }
  return [];
}

export function wireToolName(toolName) {
  return toolName.replace(".", "__");
}

export function toolVerb(toolName) {
  const dot = toolName.indexOf(".");
  return dot === -1 ? "" : toolName.slice(dot + 1);
}

function toolProblems(tool, index, sidekickId, seenNames) {
  const path = `agent.tools[${index}]`;
  if (!isPlainObject(tool)) {
    return [`${path} must be { name, description, inputSchema }`];
  }
  const problems = [];
  const prefix = `${sidekickId}.`;
  if (typeof tool.name !== "string" || !tool.name.startsWith(prefix) || !VERB_PATTERN.test(tool.name.slice(prefix.length))) {
    problems.push(`${path}.name must be "${sidekickId}.<verb>", the verb in lower case letters, digits and _`);
  } else if (wireToolName(tool.name).length > WIRE_NAME_LIMIT) {
    problems.push(`${path}.name is too long`);
  } else if (seenNames.includes(tool.name)) {
    problems.push(`${path}.name "${tool.name}" is used twice`);
  } else {
    seenNames.push(tool.name);
  }
  if (!isText(tool.description)) {
    problems.push(`${path}.description must be a line of text`);
  }
  for (const key of Object.keys(tool)) {
    if (!["name", "description", "inputSchema", "_meta"].includes(key)) {
      problems.push(`${path}: unknown field "${key}"`);
    }
  }
  problems.push(...inputSchemaProblems(tool.inputSchema, `${path}.inputSchema`));
  if (!isPlainObject(tool._meta)) {
    problems.push(`${path}._meta must be an object`);
  } else {
    problems.push(...pageActionsProblems(tool, path));
    if (tool._meta[WHEN_META_KEY] !== undefined) {
      const property = tool._meta[WHEN_META_KEY];
      const properties = isPlainObject(tool.inputSchema) && isPlainObject(tool.inputSchema.properties) ? tool.inputSchema.properties : {};
      if (typeof property !== "string" || !isPlainObject(properties[property])) {
        problems.push(`${path}._meta["${WHEN_META_KEY}"] must name a property of inputSchema`);
      }
    }
  }
  return problems;
}

// Problems with manifest.json "agent"; empty means valid. A manifest without one has none.
export function agentBlockProblems(agent, sidekickId) {
  if (!isPlainObject(agent)) {
    return ["agent must be { description, rules, notFor, examples, tools }"];
  }
  const problems = [];
  if (!isText(agent.description)) {
    problems.push("agent.description must be a line of text");
  }
  problems.push(...textListProblems(agent.rules, "rules"));
  problems.push(...textListProblems(agent.notFor, "notFor"));
  problems.push(...textListProblems(agent.examples, "examples"));
  if (!Array.isArray(agent.tools) || agent.tools.length === 0 || agent.tools.length > MAX_TOOLS) {
    problems.push(`agent.tools must list 1 to ${MAX_TOOLS} tools`);
    return problems;
  }
  const seenNames = [];
  for (let index = 0; index < agent.tools.length; index += 1) {
    problems.push(...toolProblems(agent.tools[index], index, sidekickId, seenNames));
  }
  return problems;
}

/* ---------- tools.js ---------- */

// The text of every block marked as copied from the page
export function copiedBlocks(toolsText) {
  const blocks = [];
  let searchFrom = 0;
  while (true) {
    const begin = toolsText.indexOf(COPY_BEGIN, searchFrom);
    if (begin === -1) {
      return blocks;
    }
    const contentStart = toolsText.indexOf("\n", begin) + 1;
    const end = toolsText.indexOf(COPY_END, contentStart);
    if (end === -1) {
      blocks.push({ text: null });
      return blocks;
    }
    const contentEnd = toolsText.lastIndexOf("\n", end) + 1;
    blocks.push({ text: toolsText.slice(contentStart, contentEnd) });
    searchFrom = end + COPY_END.length;
  }
}

function firstLine(text) {
  const line = text.split("\n")[0].trim();
  return line.length > 80 ? line.slice(0, 80) + "…" : line;
}

export function copiedBlockProblems(toolsText, html) {
  const problems = [];
  for (const block of copiedBlocks(toolsText)) {
    if (block.text === null) {
      problems.push(`tools.js: a "${COPY_BEGIN}" has no end marker`);
    } else if (!html.includes(block.text)) {
      problems.push(`tools.js: the copied block starting "${firstLine(block.text)}" no longer matches index.html; copy it again from the page`);
    }
  }
  return problems;
}

// Each tool's page controls must be on the page: a tool is only an action the page offers
function pageActionsMissing(agent, html) {
  const problems = [];
  for (const tool of Array.isArray(agent.tools) ? agent.tools : []) {
    for (const action of pageActionsOf(tool)) {
      if (typeof action === "string" && !pageOffersAction(html, action)) {
        problems.push(`manifest.json: ${tool.name} names the page control "${action}", which index.html does not have; a tool is only an action the page offers`);
      }
    }
  }
  return problems;
}

// Runs tools.js in a fresh context with no network and no store, as JavaScriptCore runs it on
// the phone. Returns { tools } or { problem }.
export function loadToolsScript(toolsText) {
  const sandbox = { console: { log() {}, warn() {}, error() {} } };
  vm.createContext(sandbox);
  try {
    vm.runInContext(`${toolsText}\n;globalThis.__tools = typeof ${TOOLS_GLOBAL} === "undefined" ? null : ${TOOLS_GLOBAL};`, sandbox, { timeout: LOAD_TIMEOUT_MS });
  } catch (error) {
    return { problem: `tools.js does not run: ${error && error.message ? error.message : String(error)}` };
  }
  const tools = sandbox.__tools;
  if (tools === null || typeof tools !== "object") {
    return { problem: `tools.js must set the global ${TOOLS_GLOBAL}` };
  }
  return { tools };
}

// Everything wrong with a Sidekick's tools: the agent block, tools.js, and the two together.
// toolsText is null when the Sidekick has no tools.js.
export function sidekickToolsProblems(manifest, toolsText, html, sidekickId) {
  const agent = isPlainObject(manifest) ? manifest.agent : undefined;
  if (agent === undefined && (toolsText === null || toolsText === undefined)) {
    return [];
  }
  if (agent === undefined) {
    return ["tools.js needs an agent block in manifest.json describing its tools"];
  }
  const problems = [];
  for (const agentProblem of agentBlockProblems(agent, sidekickId)) {
    problems.push(`manifest.json: ${agentProblem}`);
  }
  if (toolsText === null || toolsText === undefined) {
    problems.push("manifest.json has agent tools but there is no tools.js");
    return problems;
  }
  for (const forbidden of FORBIDDEN_IN_TOOLS) {
    if (forbidden.pattern.test(toolsText)) {
      problems.push(`tools.js may not use ${forbidden.name}`);
    }
  }
  if (typeof html === "string") {
    problems.push(...copiedBlockProblems(toolsText, html));
    problems.push(...pageActionsMissing(agent, html));
  }
  const loaded = loadToolsScript(toolsText);
  if (loaded.problem) {
    problems.push(loaded.problem);
    return problems;
  }
  const tools = loaded.tools;
  if (typeof tools.context !== "function") {
    problems.push(`tools.js: ${TOOLS_GLOBAL}.context(records, now) is missing`);
  }
  const handlers = tools.handlers;
  if (handlers === null || typeof handlers !== "object") {
    problems.push(`tools.js: ${TOOLS_GLOBAL}.handlers is missing`);
    return problems;
  }
  const declaredVerbs = [];
  for (const tool of Array.isArray(agent.tools) ? agent.tools : []) {
    if (!isPlainObject(tool) || typeof tool.name !== "string") {
      continue;
    }
    const verb = toolVerb(tool.name);
    declaredVerbs.push(verb);
    if (typeof handlers[verb] !== "function") {
      problems.push(`tools.js has no handler for ${tool.name}`);
    }
  }
  for (const verb of Object.keys(handlers)) {
    if (!declaredVerbs.includes(verb)) {
      problems.push(`tools.js handler "${verb}" has no tool in manifest.json agent.tools`);
    }
  }
  return problems;
}
