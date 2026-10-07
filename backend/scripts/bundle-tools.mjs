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
