// Runner serves live and staging (founder, 2026-10-21, docs/PRODUCT.md): one runner process polls
// both Workers and runs each job entirely in the environment it came from, one job at a time.
// A job can never read from one environment and write to the other. The old single-environment
// env file keeps working.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createBackendClient } from "../../runner/lib/backend.mjs";
import { BACKEND_HOSTS, parseEnvFile, settingsForEnvironment, settingsFromEnv, startupSettings } from "../../runner/lib/config.mjs";
import { claimFromEnvironments, runLoop } from "../../runner/lib/loop.mjs";
import { jobEnvironment, runJob } from "../../runner/lib/run-job.mjs";
import { claudeEnvironment, codeEnvironment } from "../../runner/lib/safe-env.mjs";
import {
  AGENT_THAT_FIXES_TITLE,
  REPO_ROOT,
  RUNNER_TOKEN,
  fakeDeployThatLands,
  fakeFetchWithoutStoredTests,
  makeScratch,
  standardAssets,
  startFakeBackend,
  writeStubAgent,
  type FakeBackend,
} from "./helpers/runner-fixture";

const LIVE_URL = `https://${BACKEND_HOSTS.live}`;
const STAGING_URL = `https://${BACKEND_HOSTS.staging}`;

const LIVE_ROW = { id: "rep-live-1", user_id: "user-live", sidekick_id: "reminders", bundle_version: "v-live", kind: "bug", transcript: "the title is wrong" };
const STAGING_ROW = { id: "rep-staging-1", user_id: "user-staging", sidekick_id: "reminders", bundle_version: "v-staging", kind: "bug", transcript: "the title is wrong" };

const savedRunnerEnv = process.env.MIDAS_RUNNER_ENV;
const openBackends: FakeBackend[] = [];

afterEach(async () => {
  if (savedRunnerEnv === undefined) {
    delete process.env.MIDAS_RUNNER_ENV;
  } else {
    process.env.MIDAS_RUNNER_ENV = savedRunnerEnv;
  }
  while (openBackends.length > 0) {
    const backend = openBackends.pop();
    await backend?.close();
  }
});

async function fakeBackendServing(jobRow: typeof LIVE_ROW | null): Promise<FakeBackend> {
  const server = await startFakeBackend(jobRow, standardAssets());
  openBackends.push(server);
  return server;
}

function envArgument(args: string[]): string {
  return args[args.indexOf("--env") + 1];
}

