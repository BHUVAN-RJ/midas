// This person's notes, wired into runJob (lead, 2026-11-13, W4 hand-back item 1; founder D5): a
// fixed repair appends one dated line to the copy's tests/PERSON_NOTES.md after the test
// comparison and before fix_ready, logs it in person-note.json, and publishes it with the fix; the
// one agent's prompt shows the notes the copy already had; a repair that is not fixed adds nothing.
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createBackendClient } from "../../runner/lib/backend.mjs";
import { runJob } from "../../runner/lib/run-job.mjs";
import {
  AGENT_THAT_SAYS_UNSUPPORTED,
  RUNNER_TOKEN,
  fakeDeployThatLands,
  fakeFetchWithStoredTests,
  makeScratch,
  standardAssets,
  startFakeBackend,
  writeStubAgent,
  type FakeBackend,
} from "./helpers/runner-fixture";

const JOB_ROW = {
  id: "rep-notes-1",
  user_id: "user-77",
  sidekick_id: "reminders",
  bundle_version: "20261011T065908559Z-1064a312",
  kind: "change",
  transcript: "rename the page to My Reminders",
};

const EARLIER_NOTES = "# This person's notes\n\n- 2026-11-07: Search tab hidden. Search stays in the top bar. (repair r-old)\n";

const AGENT_THAT_FIXES_WITH_NOTE = `
import { readFileSync, writeFileSync } from "node:fs";
const page = readFileSync("sidekick/index.html", "utf8");
writeFileSync("sidekick/index.html", page.replace("<title>Reminders</title>", "<title>My Reminders</title>"));
writeFileSync("outcome.json", JSON.stringify({ result: "fixed", summary: "Renamed the page title.", note: "Page title is My Reminders." }));
`;

let openBackend: FakeBackend | null = null;

afterEach(async () => {
  delete process.env.MIDAS_REPAIR_AGENT;
  if (openBackend !== null) {
    await openBackend.close();
    openBackend = null;
  }
});

async function runNotesJob(agentSource: string) {
  const { scratch, settings } = makeScratch();
  const backendServer = await startFakeBackend(JOB_ROW, standardAssets());
  openBackend = backendServer;
  const backend = createBackendClient({ baseUrl: backendServer.baseUrl, token: RUNNER_TOKEN });
  const job = await backend.claimJob();
  const fetch = fakeFetchWithStoredTests({ "TEST_CHANGES.md": "", "PERSON_NOTES.md": EARLIER_NOTES });
  const deploy = fakeDeployThatLands();
  // What the deploy got: the staged folder is removed afterwards, so read the notes at deploy time.
  const deployedNotes: string[] = [];
  async function runDeployAndReadNotes(call: { checkoutRoot: string; args: string[] }) {
    const stagedFolder = call.args[call.args.indexOf("--dir") + 1];
    const notesPath = join(stagedFolder, "tests", "PERSON_NOTES.md");
    deployedNotes.push(existsSync(notesPath) ? readFileSync(notesPath, "utf8") : "(no notes deployed)");
    return deploy.runDeploy(call);
  }
  const result = await runJob(job, {
    backend,
    settings,
    agentCommand: process.execPath,
    agentArgs: [writeStubAgent(scratch, agentSource)],
    runFetch: fetch.runFetch,
    runTests: async () => ({ ok: true, output: "1 passed" }),
    runDeploy: runDeployAndReadNotes,
    readPointer: deploy.readPointer,
    notify: async () => {},
    now: () => new Date(2026, 10, 13, 9, 0, 0),
  });
  return { result, backendServer, deployedNotes };
}

describe("runJob keeps this person's notes", () => {
  it("a fixed repair appends its dated line, logs person-note.json and publishes the notes", async () => {
    const { result, backendServer, deployedNotes } = await runNotesJob(AGENT_THAT_FIXES_WITH_NOTE);
    expect(result.status).toBe("deployed_live");
    expect(backendServer.statuses.map((status) => status.status)).toEqual(["running", "fix_ready", "deployed_live"]);
    const newLine = "- 2026-11-13: Page title is My Reminders. (repair rep-notes-1)";
    const noteLog = JSON.parse(readFileSync(join(result.logFolder, "person-note.json"), "utf8"));
    expect(noteLog).toEqual({ appended: true, line: newLine });
    const notes = readFileSync(join(result.jobFolder, "tests", "PERSON_NOTES.md"), "utf8");
    expect(notes).toContain("- 2026-11-07: Search tab hidden. Search stays in the top bar. (repair r-old)");
    expect(notes.trimEnd().endsWith(newLine)).toBe(true);
    expect(deployedNotes).toHaveLength(1);
    expect(deployedNotes[0]).toContain(newLine);
  });

  it("the one agent's prompt shows the notes the copy already had", async () => {
    process.env.MIDAS_REPAIR_AGENT = "shared";
    const { result } = await runNotesJob(AGENT_THAT_FIXES_WITH_NOTE);
    const prompt = readFileSync(join(result.logFolder, "system-prompt.md"), "utf8");
    expect(prompt).toContain("# You repair one person's copy of the Reminders Sidekick");
    expect(prompt).toContain("- 2026-11-07: Search tab hidden. Search stays in the top bar. (repair r-old)");
    // Not the new line: the prompt is built before the agent runs.
    expect(prompt).not.toContain("Page title is My Reminders.");
  });

  it("an unsupported repair adds no line and publishes nothing", async () => {
    const { result, deployedNotes } = await runNotesJob(AGENT_THAT_SAYS_UNSUPPORTED);
    expect(result.status).toBe("failed");
    expect(existsSync(join(result.logFolder, "person-note.json"))).toBe(false);
    expect(readFileSync(join(result.jobFolder, "tests", "PERSON_NOTES.md"), "utf8")).toBe(EARLIER_NOTES);
    expect(deployedNotes).toEqual([]);
  });
});
