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