describe("the env file: per environment, the old single form, or both", () => {
  it("reads both environments from the per-environment lines, live first", () => {
    const settings = startupSettings({
      MIDAS_STAGING_BACKEND_URL: `${STAGING_URL}/`,
      MIDAS_STAGING_RUNNER_TOKEN: "staging-token",
      MIDAS_LIVE_BACKEND_URL: LIVE_URL,
      MIDAS_LIVE_RUNNER_TOKEN: "live-token",
    });
    expect(settings.environments).toEqual([
      { name: "live", backendUrl: LIVE_URL, runnerToken: "live-token", urlVariable: "MIDAS_LIVE_BACKEND_URL" },
      { name: "staging", backendUrl: STAGING_URL, runnerToken: "staging-token", urlVariable: "MIDAS_STAGING_BACKEND_URL" },
    ]);
  });

  it("keeps the old single-environment file working, for live and for staging", () => {
    const oldLiveFile = parseEnvFile(`MIDAS_BACKEND_URL=${LIVE_URL}\nMIDAS_RUNNER_TOKEN=old-token\nMIDAS_RUNNER_ENV=live\n`);
    const liveSettings = startupSettings(oldLiveFile);
    expect(liveSettings.environments).toEqual([{ name: "live", backendUrl: LIVE_URL, runnerToken: "old-token", urlVariable: "MIDAS_BACKEND_URL" }]);
    expect(liveSettings.backendUrl).toBe(LIVE_URL);
    expect(liveSettings.runnerToken).toBe("old-token");
    expect(liveSettings.deployEnvironment).toBe("live");

    const oldStagingFile = parseEnvFile(`MIDAS_BACKEND_URL=${STAGING_URL}\nMIDAS_RUNNER_TOKEN=old-token\nMIDAS_RUNNER_ENV=staging\n`);
    const stagingSettings = startupSettings(oldStagingFile);
    expect(stagingSettings.environments.length).toBe(1);
    expect(stagingSettings.deployEnvironment).toBe("staging");
    expect(settingsForEnvironment(stagingSettings, "staging").backendUrl).toBe(STAGING_URL);
    expect(() => settingsForEnvironment(stagingSettings, "live")).toThrow(/does not serve live/);
  });

  it("adds the other environment to an old file with two lines", () => {
    const settings = startupSettings({
      MIDAS_BACKEND_URL: LIVE_URL,
      MIDAS_RUNNER_TOKEN: "live-token",
      MIDAS_STAGING_BACKEND_URL: STAGING_URL,
      MIDAS_STAGING_RUNNER_TOKEN: "staging-token",
    });
    const names = settings.environments.map((entry: { name: string }) => entry.name);
    expect(names).toEqual(["live", "staging"]);
    const stagingSettings = settingsForEnvironment(settings, "staging");
    expect(stagingSettings.backendUrl).toBe(STAGING_URL);
    expect(stagingSettings.runnerToken).toBe("staging-token");
    expect(stagingSettings.deployEnvironment).toBe("staging");
    const liveSettings = settingsForEnvironment(settings, "live");
    expect(liveSettings.runnerToken).toBe("live-token");
    expect(liveSettings.deployEnvironment).toBe("live");
  });

  it("refuses a half-set environment, one named twice with different values, and none at all", () => {
    expect(() => settingsFromEnv({ MIDAS_STAGING_BACKEND_URL: STAGING_URL })).toThrow(/MIDAS_STAGING_RUNNER_TOKEN/);
    expect(() => settingsFromEnv({ MIDAS_LIVE_RUNNER_TOKEN: "t" })).toThrow(/MIDAS_LIVE_BACKEND_URL/);
    expect(() => settingsFromEnv({ MIDAS_BACKEND_URL: LIVE_URL, MIDAS_RUNNER_TOKEN: "a", MIDAS_LIVE_BACKEND_URL: LIVE_URL, MIDAS_LIVE_RUNNER_TOKEN: "b" })).toThrow(/live is set twice/);
    expect(settingsFromEnv({ MIDAS_BACKEND_URL: LIVE_URL, MIDAS_RUNNER_TOKEN: "a", MIDAS_LIVE_BACKEND_URL: LIVE_URL, MIDAS_LIVE_RUNNER_TOKEN: "a" }).environments.length).toBe(1);
    expect(() => settingsFromEnv({})).toThrow(/MIDAS_BACKEND_URL is not set/);
  });

  it("refuses to start when an environment's URL is the other environment's Worker", () => {
    expect(() => startupSettings({ MIDAS_STAGING_BACKEND_URL: LIVE_URL, MIDAS_STAGING_RUNNER_TOKEN: "t" })).toThrow(/MIDAS_STAGING_BACKEND_URL .* is the live Worker, not the staging Worker/);
    expect(() => startupSettings({ MIDAS_LIVE_BACKEND_URL: STAGING_URL, MIDAS_LIVE_RUNNER_TOKEN: "t" })).toThrow(/is the staging Worker, not the live Worker/);
    expect(() => startupSettings({ MIDAS_LIVE_BACKEND_URL: "http://127.0.0.1:8787", MIDAS_LIVE_RUNNER_TOKEN: "t" })).toThrow(/neither the live nor the staging Worker/);
    expect(() => startupSettings({ MIDAS_BACKEND_URL: STAGING_URL, MIDAS_RUNNER_TOKEN: "t", MIDAS_STAGING_BACKEND_URL: STAGING_URL, MIDAS_STAGING_RUNNER_TOKEN: "t" })).toThrow(/staging Worker but MIDAS_RUNNER_ENV is live/);
  });

  it("keeps both runner tokens away from the agent and the code it writes", () => {
    const runnerProcess = {
      PATH: "/usr/bin",
      MIDAS_LIVE_RUNNER_TOKEN: "live-token",
      MIDAS_STAGING_RUNNER_TOKEN: "staging-token",
      MIDAS_LIVE_BACKEND_URL: LIVE_URL,
      MIDAS_STAGING_BACKEND_URL: STAGING_URL,
      CLAUDE_CODE_OAUTH_TOKEN: "claude-login",
    };
    for (const visible of [claudeEnvironment(runnerProcess), codeEnvironment(runnerProcess)]) {
      const text = JSON.stringify(visible);
      expect(text).not.toContain("live-token");
      expect(text).not.toContain("staging-token");
      expect(visible.PATH).toBe("/usr/bin");
    }
  });
});

