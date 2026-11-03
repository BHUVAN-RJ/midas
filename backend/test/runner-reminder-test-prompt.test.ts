// Reminder Test (founder, 2026-11-02) has its own repair agent: repair job 40594f96 failed with
// 'no repair agent for Sidekick "reminder-test"'. Its prompt names the reminder-test types,
// tools and tests, never the Reminders ones, so the agent writes records the server accepts.
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { buildSystemPrompt, templateNameForSidekick } from "../../runner/lib/prompt.mjs";

const templateText = readFileSync(new URL("../../runner/agents/reminder-test.md", import.meta.url), "utf8");

describe("Reminder Test repair agent", () => {
  it("has a template of its own", () => {
    expect(templateNameForSidekick("reminder-test")).toBe("reminder-test");
  });

  it("builds a system prompt for a reminder-test job instead of refusing it", () => {
    const job = { sidekickId: "reminder-test", transcript: "add a list for photo reminders" };
    const buildPrompt = () => buildSystemPrompt({ job, reportFiles: [] });
    expect(buildPrompt).not.toThrow();
    expect(buildPrompt()).toContain("add a list for photo reminders");
  });

  it("names the reminder-test record types and tests, not the Reminders ones", () => {
    expect(templateText).toContain("`reminder-test.item`");
    expect(templateText).toContain("`reminder-test.list`");
    expect(templateText).toContain("reminder-test-tools");
    expect(templateText).not.toMatch(/\breminders\.(item|list|settings|history|import|<)/);
  });
});
