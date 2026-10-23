#!/usr/bin/env node
// Claims at most one job and runs it, then exits. For trying the runner by hand.
import { createBackendClient } from "../lib/backend.mjs";
import { loadEnvFile, startupSettings } from "../lib/config.mjs";
import { runJob } from "../lib/run-job.mjs";
import { requireWorkingSandbox } from "../lib/sandbox.mjs";

loadEnvFile();
const settings = startupSettings();
// The agent's tests run under the macOS sandbox; without a working one the runner does not start.
await requireWorkingSandbox();
const backend = createBackendClient({ baseUrl: settings.backendUrl, token: settings.runnerToken });

const job = await backend.claimJob();
if (job === null) {
  console.log("no job waiting");
  process.exit(0);
}
console.log(`job ${job.id} (${job.sidekickId}, user ${job.userId})`);
const result = await runJob(job, { backend, settings });
console.log(JSON.stringify(result, null, 2));
process.exit(result.status === "fix_ready" ? 0 : 1);
