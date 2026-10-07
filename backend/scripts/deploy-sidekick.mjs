// Usage, from backend/: node scripts/deploy-sidekick.mjs <sidekick-id>
// Uploads ../sidekicks/<id>/index.html to R2 as a new immutable version, then moves the
// current.json pointer to it. Old versions stay in R2.
import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { bundleVersion, findForbiddenPrimitives, inlineScriptHashes } from "./bundle-tools.mjs";

const BUCKET = "midas-bundles";
const sidekickId = process.argv[2];
if (!sidekickId || !/^[a-z0-9-]{1,40}$/.test(sidekickId)) {
  console.error("usage: node scripts/deploy-sidekick.mjs <sidekick-id>");
  process.exit(1);
}

const htmlPath = new URL(`../../sidekicks/${sidekickId}/index.html`, import.meta.url);
const html = readFileSync(htmlPath, "utf8");

const violations = findForbiddenPrimitives(html);
if (violations.length > 0) {
  console.error(`deploy gate rejected ${sidekickId}: ${violations.join(", ")}`);
  process.exit(1);
}

const version = bundleVersion(html, new Date());
const pointer = { version, scriptHashes: inlineScriptHashes(html) };
const pointerPath = join(mkdtempSync(join(tmpdir(), "sidekick-")), "current.json");
writeFileSync(pointerPath, JSON.stringify(pointer));

function putObject(key, filePath, contentType) {
  const wranglerArgs = ["wrangler", "r2", "object", "put", `${BUCKET}/${key}`, "--file", filePath,
    "--content-type", contentType, "--remote"];
  execFileSync("npx", wranglerArgs, { stdio: "inherit" });
}

// The version goes up before the pointer moves, so the pointer never names a missing file.
putObject(`sidekicks/${sidekickId}/${version}/index.html`, htmlPath.pathname, "text/html; charset=utf-8");
putObject(`sidekicks/${sidekickId}/current.json`, pointerPath, "application/json");
console.log(`deployed ${sidekickId} ${version} with ${pointer.scriptHashes.length} script hash(es)`);
