// Runner repair-lanes behaviours are staging only (founder, 2026-11-22: "runner repair-lanes
// behaviours staging only until founder says live"). One runner serves live and staging; each
// repair-lanes step has a per-environment switch, off for live and on for staging when unset:
// MIDAS_<ENV>_RUNNER_SHIELD, MIDAS_<ENV>_RUNNER_NOTES, MIDAS_<ENV>_RUNNER_SORT_ANSWER, next to the
// earlier MIDAS_<ENV>_RUNNER_PUBLISH and MIDAS_<ENV>_REPAIR_AGENT. Live with every default takes the
// runner's steps from before repair lanes (runner clone 1a55606): the per-Sidekick agent prompt, the
// deploy gate and the copy's tests, records read after the agent, wrangler publish; no shield, no
// notes line, no ask-back answer in the transcript.
import { existsSync, readFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createBackendClient } from "../../runner/lib/backend.mjs";
import {
  LANE_SWITCH_DEFAULTS,
  PUBLISH_FIRST,
  PUBLISH_WITH_WRANGLER,
  anyEnvironmentRunsShield,
  laneSwitchOn,
  laneSwitchVariableName,
  settingsForEnvironment,
  settingsFromEnv,
} from "../../runner/lib/config.mjs";
import { repairAgentMode } from "../../runner/lib/prompt.mjs";
import { runJob } from "../../runner/lib/run-job.mjs";
import {
  REPO_ROOT,
  RUNNER_TOKEN,
  fakeDeployThatLands,
  fakeFetchWithStoredTests,
  makeScratch,
  standardAssets,
  startFakeBackend,
  writeStubAgent,
  type FakeBackend,
  type FakeJobRow,
} from "./helpers/runner-fixture";

const BOTH_ENVIRONMENTS = {
  MIDAS_LIVE_BACKEND_URL: "https://midas-api.midas-backend.workers.dev",
  MIDAS_LIVE_RUNNER_TOKEN: "live-token",
  MIDAS_STAGING_BACKEND_URL: "https://midas-api-staging.midas-backend.workers.dev",
  MIDAS_STAGING_RUNNER_TOKEN: "staging-token",
};

const SWITCH_NAMES = ["shield", "personNotes", "sortAnswer"] as const;

describe("lane switches from an empty environment", () => {
  it("live: every repair-lanes switch off, wrangler publish, per-Sidekick agent", () => {
    const live = settingsForEnvironment(settingsFromEnv(BOTH_ENVIRONMENTS), "live");
    expect(live.shield).toBe(false);
    expect(live.personNotes).toBe(false);
    expect(live.sortAnswer).toBe(false);
    expect(live.publishMode).toBe(PUBLISH_WITH_WRANGLER);
    expect(repairAgentMode({}, "live")).toBe("per-sidekick");
    for (const switchName of SWITCH_NAMES) {
      expect(laneSwitchOn(live, switchName)).toBe(false);
    }
  });

  it("staging: every repair-lanes switch on, publish first", () => {
    const staging = settingsForEnvironment(settingsFromEnv(BOTH_ENVIRONMENTS), "staging");
    expect(staging.shield).toBe(true);
    expect(staging.personNotes).toBe(true);
    expect(staging.sortAnswer).toBe(true);
    expect(staging.publishMode).toBe(PUBLISH_FIRST);
    for (const switchName of SWITCH_NAMES) {
      expect(laneSwitchOn(staging, switchName)).toBe(true);
    }
  });

  it("names each switch MIDAS_<ENV>_RUNNER_<NAME> and defaults live off, staging on", () => {
    expect(laneSwitchVariableName("live", "shield")).toBe("MIDAS_LIVE_RUNNER_SHIELD");
    expect(laneSwitchVariableName("staging", "personNotes")).toBe("MIDAS_STAGING_RUNNER_NOTES");
    expect(laneSwitchVariableName("live", "sortAnswer")).toBe("MIDAS_LIVE_RUNNER_SORT_ANSWER");
    expect(LANE_SWITCH_DEFAULTS).toEqual({ live: false, staging: true });
  });

  it("each switch turns on or off for one environment only", () => {
    const liveShieldOn = settingsFromEnv({ ...BOTH_ENVIRONMENTS, MIDAS_LIVE_RUNNER_SHIELD: "on" });
    expect(settingsForEnvironment(liveShieldOn, "live").shield).toBe(true);
    expect(settingsForEnvironment(liveShieldOn, "live").personNotes).toBe(false);
    const stagingNotesOff = settingsFromEnv({ ...BOTH_ENVIRONMENTS, MIDAS_STAGING_RUNNER_NOTES: "off" });
    expect(settingsForEnvironment(stagingNotesOff, "staging").personNotes).toBe(false);
    expect(settingsForEnvironment(stagingNotesOff, "staging").shield).toBe(true);
    expect(settingsForEnvironment(stagingNotesOff, "live").personNotes).toBe(false);
  });

  it("refuses a value that is not on or off", () => {
    expect(() => settingsFromEnv({ ...BOTH_ENVIRONMENTS, MIDAS_LIVE_RUNNER_SHIELD: "yes" })).toThrow("MIDAS_LIVE_RUNNER_SHIELD must be on or off, not yes");
  });

  it("builds the shield's WebKit program at start only when an environment runs the shield", () => {
    const liveOnly = settingsFromEnv({ MIDAS_LIVE_BACKEND_URL: BOTH_ENVIRONMENTS.MIDAS_LIVE_BACKEND_URL, MIDAS_LIVE_RUNNER_TOKEN: "live-token" });
    expect(anyEnvironmentRunsShield(liveOnly)).toBe(false);
    expect(anyEnvironmentRunsShield(settingsFromEnv(BOTH_ENVIRONMENTS))).toBe(true);
    const runnerSource = readFileSync(join(REPO_ROOT, "runner", "bin", "runner.mjs"), "utf8");
    expect(runnerSource).toContain("if (anyEnvironmentRunsShield(settings)) {");
  });
});

