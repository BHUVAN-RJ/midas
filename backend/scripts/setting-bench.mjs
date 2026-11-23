// Setting-lane benchmark (founder, 2026-11-22): do vague words ("change the color to red", "make it
// darker", "bigger text", "make it pop") stay in the setting lane? Sends every case of
// setting-golden.json to the Worker's own setting call (src/repair-setting-model.ts: the same prompt,
// model and checks) with the Sidekick's catalogue from sidekicks/<id>/manifest.json, and says which
// cases changed an accepted key. This calls OpenRouter for real and costs money; the unit test
// (test/repair-setting-vague-words.test.ts) checks the same set with no network.
//
// Usage (the key comes from OPENROUTER_API_KEY or ~/.openrouter-key):
//   cd ~/Desktop/Midas/midas/backend && node scripts/setting-bench.mjs
//   cd ~/Desktop/Midas/midas/backend && node scripts/setting-bench.mjs --only todo
// Results are printed, never written into the repo.

import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { mapSetting, settingCallSettings } from "../src/repair-setting-model.ts";

const GOLDEN_URL = new URL("./setting-golden.json", import.meta.url);

function readApiKey() {
  if (process.env.OPENROUTER_API_KEY) {
    return process.env.OPENROUTER_API_KEY;
  }
  const keyPath = join(homedir(), ".openrouter-key");
  return existsSync(keyPath) ? readFileSync(keyPath, "utf8").trim() : "";
}

function catalogueOf(sidekickId) {
  const manifestUrl = new URL(`../../sidekicks/${sidekickId}/manifest.json`, import.meta.url);
  const manifestText = readFileSync(manifestUrl, "utf8");
  return JSON.parse(manifestText).settings;
}

function onlyFilter() {
  const flagIndex = process.argv.indexOf("--only");
  return flagIndex === -1 ? null : process.argv[flagIndex + 1];
}

function changedKeysOf(mapping) {
  return mapping.changes.map(function keyOf(change) {
    return `${change.key}=${String(change.value)}`;
  });
}

function hitsAccepted(mapping, accept) {
  return mapping.changes.some(function isAccepted(change) {
    return accept.includes(change.key);
  });
}

async function runCase(goldenCase, apiKey) {
  const request = { words: goldenCase.words, sidekickName: goldenCase.sidekick, drawing: "nothing", catalogue: catalogueOf(goldenCase.sidekick), record: null };
  const mapping = await mapSetting(request, apiKey, fetch);
  const passed = mapping.ok && hitsAccepted(mapping, goldenCase.accept);
  const outcome = mapping.ok ? changedKeysOf(mapping).join(", ") : `up to code: ${mapping.reason}`;
  return { passed, outcome, latencyMs: mapping.latencyMs, costUsd: mapping.costUsd };
}

async function main() {
  const apiKey = readApiKey();
  if (apiKey.length === 0) {
    console.error("No key: set OPENROUTER_API_KEY or write it to ~/.openrouter-key");
    process.exit(1);
  }
  // The Worker gives the call 6 s; a benchmark run from a laptop gets more room
  settingCallSettings.timeoutMs = 20000;
  const golden = JSON.parse(readFileSync(GOLDEN_URL, "utf8"));
  const only = onlyFilter();
  const cases = golden.cases.filter(function matchesOnly(goldenCase) {
    return only === null || goldenCase.sidekick === only;
  });
  let passedCount = 0;
  let totalCost = 0;
  for (const goldenCase of cases) {
    const result = await runCase(goldenCase, apiKey);
    if (result.passed) {
      passedCount += 1;
    }
    totalCost += result.costUsd;
    const mark = result.passed ? "PASS" : "FAIL";
    console.log(`${mark}  ${goldenCase.sidekick.padEnd(15)} "${goldenCase.words}"  ->  ${result.outcome}  (${result.latencyMs} ms; want ${goldenCase.accept.join(" or ")})`);
  }
  console.log(`\n${passedCount}/${cases.length} stayed in the setting lane on an accepted key; cost $${totalCost.toFixed(4)}`);
}

await main();
