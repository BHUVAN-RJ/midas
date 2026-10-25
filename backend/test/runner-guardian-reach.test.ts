// Every repair can reach test-guardian, and only it (founder, 2026-10-25). Repairs 50ca5522 and
// 9c699df4 (2026-10-24, "I don't want the year to be shown") ended unsupported because the runner
// denied "Task", the Agent tool's own name in Claude Code, so no run since 2026-10-19 had the
// Agent tool. Also: a deletion the guardian logged passes the runner, an unlogged one still fails.
import { cpSync, mkdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { guardianReachProblems, sessionInitFromLog } from "../../runner/lib/agent-check.mjs";
import { AGENT_DENIED_SUBAGENTS, AGENT_DENIED_TOOLS, GUARDIAN_AGENT, buildClaudeArgs } from "../../runner/lib/agent.mjs";
import { createBackendClient } from "../../runner/lib/backend.mjs";
import { AGENT_SETTINGS_FILES, TEST_LOG_FILE, compareTests } from "../../runner/lib/copy-tests.mjs";
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
} from "./helpers/runner-fixture";

// Everything after a list flag until the next "--" flag.
function flagList(args: string[], flag: string): string[] {
  const index = args.indexOf(flag);
  expect(index).toBeGreaterThan(-1);
  const values: string[] = [];
  for (let position = index + 1; position < args.length && !args[position].startsWith("--"); position += 1) {
    values.push(args[position]);
  }
  return values;
}

// The init event of repair 9c699df4's real log (claude 2.1.310), trimmed: no Agent tool.
const INIT_WITHOUT_AGENT_TOOL = JSON.stringify({
  type: "system",
  subtype: "init",
  tools: ["Bash", "Edit", "Glob", "Grep", "Read", "Write"],
  agents: ["claude", "Explore", "general-purpose", "Plan", "statusline-setup", "test-guardian"],
});
// The same session once "Task" is no longer denied (seen with `--disallowedTools WebFetch`).
const INIT_WITH_AGENT_TOOL = JSON.stringify({
  type: "system",
  subtype: "init",
  tools: ["Task", "Bash", "Edit", "Glob", "Grep", "Read", "Write"],
  agents: ["claude", "Explore", "general-purpose", "Plan", "statusline-setup", "test-guardian"],
});

describe("the runner's rules leave test-guardian as the one reachable subagent", () => {
  const args = buildClaudeArgs({ systemPromptPath: "/tmp/prompt.md", model: "opus", maxTurns: 50, intelToolPath: "/r/tools/intel.mjs", checkToolPath: "/r/tools/check.mjs" });
  const denied = flagList(args, "--disallowedTools");

  it("never denies the Agent tool itself, under either of its names", () => {
    expect(denied).not.toContain("Task");
    expect(denied).not.toContain("Agent");
    expect(denied).not.toContain("Agent(*)");
    expect(denied).not.toContain(`Agent(${GUARDIAN_AGENT})`);
    expect(flagList(args, "--tools")[0].split(",")).toContain("Agent");
    expect(flagList(args, "--allowedTools")).toContain(`Agent(${GUARDIAN_AGENT})`);
  });

  it("denies every other subagent a repair session lists, claude and statusline-setup included", () => {
    const listed = JSON.parse(INIT_WITH_AGENT_TOOL).agents as string[];
    for (const agentName of listed) {
      if (agentName === GUARDIAN_AGENT) {
        continue;
      }
      expect(AGENT_DENIED_SUBAGENTS).toContain(agentName);
      expect(denied).toContain(`Agent(${agentName})`);
    }
    expect(AGENT_DENIED_SUBAGENTS).not.toContain(GUARDIAN_AGENT);
    expect(denied).toEqual(AGENT_DENIED_TOOLS);
  });
});