// ---- runJob with live's switches against the same job with staging's lane steps -----------------

const JOB_ROW = {
  id: "rep-lanes-1",
  user_id: "user-77",
  sidekick_id: "reminders",
  bundle_version: "20261011T065908559Z-1064a312",
  kind: "change",
  transcript: "make add say something else",
  sort: { status: "answered", lane: "code", confidence: 0.9, model: "typesafe/jev-1.14", answer: "Say Added it" },
} as unknown as FakeJobRow;

const EARLIER_NOTES = "# This person's notes\n\n- 2026-11-07: Search tab hidden. Search stays in the top bar. (repair r-old)\n";

// Changes what reminders.add answers without naming it in changedTools (the shield refuses this),
// leaves a notes line, and reports the shield inputs its environment got.
const AGENT_THAT_CHANGES_ADD_UNNAMED = `
import { appendFileSync, readFileSync, writeFileSync } from "node:fs";
const page = readFileSync("sidekick/index.html", "utf8");
writeFileSync("sidekick/index.html", page.replace("<title>Reminders</title>", "<title>My Reminders</title>"));
appendFileSync("sidekick/tools.js", "\\nMidasSidekickTools.handlers.add = function changedAdd() { return { ops: [], result: { text: 'Added it' } }; };\\n");
const shieldInputs = { before: process.env.MIDAS_JOB_BEFORE_FOLDER ?? null, records: process.env.MIDAS_JOB_RECORDS ?? null };
writeFileSync("outcome.json", JSON.stringify({ result: "fixed", summary: "Add says Added it. " + JSON.stringify(shieldInputs), note: "Add says Added it." }));
`;

let openBackend: FakeBackend | null = null;

afterEach(async () => {
  if (openBackend !== null) {
    await openBackend.close();
    openBackend = null;
  }
});

type Switches = { shield: boolean; personNotes: boolean; sortAnswer: boolean };

// The job's settings: the scratch checkout's paths with one environment's switches, publishing
// with wrangler so the two runs differ only in the lane switches.
async function runLanesJob(switches: Switches, { removeShield }: { removeShield: boolean }) {
  const { scratch, checkout, settings } = makeScratch();
  if (removeShield) {
    // Any use of the shield now fails the job: it is loaded from the checkout's runner/core-checks.
    rmSync(join(checkout, "runner", "core-checks"), { recursive: true, force: true });
  }
  const backendServer = await startFakeBackend(JOB_ROW, standardAssets());
  openBackend = backendServer;
  const backend = createBackendClient({ baseUrl: backendServer.baseUrl, token: RUNNER_TOKEN });
  const job = await backend.claimJob();
  const deploy = fakeDeployThatLands();
  const fetch = fakeFetchWithStoredTests({ "TEST_CHANGES.md": "", "PERSON_NOTES.md": EARLIER_NOTES });
  const result = await runJob(job, {
    backend,
    settings: { ...settings, publishMode: PUBLISH_WITH_WRANGLER, ...switches },
    agentCommand: process.execPath,
    agentArgs: [writeStubAgent(scratch, AGENT_THAT_CHANGES_ADD_UNNAMED)],
    runFetch: fetch.runFetch,
    runTests: async () => ({ ok: true, output: "1 passed" }),
    runDeploy: deploy.runDeploy,
    readPointer: deploy.readPointer,
    notify: async () => {},
    now: () => new Date(2026, 10, 22, 9, 0, 0),
  });
  return { result, backendServer, deploy };
}

