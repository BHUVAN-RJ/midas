#!/usr/bin/env node
// The repair agent's check command: deploy gate, the shield (runner/core-checks/, when the runner
// gives its inputs) and the Sidekick's tests, against the job's sidekick/ files. Takes no arguments; the job folder and checkout come from the environment the
// runner sets (MIDAS_JOB_FOLDER, MIDAS_RUNNER_CHECKOUT, MIDAS_JOB_SIDEKICK_ID), so the agent
// cannot point it anywhere else.
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { checkRepair, checkSidekick } from "../lib/check.mjs";
import { schemaRuleProblems } from "../lib/schema-change.mjs";

// How many lines of a failing test run the agent sees.
const OUTPUT_TAIL_LINES = 40;

const jobFolder = process.env.MIDAS_JOB_FOLDER;
const checkoutRoot = process.env.MIDAS_RUNNER_CHECKOUT;
const sidekickId = process.env.MIDAS_JOB_SIDEKICK_ID;
if (!jobFolder || !checkoutRoot || !sidekickId) {
  console.error("check: MIDAS_JOB_FOLDER, MIDAS_RUNNER_CHECKOUT and MIDAS_JOB_SIDEKICK_ID must be set");
  process.exit(2);
}

// The schema rules the runner applies after the agent (add only; every literal write declared),
// so the agent hears about them now instead of from a failed job.
const manifestBeforePath = process.env.MIDAS_JOB_MANIFEST_BEFORE;
if (manifestBeforePath && existsSync(manifestBeforePath)) {
  let schemaProblems;
  try {
    schemaProblems = schemaRuleProblems({
      manifestBefore: JSON.parse(readFileSync(manifestBeforePath, "utf8")),
      manifestAfter: JSON.parse(readFileSync(join(jobFolder, "sidekick", "manifest.json"), "utf8")),
      htmlAfter: readFileSync(join(jobFolder, "sidekick", "index.html"), "utf8"),
    });
  } catch (error) {
    schemaProblems = [`manifest.json could not be read: ${error.message}`];
  }
  if (schemaProblems.length > 0) {
    console.log(`check failed: ${schemaProblems.join("; ")}`);
    process.exit(1);
  }
}

// The person's records as a JSON list [{ key, value }]; anything else is a runner fault
function readRecordsFile(recordsPath) {
  const parsed = JSON.parse(readFileSync(recordsPath, "utf8"));
  if (!Array.isArray(parsed)) {
    throw new Error(`${recordsPath} is not a list of records`);
  }
  return parsed;
}

// The shield runs when the runner gives the copy as the job started and the person's records
// (MIDAS_JOB_BEFORE_FOLDER, MIDAS_JOB_RECORDS, both outside the job folder); the runner's own
// final check runs it on every repair either way.
const beforeFolder = process.env.MIDAS_JOB_BEFORE_FOLDER;
const recordsPath = process.env.MIDAS_JOB_RECORDS;
const shieldInputsGiven = Boolean(beforeFolder && recordsPath && existsSync(beforeFolder) && existsSync(recordsPath));

let result;
if (shieldInputsGiven) {
  result = await checkRepair({ checkoutRoot, sidekickId, jobFolder, beforeFolder, records: readRecordsFile(recordsPath) });
} else {
  result = await checkSidekick({ checkoutRoot, sidekickId, jobFolder });
}
if (result.shield) {
  console.log(result.shield.report);
}
if (result.ok) {
  const passedWhat = shieldInputsGiven ? "deploy gate, shield and Sidekick tests" : "deploy gate and Sidekick tests (shield not run here)";
  console.log(`check passed: ${passedWhat}`);
  process.exit(0);
}
console.log(`check failed: ${result.problems.join("; ")}`);
if (result.testOutput) {
  // Only the tail, so the agent never needs to pipe the output: the failing assertions are there.
  const outputLines = result.testOutput.split("\n");
  console.log(outputLines.slice(-OUTPUT_TAIL_LINES).join("\n"));
}
process.exit(1);