describe("both environments are polled", () => {
  it("claims from live and from staging, tags each job with its environment, and takes turns", async () => {
    const liveServer = await fakeBackendServing(LIVE_ROW);
    const stagingServer = await fakeBackendServing(STAGING_ROW);
    const liveBackend = createBackendClient({ baseUrl: liveServer.baseUrl, token: RUNNER_TOKEN, environment: "live" });
    const stagingBackend = createBackendClient({ baseUrl: stagingServer.baseUrl, token: RUNNER_TOKEN, environment: "staging" });
    const claimNextJob = claimFromEnvironments({ backends: [liveBackend, stagingBackend] });

    const first = await claimNextJob();
    expect(first?.job.id).toBe("rep-live-1");
    expect(first?.job.environment).toBe("live");
    expect(first?.backend).toBe(liveBackend);

    // Live gave the last job, so staging is asked first this time.
    const second = await claimNextJob();
    expect(second?.job.id).toBe("rep-staging-1");
    expect(second?.job.environment).toBe("staging");
    expect(second?.backend).toBe(stagingBackend);
    expect(liveServer.claims).toBe(1);

    expect(await claimNextJob()).toBeNull();
    expect(liveServer.claims).toBe(2);
    expect(stagingServer.claims).toBe(2);
  });

  it("does not let a busy environment keep the other waiting", async () => {
    let liveClaims = 0;
    const alwaysBusyLive = {
      environment: "live",
      claimJob: async () => {
        liveClaims += 1;
        return { id: `live-${liveClaims}`, environment: "live" };
      },
    };
    const stagingServer = await fakeBackendServing(STAGING_ROW);
    const stagingBackend = createBackendClient({ baseUrl: stagingServer.baseUrl, token: RUNNER_TOKEN, environment: "staging" });
    const claimNextJob = claimFromEnvironments({ backends: [alwaysBusyLive, stagingBackend] });
    const firstClaim = await claimNextJob();
    const secondClaim = await claimNextJob();
    const thirdClaim = await claimNextJob();
    expect(firstClaim?.job.id).toBe("live-1");
    expect(secondClaim?.job.id).toBe("rep-staging-1");
    expect(thirdClaim?.job.id).toBe("live-2");
  });

  it("still asks staging when live cannot be reached, and says which one failed", async () => {
    const downLive = {
      environment: "live",
      claimJob: async () => {
        throw new Error("claim failed: 503");
      },
    };
    const stagingServer = await fakeBackendServing(STAGING_ROW);
    const stagingBackend = createBackendClient({ baseUrl: stagingServer.baseUrl, token: RUNNER_TOKEN, environment: "staging" });
    const errors: string[] = [];
    const claimNextJob = claimFromEnvironments({
      backends: [downLive, stagingBackend],
      onError: (error: Error) => {
        errors.push(error.message);
      },
    });
    const claimed = await claimNextJob();
    expect(claimed?.job.id).toBe("rep-staging-1");
    expect(errors).toEqual(["live: claim failed: 503"]);
  });

  it("runs one job at a time across both environments", async () => {
    const liveServer = await fakeBackendServing(LIVE_ROW);
    const stagingServer = await fakeBackendServing(STAGING_ROW);
    const backends = [
      createBackendClient({ baseUrl: liveServer.baseUrl, token: RUNNER_TOKEN, environment: "live" }),
      createBackendClient({ baseUrl: stagingServer.baseUrl, token: RUNNER_TOKEN, environment: "staging" }),
    ];
    let running = 0;
    let mostAtOnce = 0;
    const ranJobs: string[] = [];
    let idlePolls = 0;
    await runLoop({
      claimJob: claimFromEnvironments({ backends }),
      runJob: async (claimed: { job: { id: string; environment: string } }) => {
        running += 1;
        mostAtOnce = Math.max(mostAtOnce, running);
        await new Promise((resolve) => setTimeout(resolve, 5));
        ranJobs.push(`${claimed.job.environment}:${claimed.job.id}`);
        running -= 1;
      },
      pollIntervalMs: 1,
      sleep: async () => {
        idlePolls += 1;
      },
      shouldStop: () => idlePolls >= 1,
    });
    expect(ranJobs).toEqual(["live:rep-live-1", "staging:rep-staging-1"]);
    expect(mostAtOnce).toBe(1);
  });

  it("is how both runner commands claim and run a job", () => {
    for (const binary of ["runner/bin/runner.mjs", "runner/bin/run-once.mjs"]) {
      const source = readFileSync(join(REPO_ROOT, binary), "utf8");
      expect(source).toContain("const settings = startupSettings();");
      expect(source).toContain("settings.environments.map(backendFor)");
      expect(source).toContain("environment: environmentEntry.name");
      expect(source).toContain("claimFromEnvironments({ backends");
      expect(source).toContain("settingsForEnvironment(settings, job.environment)");
      expect(source).not.toContain("backendUrl: settings.backendUrl");
    }
  });
});

