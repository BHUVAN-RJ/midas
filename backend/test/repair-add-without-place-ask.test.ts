// A request to add something with no drawing and no named place is a question, never a refusal
// (founder, 2026-11-23, same decision as docs/PRODUCT.md main 130a76a; staging job 844c1160:
// Reminders "Can you add more emojis on the screen", no drawing, sorted code at 0.3, and the repair
// agent answered unsupported "unclear: where should they go"). Both layers ask: the sort's rule names
// it ask_back with options naming concrete places, and the repair agent finishes with result "ask"
// and those choices, which the runner posts as the question card.
import { afterEach, describe, expect, it } from "vitest";
import { createBackendClient } from "../../runner/lib/backend.mjs";
import { UNCLEAR_ASK_RULE, buildSystemPrompt } from "../../runner/lib/prompt.mjs";
import { runJob } from "../../runner/lib/run-job.mjs";
import { plannedSteps } from "../../runner/core-checks/page-open.mjs";
import { CARD_OPTIONS_RULE, VAGUE_WORDS_RULE, isConcreteLabel } from "../src/repair-sort-model";
import { agentQuestionFrom } from "../src/repair-sort";
import {
  RUNNER_TOKEN,
  fakeDeployThatLands,
  fakeFetchWithoutStoredTests,
  makeScratch,
  standardAssets,
  startFakeBackend,
  writeStubAgent,
  type FakeBackend,
} from "./helpers/runner-fixture";

const WORDS = "Can you add more emojis on the screen";
const PLACE_OPTIONS = [
  { label: "Emoji on Each View Title", kind: "other_icon" },
  { label: "An Emoji for Each Reminder", kind: "other_icon" },
  { label: "Emoji Beside the Date", kind: "other_icon" },
];

describe("the sort asks where", () => {
  it("names adding with no drawing and no place as ask_back, with places as options, and no longer gives emojis as a code example", () => {
    const rule = VAGUE_WORDS_RULE.toLowerCase();
    expect(rule).toContain(`"${WORDS.toLowerCase()}"`);
    expect(rule).toContain('"add some colour"');
    expect(rule).toContain("no drawing and no named place");
    expect(VAGUE_WORDS_RULE).not.toContain('"add emojis"');
    expect(VAGUE_WORDS_RULE).toContain('"Emoji on Each View Title"');
    expect(CARD_OPTIONS_RULE).toContain("with no drawing, the thing they asked for in one concrete place");
  });

  it("the place options are concrete labels the card accepts", () => {
    for (const option of PLACE_OPTIONS) {
      expect(isConcreteLabel(option.label)).toBe(true);
    }
    const card = agentQuestionFrom({ question: "Where should emojis go?", options: PLACE_OPTIONS });
    expect(card?.options.map(function labelOf(option) { return option.label; })).toEqual(PLACE_OPTIONS.map(function labelOf(option) { return option.label; }));
  });
});

describe("the repair agent asks where", () => {
  it("its prompt for job 844c1160's words says not knowing where is the ask case, never unsupported", () => {
    const job = { id: "844c1160", sidekickId: "reminders", transcript: WORDS };
    const manifestText = JSON.stringify({ id: "reminders", name: "Reminders", types: {} });
    for (const agentMode of ["per-sidekick", "shared"]) {
      const prompt = buildSystemPrompt({ job, reportFiles: ["transcript.txt", "screenshot.png"], manifestText, agentMode });
      expect(prompt).toContain(UNCLEAR_ASK_RULE);
    }
    expect(UNCLEAR_ASK_RULE).toContain("add something with no drawing and no named place");
    expect(UNCLEAR_ASK_RULE).toContain("never unsupported");
    expect(UNCLEAR_ASK_RULE).toContain('"Emoji on Each View Title"');
  });
});

const AGENT_THAT_ASKS_WHERE = `
import { writeFileSync } from "node:fs";
writeFileSync("outcome.json", ${JSON.stringify(JSON.stringify({ result: "ask", question: "Where should emojis go?", options: PLACE_OPTIONS, summary: "Not clear where the emojis go." }))});
`;

function pagesThatOpen() {
  async function openPageStandIn({ actions, kinds, records }: { actions: string[]; kinds: string[]; records: unknown[] }) {
    const steps = plannedSteps({ records, actions, kinds });
    return steps.map(function stepReport(step: { name: string; action: string | null }) {
      const report = { errors: [], writes: [], written: {}, visibleElements: 5, textLength: 5, action: step.action === null ? null : { found: true } };
      return { name: step.name, action: step.action, report };
    });
  }
  return openPageStandIn;
}

let openBackend: FakeBackend | null = null;

afterEach(async () => {
  if (openBackend !== null) {
    await openBackend.close();
    openBackend = null;
  }
});

describe("runJob for job 844c1160's words", () => {
  it("comes back as a question with the place choices, never unsupported, nothing published", async () => {
    const { scratch, settings } = makeScratch();
    const jobRow = { id: "rep-844c1160", user_id: "user-77", sidekick_id: "reminders", bundle_version: "20261011T065908559Z-1064a312", kind: "unknown", transcript: WORDS };
    const backendServer = await startFakeBackend(jobRow, standardAssets());
    openBackend = backendServer;
    const client = createBackendClient({ baseUrl: backendServer.baseUrl, token: RUNNER_TOKEN });
    const asked: Array<{ reportId: string; body: { question: string; options: unknown[] } }> = [];
    async function recordAsk(reportId: string, body: { question: string; options: unknown[] }) {
      asked.push({ reportId, body });
      return { lane: "ask_back" };
    }
    const backend = { ...client, askQuestion: recordAsk };
    const deploy = fakeDeployThatLands();
    async function quiet() {}
    async function testsPass() {
      return { ok: true, output: "1 passed" };
    }
    const job = await backend.claimJob();
    const result = await runJob(job, {
      backend,
      settings: { ...settings, publishMode: "first" },
      agentCommand: process.execPath,
      agentArgs: [writeStubAgent(scratch, AGENT_THAT_ASKS_WHERE)],
      runFetch: fakeFetchWithoutStoredTests().runFetch,
      runTests: testsPass,
      runDeploy: deploy.runDeploy,
      readPointer: deploy.readPointer,
      notify: quiet,
      openPageImplementation: pagesThatOpen(),
    });
    expect(result.status).toBe("asked");
    expect(asked.length).toBe(1);
    expect(asked[0].body.options).toEqual(PLACE_OPTIONS);
    const statuses = backendServer.statuses.map(function statusName(entry: Record<string, unknown>) {
      return entry.status;
    });
    expect(statuses).toEqual(["running"]);
    expect(deploy.deployCalls).toEqual([]);
  });
});
