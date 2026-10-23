#!/usr/bin/env node
// The Mac mini runner. Started by launchd (runner/install.sh) through runner/bin/start.sh, or by
// hand: `node runner/bin/runner.mjs`. Settings: ~/.midas-runner/env (see runner/README.md).
// One process serves every environment the env file names (live and staging, founder
// 2026-10-21), one job at a time; each job runs entirely in the environment it came from.
import { createBackendClient } from "../lib/backend.mjs";
import { loadEnvFile, settingsForEnvironment, startupSettings } from "../lib/config.mjs";
import { claimFromEnvironments, runLoop, sleepMs } from "../lib/loop.mjs";
import { runJob } from "../lib/run-job.mjs";
import { requireWorkingSandbox } from "../lib/sandbox.mjs";

loadEnvFile();
const settings = startupSettings();
// The agent's tests run under the macOS sandbox; without a working one the runner does not start.
await requireWorkingSandbox();

function backendFor(environmentEntry) {
  return createBackendClient({ baseUrl: environmentEntry.backendUrl, token: environmentEntry.runnerToken, environment: environmentEntry.name });
}

const backends = settings.environments.map(backendFor);

let stopping = false;
function requestStop() {
  stopping = true;
  console.log("runner: stopping after the current job");
}
process.on("SIGTERM", requestStop);
process.on("SIGINT", requestStop);

function logError(error) {
  console.error(`runner: ${error.message}`);
}

for (const environmentEntry of settings.environments) {
  console.log(`runner: polling ${environmentEntry.name} ${environmentEntry.backendUrl} every ${settings.pollIntervalMs} ms`);
}
console.log(`runner: jobs in ${settings.jobsRoot}`);

await runLoop({
  claimJob: claimFromEnvironments({ backends, onError: logError }),
  runJob: function runOneJob(claimed) {
    const { job, backend } = claimed;
    console.log(`runner: job ${job.id} on ${job.environment} (${job.sidekickId}, user ${job.userId})`);
    const jobSettings = settingsForEnvironment(settings, job.environment);
    return runJob(job, { backend, settings: jobSettings }).then(function logResult(result) {
      console.log(`runner: job ${job.id} ${result.status}${result.reason ? `: ${result.reason}` : ""}`);
    });
  },
  pollIntervalMs: settings.pollIntervalMs,
  sleep: sleepMs,
  shouldStop: () => stopping,
  onError: logError,
});
