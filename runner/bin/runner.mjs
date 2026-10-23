#!/usr/bin/env node
// The Mac mini runner. Started by launchd (runner/install.sh) through runner/bin/start.sh, or by
// hand: `node runner/bin/runner.mjs`. Settings: ~/.midas-runner/env (see runner/README.md).
import { createBackendClient } from "../lib/backend.mjs";
import { loadEnvFile, startupSettings } from "../lib/config.mjs";
import { runLoop, sleepMs } from "../lib/loop.mjs";
import { runJob } from "../lib/run-job.mjs";
import { requireWorkingSandbox } from "../lib/sandbox.mjs";

loadEnvFile();
const settings = startupSettings();
// The agent's tests run under the macOS sandbox; without a working one the runner does not start.
await requireWorkingSandbox();
const backend = createBackendClient({ baseUrl: settings.backendUrl, token: settings.runnerToken });

let stopping = false;
function requestStop() {
  stopping = true;
  console.log("runner: stopping after the current job");
}
process.on("SIGTERM", requestStop);
process.on("SIGINT", requestStop);

console.log(`runner: polling ${settings.backendUrl} every ${settings.pollIntervalMs} ms; jobs in ${settings.jobsRoot}`);

await runLoop({
  claimJob: backend.claimJob,
  runJob: function runOneJob(job) {
    console.log(`runner: job ${job.id} (${job.sidekickId}, user ${job.userId})`);
    return runJob(job, { backend, settings }).then(function logResult(result) {
      console.log(`runner: job ${job.id} ${result.status}${result.reason ? `: ${result.reason}` : ""}`);
    });
  },
  pollIntervalMs: settings.pollIntervalMs,
  sleep: sleepMs,
  shouldStop: () => stopping,
  onError: function logError(error) {
    console.error(`runner: ${error.message}`);
  },
});