// A staging job run end to end with MIDAS_RUNNER_ENV unset (which alone would mean live): every
// step must still use staging.
async function runStagingJob(jobSettingsName: "staging" | "live") {
  delete process.env.MIDAS_RUNNER_ENV;
  const { scratch, settings: scratchSettings } = makeScratch();
  const liveServer = await fakeBackendServing(null);
  const stagingServer = await fakeBackendServing(STAGING_ROW);
  const settings = {
    ...scratchSettings,
    environments: [
      { name: "live", backendUrl: liveServer.baseUrl, runnerToken: RUNNER_TOKEN, urlVariable: "MIDAS_LIVE_BACKEND_URL" },
      { name: "staging", backendUrl: stagingServer.baseUrl, runnerToken: RUNNER_TOKEN, urlVariable: "MIDAS_STAGING_BACKEND_URL" },
    ],
  };
  const stagingBackend = createBackendClient({ baseUrl: stagingServer.baseUrl, token: RUNNER_TOKEN, environment: "staging" });
  const claimed = await claimFromEnvironments({ backends: [stagingBackend] })();
  const fetch = fakeFetchWithoutStoredTests();
  const deploy = fakeDeployThatLands();
  const pointerReads: Array<{ environmentName?: string }> = [];
  const notifications: Array<{ title: string; body: string }> = [];
  const runResult = runJob(claimed!.job, {
    backend: claimed!.backend,
    settings: settingsForEnvironment(settings, jobSettingsName),
    agentCommand: process.execPath,
    agentArgs: [writeStubAgent(scratch, AGENT_THAT_FIXES_TITLE)],
    runFetch: fetch.runFetch,
    runTests: async () => ({ ok: true, output: "81 passed" }),
    runDeploy: deploy.runDeploy,
    readPointer: async (request: { environmentName?: string }) => {
      pointerReads.push(request);
      return deploy.readPointer();
    },
    notify: async (notification: { title: string; body: string }) => {
      notifications.push(notification);
    },
  });
  return { runResult, liveServer, stagingServer, fetch, deploy, pointerReads, notifications, scratchSettings };
}

describe("a job is handled entirely in its own environment", () => {
  it("fetches, deploys, reads back, reports and posts on staging for a staging job", async () => {
    const { runResult, liveServer, stagingServer, fetch, deploy, pointerReads, notifications, scratchSettings } = await runStagingJob("staging");
    const result = await runResult;
    expect(result.status).toBe("deployed_live");
    expect(fetch.calls.length).toBe(1);
    expect(envArgument(fetch.calls[0].args)).toBe("staging");
    expect(deploy.deployCalls.length).toBe(1);
    expect(envArgument(deploy.deployCalls[0].args)).toBe("staging");
    expect(pointerReads.map((read) => read.environmentName)).toEqual(["staging"]);
    const summary = readFileSync(join(String(scratchSettings.logsRoot), "rep-staging-1", "summary.md"), "utf8");
    expect(summary).toContain("- Environment: staging");
    expect(summary).toContain("--env staging --user user-staging --from-base");
    expect(summary).not.toContain("--env live");
    expect(notifications[1].body).toContain("on staging for user-staging");
    const stagingStatuses = stagingServer.statuses.map((status) => status.status);
    expect(stagingStatuses).toContain("running");
    expect(stagingStatuses).toContain("fix_ready");
    expect(stagingStatuses).toContain("deployed_live");
    expect(stagingServer.recordRequests).toBeGreaterThan(0);
    expect(liveServer.statuses).toEqual([]);
    expect(liveServer.recordRequests).toBe(0);
    expect(liveServer.assetRequests).toEqual([]);
  });

  it("refuses a staging job given live settings, before reading or posting anything", async () => {
    const { runResult, liveServer, stagingServer, fetch, deploy } = await runStagingJob("live");
    await expect(runResult).rejects.toThrow(/refusing job rep-staging-1: the job was claimed from staging but the job would publish to live/);
    expect(stagingServer.statuses).toEqual([]);
    expect(stagingServer.assetRequests).toEqual([]);
    expect(liveServer.statuses).toEqual([]);
    expect(fetch.calls).toEqual([]);
    expect(deploy.deployCalls).toEqual([]);
  });

  it("refuses when the job, the backend client and the settings do not all name one environment", () => {
    const stagingSettings = { deployEnvironment: "staging", backendUrl: STAGING_URL };
    expect(jobEnvironment({ job: { id: "r", environment: "staging" }, backend: { environment: "staging" }, settings: stagingSettings })).toBe("staging");
    expect(() => jobEnvironment({ job: { id: "r", environment: "staging" }, backend: { environment: "live" }, settings: stagingSettings })).toThrow(/the backend client is live but the job would publish to staging/);
    expect(() => jobEnvironment({ job: { id: "r", environment: "live" }, backend: { environment: "staging" }, settings: stagingSettings })).toThrow(/claimed from live/);
    expect(() => jobEnvironment({ job: { id: "r", environment: "staging" }, backend: { environment: "staging" }, settings: { deployEnvironment: "staging", backendUrl: LIVE_URL } })).toThrow(/the backend URL is live/);
  });
});
