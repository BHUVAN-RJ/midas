// Primitive block checks (docs/briefs/repair-lanes.md W1; founder D3, 2026-11-13): where a
// primitive (docs/primitives/<primitive>/) defines block checks, they run on every repair of a
// Sidekick built from it. Loaded from the platform checkout, like every core check.
//
// The format (no primitive has machine checks yet; the blocks' "Tests." sections are prose):
//
//   docs/primitives/<primitive>/checks/<anything>.mjs
//     export const sidekicks = ["todo"];               // the Sidekicks built from this primitive
//     export const checks = [
//       { id: "TD-SET-01", run({ sidekickId, html, manifest, toolsText, records }) { return []; } },
//     ];                                               // run returns problem texts; [] = passes
//
// A check that throws fails with what it threw. A file that does not load fails the shield: a
// broken core check must never read as a pass.
import { existsSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const PRIMITIVES_FOLDER = join("docs", "primitives");
const CHECKS_FOLDER = "checks";

// Every check file in the checkout: [{ primitive, path }]
export function blockCheckFiles(checkoutRoot) {
  const primitivesRoot = join(checkoutRoot, PRIMITIVES_FOLDER);
  if (!existsSync(primitivesRoot)) {
    return [];
  }
  const files = [];
  const primitiveEntries = readdirSync(primitivesRoot, { withFileTypes: true });
  for (const primitiveEntry of primitiveEntries) {
    if (!primitiveEntry.isDirectory()) {
      continue;
    }
    const checksRoot = join(primitivesRoot, primitiveEntry.name, CHECKS_FOLDER);
    if (!existsSync(checksRoot)) {
      continue;
    }
    const checkNames = readdirSync(checksRoot).filter(function isModule(fileName) {
      return fileName.endsWith(".mjs");
    });
    checkNames.sort();
    for (const checkName of checkNames) {
      files.push({ primitive: primitiveEntry.name, path: join(checksRoot, checkName) });
    }
  }
  return files;
}

function errorText(error) {
  return error && error.message ? error.message : String(error);
}

async function runOneCheck({ primitive, check, copy }) {
  const label = `${primitive} ${check.id ?? "(no id)"}`;
  if (typeof check.run !== "function") {
    return [`${label}: has no run function`];
  }
  try {
    const found = await check.run(copy);
    if (!Array.isArray(found)) {
      return [`${label}: run must return a list of problems`];
    }
    return found.map(function labelled(problem) {
      return `${label}: ${problem}`;
    });
  } catch (error) {
    return [`${label}: threw ${errorText(error)}`];
  }
}

// copy: { sidekickId, html, manifest, toolsText, records }. Returns { problems, notes }.
export async function checkPrimitiveBlocks({ checkoutRoot, copy }) {
  const problems = [];
  const notes = [];
  let ran = 0;
  for (const file of blockCheckFiles(checkoutRoot)) {
    let checkModule;
    try {
      checkModule = await import(pathToFileURL(file.path).href);
    } catch (error) {
      problems.push(`${file.primitive}: ${file.path} does not load: ${errorText(error)}`);
      continue;
    }
    const sidekicks = Array.isArray(checkModule.sidekicks) ? checkModule.sidekicks : [];
    if (!sidekicks.includes(copy.sidekickId)) {
      continue;
    }
    const checks = Array.isArray(checkModule.checks) ? checkModule.checks : [];
    for (const check of checks) {
      ran += 1;
      problems.push(...(await runOneCheck({ primitive: file.primitive, check, copy })));
    }
  }
  if (ran === 0) {
    notes.push(`no primitive block checks apply to ${copy.sidekickId}`);
  } else {
    notes.push(`${ran} primitive block checks ran`);
  }
  return { problems, notes };
}
