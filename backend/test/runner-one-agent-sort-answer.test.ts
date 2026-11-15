// The ask-back answer reaches the repair agent (lead, 2026-11-13, after W2 Sort; founder D4 = A:
// "the answer joins the same request"). The claimed job carries sort: { status, lane, confidence,
// model, answer }; the runner keeps it (normalizeJob) and the prompt shows the answer next to the
// transcript, in the one agent's prompt and in the per-Sidekick prompts still in use.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { normalizeJob } from "../../runner/lib/backend.mjs";
import { SORT_QUESTION_TEXT, buildSystemPrompt, sortAnswerLine, transcriptWithAnswer } from "../../runner/lib/prompt.mjs";

const REPO_ROOT = join(__dirname, "..", "..");
const ANSWER_LINE = 'Asked "What should it be?", they answered: "Other icon"';

function claimedRow(sort: unknown) {
  return { id: "r-ask", user_id: "u", sidekick_id: "todo", kind: "change", transcript: "change this", sort };
}

function promptFor(job: ReturnType<typeof normalizeJob>, agentMode: string): string {
  const manifestText = readFileSync(join(REPO_ROOT, "sidekicks", "todo", "manifest.json"), "utf8");
  return buildSystemPrompt({ job, reportFiles: ["transcript.txt"], manifestText, checkoutRoot: REPO_ROOT, agentMode });
}

describe("the person's answer to the ask-back card", () => {
  it("the runner keeps sort from the claim, and null when the report has none", () => {
    const sort = { status: "answered", lane: "code", confidence: 0.91, model: "typesafe/jev-1.14", answer: "Other icon" };
    expect(normalizeJob(claimedRow(sort))?.sort).toEqual(sort);
    expect(normalizeJob(claimedRow(undefined))?.sort).toBeNull();
    expect(normalizeJob(claimedRow("odd"))?.sort).toBeNull();
  });

  it("is one line with the card's question, after the person's words", () => {
    const job = normalizeJob(claimedRow({ status: "answered", lane: "code", answer: " Other\n icon " }));
    expect(SORT_QUESTION_TEXT).toBe("What should it be?");
    expect(sortAnswerLine(job)).toBe(ANSWER_LINE);
    expect(transcriptWithAnswer(job)).toBe(`change this\n\n${ANSWER_LINE}`);
  });

  it("adds nothing when there was no card or no answer", () => {
    for (const sort of [undefined, { status: "sorted", lane: "code", answer: null }, { answer: "   " }]) {
      const job = normalizeJob(claimedRow(sort));
      expect(sortAnswerLine(job)).toBeNull();
      expect(transcriptWithAnswer(job)).toBe("change this");
    }
  });

  it("is in the transcript block of the one agent's prompt and of the per-Sidekick prompt", () => {
    const job = normalizeJob(claimedRow({ status: "answered", lane: "code", answer: "Other icon" }));
    for (const agentMode of ["shared", "per-sidekick"]) {
      const prompt = promptFor(job, agentMode);
      expect(prompt).toContain("```\nchange this\n\nAsked \"What should it be?\", they answered: \"Other icon\"\n```");
    }
  });

  it("the one agent is told what the line means", () => {
    const template = readFileSync(join(REPO_ROOT, "runner", "agents", "repair.md"), "utf8");
    expect(template).toContain('`Asked "What should it be?", they answered: "..."`, Midas asked the person one question');
  });
});
