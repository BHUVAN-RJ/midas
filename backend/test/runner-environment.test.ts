import { afterEach, describe, expect, it } from "vitest";
import { runnerEnvironment, settingsFromEnv } from "../../runner/lib/config.mjs";
import { deployArgs } from "../../runner/lib/deploy.mjs";
import { fetchArgs } from "../../runner/lib/copy-tests.mjs";
import { resetToBaseCommand } from "../../runner/lib/summary.mjs";

// "Midas Test" (founder, 2026-10-14) runs on staging, so a runner serving it must read and publish
// staging copies. MIDAS_RUNNER_ENV picks the server; unset means live, as before.

const savedRunnerEnv = process.env.MIDAS_RUNNER_ENV;

afterEach(() => {
  if (savedRunnerEnv === undefined) {
    delete process.env.MIDAS_RUNNER_ENV;
  } else {
    process.env.MIDAS_RUNNER_ENV = savedRunnerEnv;
  }
});

function envArgument(args: string[]): string {
  const flagIndex = args.indexOf("--env");
  return args[flagIndex + 1];
}

const job = { sidekickId: "reminders", userId: "user-1" };

describe("runner environment", () => {
  it("is live when MIDAS_RUNNER_ENV is not set", () => {
    delete process.env.MIDAS_RUNNER_ENV;
    expect(runnerEnvironment()).toBe("live");
    expect(envArgument(deployArgs({ ...job, deployFolder: "/tmp/x" }))).toBe("live");
    expect(envArgument(fetchArgs({ ...job, outFolder: "/tmp/y" }))).toBe("live");
    expect(resetToBaseCommand(job)).toContain("--env live");
  });

  it("publishes, fetches and resets staging copies when set to staging", () => {
    process.env.MIDAS_RUNNER_ENV = "staging";
    expect(envArgument(deployArgs({ ...job, deployFolder: "/tmp/x" }))).toBe("staging");
    expect(envArgument(fetchArgs({ ...job, outFolder: "/tmp/y" }))).toBe("staging");
    expect(resetToBaseCommand(job)).toContain("--env staging");
  });

  it("refuses any other value", () => {
    expect(() => runnerEnvironment({ MIDAS_RUNNER_ENV: "prod" })).toThrow(/live or staging/);
    expect(() => settingsFromEnv({ MIDAS_BACKEND_URL: "https://x", MIDAS_RUNNER_TOKEN: "t", MIDAS_RUNNER_ENV: "prod" })).toThrow(/live or staging/);
  });

  it("is part of the settings", () => {
    const settings = settingsFromEnv({ MIDAS_BACKEND_URL: "https://x", MIDAS_RUNNER_TOKEN: "t", MIDAS_RUNNER_ENV: "staging" });
    expect(settings.deployEnvironment).toBe("staging");
  });
});