describe("guardianReachProblems reads the session's init event", () => {
  it("names the missing Agent tool in the log of repair 9c699df4", () => {
    const init = sessionInitFromLog(`not json\n${INIT_WITHOUT_AGENT_TOOL}\n`);
    expect(init).not.toBeNull();
    const problems = guardianReachProblems({ init, guardianName: GUARDIAN_AGENT, deniedSubagents: AGENT_DENIED_SUBAGENTS });
    expect(problems).toEqual(["no Agent tool (tools: Bash, Edit, Glob, Grep, Read, Write)"]);
  });

  it("passes the fixed session and flags a subagent the runner does not deny", () => {
    const init = sessionInitFromLog(INIT_WITH_AGENT_TOOL);
    expect(guardianReachProblems({ init, guardianName: GUARDIAN_AGENT, deniedSubagents: AGENT_DENIED_SUBAGENTS })).toEqual([]);
    const withNewAgent = { tools: ["Agent"], agents: ["test-guardian", "new-helper"] };
    expect(guardianReachProblems({ init: withNewAgent, guardianName: GUARDIAN_AGENT, deniedSubagents: AGENT_DENIED_SUBAGENTS })).toEqual(["subagent new-helper is listed and not denied"]);
    const withoutGuardian = { tools: ["Agent"], agents: ["Explore"] };
    expect(guardianReachProblems({ init: withoutGuardian, guardianName: GUARDIAN_AGENT, deniedSubagents: AGENT_DENIED_SUBAGENTS })).toEqual(["test-guardian not listed"]);
    expect(guardianReachProblems({ init: sessionInitFromLog("{}"), guardianName: GUARDIAN_AGENT, deniedSubagents: AGENT_DENIED_SUBAGENTS })).toEqual(["the log has no init event"]);
  });
});

describe("compareTests: a deletion passes only when the guardian logged it", () => {
  const before = { "a.test.ts": Buffer.from("x"), "b.test.ts": Buffer.from("y"), [TEST_LOG_FILE]: Buffer.from("- old entry\n") };

  it("accepts a logged deletion and still lists it", () => {
    const logged = compareTests({ before, after: { "a.test.ts": Buffer.from("x"), [TEST_LOG_FILE]: Buffer.from("- 2026-10-25 b.test.ts removed with its feature. ACCEPTED\n- old entry\n") } });
    expect(logged.deleted).toEqual(["b.test.ts"]);
    expect(logged.problems).toEqual([]);
  });

  it("refuses a deletion logged under another file's name, or with a log that lost a line", () => {
    const wrongName = compareTests({ before, after: { "a.test.ts": Buffer.from("x"), [TEST_LOG_FILE]: Buffer.from("- old entry\n- 2026-10-25 a.test.ts ACCEPTED\n") } });
    expect(wrongName.problems).toEqual(["test deleted: b.test.ts"]);
    const lostLine = compareTests({ before, after: { "a.test.ts": Buffer.from("x"), [TEST_LOG_FILE]: Buffer.from("- 2026-10-25 b.test.ts ACCEPTED\n") } });
    expect(lostLine.problems).toEqual(["test deleted: b.test.ts", "TEST_CHANGES.md lost entries"]);
  });
});

const JOB_ROW = { id: "rep-g1", user_id: "user-77", sidekick_id: "reminders", bundle_version: "20261011T065908559Z-1064a312", kind: "change", transcript: "take the manifest check away with the feature" };

const COPY_TEST_MANIFEST = [
  'import { readFileSync } from "node:fs";',
  'import { describe, expect, it } from "vitest";',
  'const manifest = JSON.parse(readFileSync(new URL("../../sidekicks/reminders/manifest.json", import.meta.url), "utf8"));',
  'describe("copy manifest", () => { it("is the reminders Sidekick", () => { expect(manifest.id).toBe("reminders"); }); });',
  "",
].join("\n");
const COPY_LOG = "# Test changes for this copy\n\n- 2026-10-12: copy started from base; no changes.\n";

