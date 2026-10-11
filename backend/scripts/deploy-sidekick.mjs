// Usage, from backend/: node scripts/deploy-sidekick.mjs <sidekick-id> --env staging|live
// Uploads ../sidekicks/<id>/index.html and manifest.json to R2 as a new immutable version, then
// moves the current.json pointer to it. Old versions stay in R2. Live refuses unless staging
// already runs exactly this page and manifest.
import { readFileSync, writeFileSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  bundleContentHash,
  bundleVersion,
  findForbiddenPrimitives,
  inlineScriptHashes,
  liveDeployRefusal,
  validateManifest,
} from "./bundle-tools.mjs";
import { ENVIRONMENTS, environmentFromArgs, positionalArgs } from "./environments.mjs";
import { rowsFromWranglerJson } from "./db-tools.mjs";
import { captureWrangler, runWrangler } from "./wrangler.mjs";

function stop(message) {
  console.error(message);
  process.exit(1);
}

const commandArgs = process.argv.slice(2);
const environment = environmentFromArgs(commandArgs);
const [sidekickId] = positionalArgs(commandArgs);
if (environment === null || !sidekickId || !/^[a-z0-9-]{1,40}$/.test(sidekickId)) {
  stop("usage: node scripts/deploy-sidekick.mjs <sidekick-id> --env staging|live");
}

const sidekickDirectory = new URL(`../../sidekicks/${sidekickId}/`, import.meta.url);
const htmlPath = new URL("index.html", sidekickDirectory);
const manifestPath = new URL("manifest.json", sidekickDirectory);
const html = readFileSync(htmlPath, "utf8");
const manifestText = readFileSync(manifestPath, "utf8");

const violations = findForbiddenPrimitives(html);
if (violations.length > 0) {
  stop(`deploy gate rejected ${sidekickId}: ${violations.join(", ")}`);
}

let manifest;
try {
  manifest = JSON.parse(manifestText);
} catch {
  stop(`${sidekickId}/manifest.json is not JSON`);
}
const manifestProblems = validateManifest(manifest, sidekickId);
if (manifestProblems.length > 0) {
  stop(`${sidekickId}/manifest.json: ${manifestProblems.join("; ")}`);
}

const contentHash = bundleContentHash(html, manifestText);

// Reads staging's current.json; null if staging has never had this Sidekick.
function readStagingPointer() {
  const objectPath = `${ENVIRONMENTS.staging.bucket}/sidekicks/${sidekickId}/current.json`;
  try {
    const pointerText = captureWrangler(["r2", "object", "get", objectPath, "--pipe", "--remote"]);
    return JSON.parse(pointerText);
  } catch {
    return null;
  }
}

if (environment.name === "live") {
  const refusal = liveDeployRefusal(readStagingPointer(), contentHash);
  if (refusal !== null) {
    stop(`live deploy refused: ${refusal}`);
  }
}

// The op-log sequence at deploy time (D5), so code and data can be rolled back together. Null
// if the ops table does not exist yet in this environment.
function readCurrentSeq() {
  const sql = "SELECT COALESCE(MAX(seq), 0) AS seq FROM ops";
  try {
    const outputText = captureWrangler(["d1", "execute", environment.database, "--remote", "--json", "--command", sql, ...environment.wranglerEnvArgs]);
    const rows = rowsFromWranglerJson(outputText);
    return rows[0]?.seq ?? null;
  } catch {
    return null;
  }
}

const deployedAtSeq = readCurrentSeq();
const deployedAt = new Date();
const version = bundleVersion(html, deployedAt);
const scriptHashes = inlineScriptHashes(html);
const pointer = { version, scriptHashes, contentHash };
const versionRecord = { version, scriptHashes, contentHash, deployedAt: deployedAt.toISOString(), deployedAtSeq };

const scratchDirectory = mkdtempSync(join(tmpdir(), "sidekick-"));
const pointerPath = join(scratchDirectory, "current.json");
const versionRecordPath = join(scratchDirectory, "version.json");
writeFileSync(pointerPath, JSON.stringify(pointer));
writeFileSync(versionRecordPath, JSON.stringify(versionRecord));

function putObject(key, filePath, contentType) {
  const objectPath = `${environment.bucket}/${key}`;
  runWrangler(["r2", "object", "put", objectPath, "--file", filePath, "--content-type", contentType, "--remote"]);
}

// The version's files go up before the pointer moves, so the pointer never names a missing file.
const versionPrefix = `sidekicks/${sidekickId}/${version}`;
putObject(`${versionPrefix}/index.html`, htmlPath.pathname, "text/html; charset=utf-8");
putObject(`${versionPrefix}/manifest.json`, manifestPath.pathname, "application/json");
putObject(`${versionPrefix}/version.json`, versionRecordPath, "application/json");
putObject(`sidekicks/${sidekickId}/current.json`, pointerPath, "application/json");
console.log(`deployed ${sidekickId} ${version} to ${environment.name} with ${scriptHashes.length} script hash(es)`);
