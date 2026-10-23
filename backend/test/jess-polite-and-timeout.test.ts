// Staging 2026-10-22: "Can you set a reminder at 9 AM" came back "cannot act, not confident"
// (a polite request read as a question), and jess timed out at the reminder route's 4 s.
import { describe, expect, it } from "vitest";
import { buildJessRequest } from "../src/jess";
import { JESS_MODEL_TIMEOUT_MS, jessCallSettings } from "../src/jess-route";

function systemPrompt(): string {
  const request = buildJessRequest(
    { transcript: "Can you set a reminder at 9 AM", now: "2026-10-22T07:00:00Z", timeZone: "America/Los_Angeles", locale: "en-US", sidekicks: [] } as never,
    { reasoning: "off" },
  );
  return String(request.messages[0].content);
}

describe("jess prompt and timing", () => {
  it("tells the model a polite 'can you …' is a request, not a question", () => {
    const prompt = systemPrompt();
    expect(prompt).toContain("A polite request is a request, not a question");
    expect(prompt).toContain('"can you set a reminder"');
  });

  it("gives a reminder with no 'what' the title Reminder", () => {
    expect(systemPrompt()).toContain('use the title "Reminder"');
  });

  it("gives DeepSeek 8 s per attempt on the jess route", () => {
    expect(JESS_MODEL_TIMEOUT_MS).toBe(8000);
    expect(jessCallSettings.timeoutMs).toBe(8000);
  });
});
