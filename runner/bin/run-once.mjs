#!/usr/bin/env node
// Claims at most one job, from any environment the env file names, and runs it in that
// environment, then exits. For trying the runner by hand.
import { createBackendClient } from "../lib/backend.mjs";
import { loadEnvFile, settingsForEnvironment, startupSettings } from "../lib/config.mjs";
import { claimFromEnvironments } from "../lib/loop.mjs";
import { runJob } from "../lib/run-job.mjs";
import { requireWorkingSandbox } from "../lib/sandbox.mjs";

loadEnvFile();
const settings = startupSettings();
// The agent's tests run under the macOS sandbox; without a working one the runner does not start.
await requireWorkingSandbox();

function backendFor(environmentEntry) {
  return createBackendClient({ baseUrl: environmentEntry.backendUrl, token: environmentEntry.runnerToken, environment: environmentEntry.name });
}

function logError(error) {
  console.error(error.message);
}

const backends = settings.environments.map(backendFor);
const claimNextJob = claimFromEnvironments({ backends, onError: logError });
const claimed = await claimNextJob();
if (claimed === null) {
  console.log("no job waiting");
  process.exit(0);
}
const { job, backend } = claimed;
console.log(`job ${job.id} on ${job.environment} (${job.sidekickId}, user ${job.userId})`);
const result = await runJob(job, { backend, settings: settingsForEnvironment(settings, job.environment) });
console.log(JSON.stringify(result, null, 2));
process.exit(result.status === "fix_ready" ? 0 : 1);