function liveDefaults(): Switches {
  const live = settingsForEnvironment(settingsFromEnv(BOTH_ENVIRONMENTS), "live");
  return { shield: live.shield, personNotes: live.personNotes, sortAnswer: live.sortAnswer };
}

function stagingDefaults(): Switches {
  const staging = settingsForEnvironment(settingsFromEnv(BOTH_ENVIRONMENTS), "staging");
  return { shield: staging.shield, personNotes: staging.personNotes, sortAnswer: staging.sortAnswer };
}

describe("a live job with every default takes the steps from before repair lanes", () => {
  it("never loads the shield, gives the agent no shield inputs and publishes with wrangler", async () => {
    const { result, backendServer, deploy } = await runLanesJob(liveDefaults(), { removeShield: true });
    expect(result.status).toBe("deployed_live");
    expect(backendServer.statuses.map((status) => status.status)).toEqual(["running", "fix_ready", "deployed_live"]);
    expect(deploy.deployCalls).toHaveLength(1);
    expect(existsSync(join(result.logFolder, "shield.txt"))).toBe(false);
    expect(existsSync(join(result.logFolder, "records.json"))).toBe(false);
    const outcome = JSON.parse(readFileSync(join(result.jobFolder, "outcome.json"), "utf8"));
    const shieldInputs = JSON.parse(outcome.summary.slice(outcome.summary.indexOf("{")));
    expect(shieldInputs).toEqual({ before: null, records: null });
    // The records are still read and checked, once, after the agent
    expect(backendServer.recordRequests).toBe(1);
  });

  it("writes no notes line", async () => {
    const { result } = await runLanesJob(liveDefaults(), { removeShield: true });
    expect(result.status).toBe("deployed_live");
    expect(existsSync(join(result.logFolder, "person-note.json"))).toBe(false);
    expect(readFileSync(join(result.jobFolder, "tests", "PERSON_NOTES.md"), "utf8")).toBe(EARLIER_NOTES);
  });

  it("uses the per-Sidekick prompt without the ask-back answer", async () => {
    const { result } = await runLanesJob(liveDefaults(), { removeShield: true });
    const prompt = readFileSync(join(result.logFolder, "system-prompt.md"), "utf8");
    expect(prompt.startsWith("# You repair one user's copy of the Reminders Sidekick")).toBe(true);
    expect(prompt).toContain("make add say something else");
    expect(prompt).not.toContain("Say Added it");
  });
});

describe("the same job with staging's switches takes the repair-lanes steps", () => {
  it("the shield refuses the unnamed tool change before fix_ready, with its inputs given to the agent", async () => {
    const { result, backendServer, deploy } = await runLanesJob(stagingDefaults(), { removeShield: false });
    expect(result.status).toBe("failed");
    expect(result.reason).toBe("check failed");
    expect(result.detail).toContain("reminders.add");
    expect(backendServer.statuses.map((status) => status.status)).toEqual(["running", "failed"]);
    expect(deploy.deployCalls).toEqual([]);
    expect(readFileSync(join(result.logFolder, "shield.txt"), "utf8")).toContain("✕ tools");
    const outcome = JSON.parse(readFileSync(join(result.jobFolder, "outcome.json"), "utf8"));
    const shieldInputs = JSON.parse(outcome.summary.slice(outcome.summary.indexOf("{")));
    expect(shieldInputs).toEqual({ before: join(result.logFolder, "before"), records: join(result.logFolder, "records.json") });
  });

  it("adds the ask-back answer to the transcript", async () => {
    const { result } = await runLanesJob(stagingDefaults(), { removeShield: false });
    const prompt = readFileSync(join(result.logFolder, "system-prompt.md"), "utf8");
    expect(prompt).toContain('they answered: "Say Added it"');
  });

  it("writes the notes line when only the shield is off", async () => {
    const { result } = await runLanesJob({ ...stagingDefaults(), shield: false }, { removeShield: true });
    expect(result.status).toBe("deployed_live");
    const noteLog = JSON.parse(readFileSync(join(result.logFolder, "person-note.json"), "utf8"));
    expect(noteLog).toEqual({ appended: true, line: "- 2026-11-22: Add says Added it. (repair rep-lanes-1)" });
  });
});
