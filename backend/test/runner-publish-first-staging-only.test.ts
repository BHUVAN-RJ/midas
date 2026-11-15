// Publish first is staging only until the founder says live (founder, 2026-11-14; brief
// docs/briefs/repair-lanes.md, "STAGING ONLY"). One runner serves live and staging, so the mode is
// per environment: staging publishes first by default, live keeps the earlier way (every check,
// then deploy-sidekick.mjs) and is not long-polled, since live's Worker has no new routes.
import { describe, expect, it } from "vitest";
import {
  PUBLISH_FIRST,
  PUBLISH_WITH_WRANGLER,
  longPollBackends,
  settingsForEnvironment,
  settingsFromEnv,
} from "../../runner/lib/config.mjs";

const BOTH_ENVIRONMENTS = {
  MIDAS_LIVE_BACKEND_URL: "https://midas-api.midas-backend.workers.dev",
  MIDAS_LIVE_RUNNER_TOKEN: "live-token",
  MIDAS_STAGING_BACKEND_URL: "https://midas-api-staging.midas-backend.workers.dev",
  MIDAS_STAGING_RUNNER_TOKEN: "staging-token",
};

function fakeBackend(environment: string) {
  return { environment };
}

describe("publish mode per environment", () => {
  it("publishes first on staging and the earlier way on live, by default", () => {
    const settings = settingsFromEnv(BOTH_ENVIRONMENTS);
    expect(settings.publishModes).toEqual({ live: PUBLISH_WITH_WRANGLER, staging: PUBLISH_FIRST });
    expect(settingsForEnvironment(settings, "live").publishMode).toBe(PUBLISH_WITH_WRANGLER);
    expect(settingsForEnvironment(settings, "staging").publishMode).toBe(PUBLISH_FIRST);
  });

  it("a staging-only runner publishes first; a live-only runner does not", () => {
    const stagingOnly = settingsFromEnv({
      MIDAS_STAGING_BACKEND_URL: BOTH_ENVIRONMENTS.MIDAS_STAGING_BACKEND_URL,
      MIDAS_STAGING_RUNNER_TOKEN: "staging-token",
    });
    expect(stagingOnly.publishMode).toBe(PUBLISH_FIRST);
    const liveOnly = settingsFromEnv({ MIDAS_BACKEND_URL: BOTH_ENVIRONMENTS.MIDAS_LIVE_BACKEND_URL, MIDAS_RUNNER_TOKEN: "live-token" });
    expect(liveOnly.publishMode).toBe(PUBLISH_WITH_WRANGLER);
  });

  it("live publishes first only when MIDAS_LIVE_RUNNER_PUBLISH says so; staging can be turned back", () => {
    const liveOn = settingsFromEnv({ ...BOTH_ENVIRONMENTS, MIDAS_LIVE_RUNNER_PUBLISH: "first" });
    expect(settingsForEnvironment(liveOn, "live").publishMode).toBe(PUBLISH_FIRST);
    const stagingOff = settingsFromEnv({ ...BOTH_ENVIRONMENTS, MIDAS_STAGING_RUNNER_PUBLISH: "wrangler" });
    expect(settingsForEnvironment(stagingOff, "staging").publishMode).toBe(PUBLISH_WITH_WRANGLER);
  });

  it("the old single switch does not turn live on", () => {
    const settings = settingsFromEnv({ ...BOTH_ENVIRONMENTS, MIDAS_RUNNER_PUBLISH: "first" });
    expect(settingsForEnvironment(settings, "live").publishMode).toBe(PUBLISH_WITH_WRANGLER);
  });

  it("refuses an unknown mode, naming the variable", () => {
    expect(() => settingsFromEnv({ ...BOTH_ENVIRONMENTS, MIDAS_LIVE_RUNNER_PUBLISH: "fast" })).toThrow("MIDAS_LIVE_RUNNER_PUBLISH must be first or wrangler, not fast");
  });
});

describe("longPollBackends", () => {
  it("long-polls only environments that publish first", () => {
    const live = fakeBackend("live");
    const staging = fakeBackend("staging");
    expect(longPollBackends([live, staging], { live: PUBLISH_WITH_WRANGLER, staging: PUBLISH_FIRST })).toEqual([staging]);
    expect(longPollBackends([live], { live: PUBLISH_WITH_WRANGLER, staging: PUBLISH_FIRST })).toEqual([]);
    expect(longPollBackends([live, staging], { live: PUBLISH_FIRST, staging: PUBLISH_FIRST })).toEqual([live, staging]);
  });
});