// What a guardian-accepted deletion looks like from the runner's side: the file is gone and the
// log kept its lines and gained one naming it.
const AGENT_WITH_GUARDIAN_LOGGED_DELETION = `
import { readFileSync, writeFileSync, unlinkSync, appendFileSync } from "node:fs";
const page = readFileSync("sidekick/index.html", "utf8");
writeFileSync("sidekick/index.html", page.replace("<title>Reminders</title>", "<title>My Reminders</title>"));
unlinkSync("tests/reminders-copy-manifest.test.ts");
appendFileSync("tests/TEST_CHANGES.md", "- 2026-10-25: reminders-copy-manifest.test.ts removed with its feature. ACCEPTED by test-guardian.\\n");
writeFileSync("outcome.json", JSON.stringify({ result: "fixed", summary: "Renamed; the guardian removed a test." }));
`;

let openBackend: FakeBackend | null = null;

afterEach(async () => {
  if (openBackend !== null) {
    await openBackend.close();
    openBackend = null;
  }
});

describe("a repair job with a deletion the guardian logged", () => {
  it("goes live and names the deletion in the summary", async () => {
    const { scratch, checkout, settings } = makeScratch();
    for (const relativePath of AGENT_SETTINGS_FILES) {
      mkdirSync(join(checkout, relativePath, ".."), { recursive: true });
      cpSync(join(REPO_ROOT, relativePath), join(checkout, relativePath));
    }
    const storedTests = { "reminders-copy-manifest.test.ts": COPY_TEST_MANIFEST, [TEST_LOG_FILE]: COPY_LOG };
    const backendServer = await startFakeBackend(JOB_ROW, standardAssets());
    openBackend = backendServer;
    const backend = createBackendClient({ baseUrl: backendServer.baseUrl, token: RUNNER_TOKEN });
    const job = await backend.claimJob();
    const deploy = fakeDeployThatLands();
    const result = await runJob(job, {
      backend,
      settings,
      agentCommand: process.execPath,
      agentArgs: [writeStubAgent(scratch, AGENT_WITH_GUARDIAN_LOGGED_DELETION)],
      runFetch: fakeFetchWithStoredTests(storedTests).runFetch,
      runTests: async () => ({ ok: true, output: "ok" }),
      runDeploy: deploy.runDeploy,
      readPointer: deploy.readPointer,
      notify: async () => {},
    });
    expect(result.status).toBe("deployed_live");
    const report = JSON.parse(readFileSync(join(result.logFolder, "tests-report.json"), "utf8"));
    expect(report.deleted).toEqual(["reminders-copy-manifest.test.ts"]);
    expect(report.problems).toEqual([]);
    const summary = readFileSync(join(result.logFolder, "summary.md"), "utf8");
    expect(summary).toContain("Deleted by test-guardian: reminders-copy-manifest.test.ts.");
  });
});

describe("the repair prompts and the guardian agree on how a job reaches the guardian", () => {
  const guardianText = readFileSync(join(REPO_ROOT, ".claude", "agents", "test-guardian.md"), "utf8");

  it("the guardian has the repair-job rules: the report as authority, the check command as the suite, change before delete", () => {
    expect(guardianText).toContain("## Inside a repair job");
    expect(guardianText).toContain("`docs/PRODUCT.md` is not in the job");
    expect(guardianText).toContain("A user reversing an earlier request of their own is a valid request");
    expect(guardianText).toContain("**The full suite** is the check command the repair agent gives you");
    expect(guardianText).toContain("**Change, don't delete,**");
  });

  for (const promptName of ["reminders.md", "care-reminders.md"]) {
    it(`${promptName} hands the guardian the check command and the reversal rule`, () => {
      const promptText = readFileSync(join(REPO_ROOT, "runner", "agents", promptName), "utf8");
      const start = promptText.indexOf("- When an existing test blocks what the user asked for");
      expect(start).toBeGreaterThan(-1);
      const delegation = promptText.slice(start, promptText.indexOf("\n- ", start + 1));
      expect(delegation).toContain("`node {{CHECK_TOOL}}`");
      expect(delegation).toContain("A user reversing an earlier");
    });
  }
});
