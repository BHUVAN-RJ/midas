// Unclear code requests become a question, never a refusal (founder, 2026-11-23; docs/PRODUCT.md
// main 130a76a; job 08b4244b: Reminders "That I can move around everywhere" went to code at 0.26 and
// the agent answered unsupported because it could not tell what to move). The repair agent may
// finish with result "ask" (a short question and 2-3 concrete options); the runner posts it to the
// Worker (POST /repairs/:id/ask) and ends the job without publishing. A job that already carries the
// person's answer is never asked again: the prompt says so and the runner refuses such an ask.
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { RepairCancelled, createBackendClient } from "../../runner/lib/backend.mjs";
import { readOutcome } from "../../runner/lib/outcome.mjs";
import { ASK_OPTION_KINDS, UNCLEAR_ANSWERED_RULE, UNCLEAR_ASK_RULE, buildSystemPrompt, unclearRuleFor } from "../../runner/lib/prompt.mjs";
import { runJob } from "../../runner/lib/run-job.mjs";
import { plannedSteps } from "../../runner/core-checks/page-open.mjs";
import { GUESS_IDS, isConcreteLabel } from "../src/repair-sort-model";
import {
  RUNNER_TOKEN,
  fakeDeployThatLands,
  fakeFetchWithoutStoredTests,
  makeScratch,
  standardAssets,
  startFakeBackend,
  writeStubAgent,
  type FakeBackend,
  type FakeJobRow,
} from "./helpers/runner-fixture";

const ASK_OUTCOME = {
  result: "ask",
  question: "What should move?",
  options: [
    { label: "Drag to Reorder", kind: "move" },
    { label: "Move to Another Day", kind: "move" },
    { label: "Move the New Button", kind: "move" },
  ],
  summary: "Not clear what 'that' is: reorder, another day or the New button.",
};

// The agent that could not tell what to move: it asks, as the founder decided
const AGENT_THAT_ASKS = `
import { writeFileSync } from "node:fs";
writeFileSync("outcome.json", ${JSON.stringify(JSON.stringify(ASK_OUTCOME))});
`;

function folderWithOutcome(outcome: unknown): string {
  const folder = mkdtempSync(join(tmpdir(), "midas-ask-outcome-"));
  writeFileSync(join(folder, "outcome.json"), JSON.stringify(outcome));
  return folder;
}

describe("outcome.json result ask", () => {
  it("is read with its question and options; kinds outside the list become other_layout", () => {
    const read = readOutcome(folderWithOutcome({ ...ASK_OUTCOME, options: [{ label: " Drag to Reorder ", kind: "move" }, { label: "Smaller Rows", kind: "tiny" }] }));
    expect(read.problem).toBeUndefined();
    expect(read.outcome.result).toBe("ask");
    expect(read.outcome.question).toBe("What should move?");
    expect(read.outcome.options).toEqual([{ label: "Drag to Reorder", kind: "move" }, { label: "Smaller Rows", kind: "other_layout" }]);
  });

  it("needs a question and 2 or 3 options with a label", () => {
    expect(readOutcome(folderWithOutcome({ ...ASK_OUTCOME, question: "" })).problem).toContain("needs a question");
    expect(readOutcome(folderWithOutcome({ ...ASK_OUTCOME, options: [{ label: "Drag to Reorder" }] })).problem).toContain("2 or 3 options");
    const fourOptions = ["Drag to Reorder", "Smaller Rows", "Red Title", "Bigger Rows"].map(function asOption(label) {
      return { label };
    });
    expect(readOutcome(folderWithOutcome({ ...ASK_OUTCOME, options: fourOptions })).problem).toContain("2 or 3 options");
  });
});

describe("the prompt's not-understandable case", () => {
  const manifestText = JSON.stringify({ id: "reminders", name: "Reminders", types: {} });

  it("asks when there is no answer yet, and the reminders prompt no longer says to treat it as unsupported", () => {
    const job = { id: "r1", sidekickId: "reminders", transcript: "That I can move around everywhere" };
    expect(unclearRuleFor(job)).toBe(UNCLEAR_ASK_RULE);
    const prompt = buildSystemPrompt({ job, reportFiles: ["transcript.txt"], manifestText, agentMode: "per-sidekick" });
    expect(prompt).toContain(UNCLEAR_ASK_RULE);
    expect(prompt).not.toContain("{{UNCLEAR_RULE}}");
    expect(prompt).not.toContain("treat as unsupported and say what was");
    expect(prompt).toContain('"result": "ask"');
  });

  it("never asks once the job carries the person's answer (a picked choice is never refused or asked again)", () => {
    const job = { id: "r1", sidekickId: "reminders", transcript: "That I can move around everywhere", sort: { answer: "Drag to Reorder", question: "What should move?" } };
    expect(unclearRuleFor(job)).toBe(UNCLEAR_ANSWERED_RULE);
    const prompt = buildSystemPrompt({ job, reportFiles: ["transcript.txt"], manifestText, agentMode: "per-sidekick" });
    expect(prompt).toContain(UNCLEAR_ANSWERED_RULE);
    expect(prompt).not.toContain(UNCLEAR_ASK_RULE);
    expect(prompt).toContain('Asked "What should move?", they answered: "Drag to Reorder"');
  });

  it("the one agent's prompt carries the rule too", () => {
    const job = { id: "r1", sidekickId: "reminders", transcript: "That I can move around everywhere" };
    const prompt = buildSystemPrompt({ job, reportFiles: ["transcript.txt"], manifestText, agentMode: "shared" });
    expect(prompt).toContain(UNCLEAR_ASK_RULE);
    expect(prompt).not.toContain("{{UNCLEAR_RULE}}");
  });

  it("its example labels pass the sort's own label check, and its kinds are the sort's guess ids", () => {
    const examples = [...UNCLEAR_ASK_RULE.matchAll(/e\.g\. ([^.]+)\./g)][1][1];
    const labels = [...examples.matchAll(/"([^"]+)"/g)].map(function labelOf(match) {
      return match[1];
    });
    expect(labels.length).toBeGreaterThanOrEqual(3);
    for (const label of labels) {
      expect(isConcreteLabel(label)).toBe(true);
    }
    expect([...ASK_OPTION_KINDS].sort()).toEqual([...GUESS_IDS].sort());
  });
});

