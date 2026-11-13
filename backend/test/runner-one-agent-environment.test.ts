// One runner serves live and staging (founder, 2026-10-21), and the one repair agent goes to
// staging before live (founder, 2026-11-13: testing, then staging, then live). These check that
// MIDAS_STAGING_REPAIR_AGENT=shared sends staging jobs to the one agent while live jobs keep the
// per-Sidekick files, and that a job's own environment (job.environment, set when it is claimed)
// picks the variable.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { buildSystemPrompt, repairAgentMode, repairAgentVariableFor } from "../../runner/lib/prompt.mjs";

const REPO_ROOT = join(__dirname, "..", "..");
const SHARED_HEADING = "# You repair one person's copy of the Water Sidekick";
const PER_SIDEKICK_HEADING = "# You repair one user's copy of the hydration Sidekick";
const VARIABLES = ["MIDAS_REPAIR_AGENT", "MIDAS_STAGING_REPAIR_AGENT", "MIDAS_LIVE_REPAIR_AGENT"];

function waterPrompt(environment: string | undefined): string {
  const manifestText = readFileSync(join(REPO_ROOT, "sidekicks", "hydration", "manifest.json"), "utf8");
  const job = { sidekickId: "hydration", kind: "change", id: "r-env", transcript: "bigger glass", environment };
  return buildSystemPrompt({ job, reportFiles: [], manifestText, checkoutRoot: REPO_ROOT });
}

function clearModeVariables(): void {
  for (const variableName of VARIABLES) {
    delete process.env[variableName];
  }
}

describe("the one agent per environment", () => {
  // The machine running the suite may have a mode set; each test starts and ends with none.
  beforeEach(clearModeVariables);
  afterEach(clearModeVariables);

  it("names the variable the way config.mjs names per-environment ones", () => {
    expect(repairAgentVariableFor("staging")).toBe("MIDAS_STAGING_REPAIR_AGENT");
    expect(repairAgentVariableFor("live")).toBe("MIDAS_LIVE_REPAIR_AGENT");
  });

  it("the job's environment variable wins over the one for both", () => {
    const environment = { MIDAS_STAGING_REPAIR_AGENT: "shared", MIDAS_REPAIR_AGENT: "per-sidekick" };
    expect(repairAgentMode(environment, "staging")).toBe("shared");
    expect(repairAgentMode(environment, "live")).toBe("per-sidekick");
    expect(repairAgentMode({ MIDAS_REPAIR_AGENT: "shared" }, "live")).toBe("shared");
    expect(repairAgentMode({ MIDAS_LIVE_REPAIR_AGENT: "nonsense", MIDAS_REPAIR_AGENT: "shared" }, "live")).toBe("shared");
  });

  it("staging jobs get the one agent and live jobs keep Water's own file", () => {
    process.env.MIDAS_STAGING_REPAIR_AGENT = "shared";
    expect(waterPrompt("staging")).toContain(SHARED_HEADING);
    expect(waterPrompt("live")).toContain(PER_SIDEKICK_HEADING);
    expect(waterPrompt(undefined)).toContain(PER_SIDEKICK_HEADING);
  });

  it("with nothing set, every job keeps its Sidekick's own file", () => {
    expect(waterPrompt("staging")).toContain(PER_SIDEKICK_HEADING);
    expect(waterPrompt("live")).toContain(PER_SIDEKICK_HEADING);
  });
});
