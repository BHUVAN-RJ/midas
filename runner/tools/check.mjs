#!/usr/bin/env node
// The repair agent's check command: deploy gate plus the Sidekick's tests, against the job's
// sidekick/ files. Takes no arguments; the job folder and checkout come from the environment the
// runner sets (MIDAS_JOB_FOLDER, MIDAS_RUNNER_CHECKOUT, MIDAS_JOB_SIDEKICK_ID), so the agent
// cannot point it anywhere else.
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { checkSidekick } from "../lib/check.mjs";
import { schemaRuleProblems } from "../lib/schema-change.mjs";

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

const result = await checkSidekick({ checkoutRoot, sidekickId, jobFolder });
if (result.ok) {
  console.log("check passed: deploy gate and Sidekick tests");
  process.exit(0);
}
console.log(`check failed: ${result.problems.join("; ")}`);
if (result.testOutput) {
  // Only the tail: the agent needs the failing assertions, not the whole run.
  const outputLines = result.testOutput.split("\n");
  console.log(outputLines.slice(-80).join("\n"));
}
process.exit(1);