describe("the backend client's askQuestion", () => {
  it("posts the question to /repairs/:id/ask and reads a cancel as RepairCancelled", async () => {
    const requests: Array<{ url: string; body: unknown }> = [];
    let answer = new Response(JSON.stringify({ lane: "ask_back" }), { status: 200 });
    async function fetchStandIn(url: string, init: RequestInit) {
      requests.push({ url, body: JSON.parse(String(init.body)) });
      return answer;
    }
    const client = createBackendClient({ baseUrl: "https://worker.test", token: RUNNER_TOKEN, fetchImplementation: fetchStandIn });
    const reply = await client.askQuestion("rep-1", { question: "What should move?", options: ASK_OUTCOME.options, summary: "unclear" });
    expect(reply).toEqual({ lane: "ask_back" });
    expect(requests[0].url).toBe("https://worker.test/repairs/rep-1/ask");
    expect(requests[0].body).toEqual({ question: "What should move?", options: ASK_OUTCOME.options, summary: "unclear" });
    answer = new Response(JSON.stringify({ cancelled: true }), { status: 409 });
    await expect(client.askQuestion("rep-1", { question: "Q?", options: [], summary: "" })).rejects.toBeInstanceOf(RepairCancelled);
  });
});

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

async function runAskJob(jobRow: FakeJobRow & Record<string, unknown>) {
  const { scratch, settings } = makeScratch();
  const backendServer = await startFakeBackend(jobRow, standardAssets());
  openBackend = backendServer;
  const client = createBackendClient({ baseUrl: backendServer.baseUrl, token: RUNNER_TOKEN });
  const asked: unknown[] = [];
  async function recordAsk(reportId: string, body: unknown) {
    asked.push({ reportId, body });
    return { lane: "ask_back" };
  }
  const deploy = fakeDeployThatLands();
  const backend = { ...client, askQuestion: recordAsk };
  const job = await backend.claimJob();
  const notifications: string[] = [];
  async function recordNotification({ title }: { title: string }) {
    notifications.push(title);
  }
  async function testsPass() {
    return { ok: true, output: "1 passed" };
  }
  const result = await runJob(job, {
    backend,
    settings: { ...settings, publishMode: "first" },
    agentCommand: process.execPath,
    agentArgs: [writeStubAgent(scratch, AGENT_THAT_ASKS)],
    runFetch: fakeFetchWithoutStoredTests().runFetch,
    runTests: testsPass,
    runDeploy: deploy.runDeploy,
    readPointer: deploy.readPointer,
    notify: recordNotification,
    openPageImplementation: pagesThatOpen(),
  });
  const statuses = backendServer.statuses.map(function statusName(entry: Record<string, unknown>) {
    return entry.status;
  });
  return { result, asked, statuses, deploy, notifications };
}

const JOB_ROW = {
  id: "rep-ask-1",
  user_id: "user-77",
  sidekick_id: "reminders",
  bundle_version: "20261011T065908559Z-1064a312",
  kind: "unknown",
  transcript: "That I can move around everywhere",
};

describe("runJob with an agent that asks", () => {
  it("posts the question, publishes nothing and posts no failure", async () => {
    const { result, asked, statuses, deploy, notifications } = await runAskJob(JOB_ROW);
    expect(result.status).toBe("asked");
    expect(asked).toEqual([{ reportId: "rep-ask-1", body: { question: "What should move?", options: ASK_OUTCOME.options, summary: ASK_OUTCOME.summary } }]);
    expect(statuses).toEqual(["running"]);
    expect(deploy.deployCalls).toEqual([]);
    expect(notifications).toContain("Asked: reminders");
  });

  it("a job that already carries the person's answer never asks again: it fails for the founder, nothing is posted to the phone", async () => {
    const answered = { ...JOB_ROW, sort: { status: "sorted", lane: "code", answer: "Drag to Reorder", question: "What should move?" } };
    const { result, asked, statuses } = await runAskJob(answered);
    expect(result.status).toBe("failed");
    expect(result.reason).toBe("asked after an answer");
    expect(asked).toEqual([]);
    expect(statuses).toEqual(["running", "failed"]);
  });
});
