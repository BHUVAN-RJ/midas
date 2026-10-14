#!/usr/bin/env node
// The repair agent's check command: deploy gate plus the Sidekick's tests, against the job's
// sidekick/ files. Takes no arguments; the job folder and checkout come from the environment the
// runner sets (MIDAS_JOB_FOLDER, MIDAS_RUNNER_CHECKOUT, MIDAS_JOB_SIDEKICK_ID), so the agent
// cannot point it anywhere else.
import { checkSidekick } from "../lib/check.mjs";

const jobFolder = process.env.MIDAS_JOB_FOLDER;
const checkoutRoot = process.env.MIDAS_RUNNER_CHECKOUT;
const sidekickId = process.env.MIDAS_JOB_SIDEKICK_ID;
if (!jobFolder || !checkoutRoot || !sidekickId) {
  console.error("check: MIDAS_JOB_FOLDER, MIDAS_RUNNER_CHECKOUT and MIDAS_JOB_SIDEKICK_ID must be set");
  process.exit(2);
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
