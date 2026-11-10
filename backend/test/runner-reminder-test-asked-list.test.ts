// Founder, 2026-11-09: "add a new list that takes in only photos as reminders" twice got a
// Photos Only switch in New List (jobs 6bbabf06, 8ba03c8c) instead of a list. The Reminder Test
// repair agent must make the asked-for list itself; an option to make more comes only on top.
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { buildSystemPrompt } from "../../runner/lib/prompt.mjs";

const templateText = readFileSync(new URL("../../runner/agents/reminder-test.md", import.meta.url), "utf8");

function buildReminderTestPrompt(transcript: string): string {
  const job = { sidekickId: "reminder-test", transcript };
  return buildSystemPrompt({ job, reportFiles: [] });
}

describe("Reminder Test repair agent: asked for a list, make the list", () => {
  it("tells the agent to create the asked-for list once on load", () => {
    expect(templateText).toContain("**Asked for a list, make the list**");
    expect(templateText).toContain("create it once on load");
  });

  it("forbids answering with only a New List option", () => {
    expect(templateText).toContain("Never answer with only a way for them");
    expect(templateText).toContain("on top of the list, never instead of it");
  });

  it("puts the rule inside the supported-request cases, before the unsupported ones", () => {
    const ruleIndex = templateText.indexOf("**Asked for a list, make the list**");
    const featureCaseIndex = templateText.indexOf("4. **A new feature**");
    const unsupportedCaseIndex = templateText.indexOf("5. **Something the shell does not do.**");
    expect(ruleIndex).toBeGreaterThan(featureCaseIndex);
    expect(ruleIndex).toBeLessThan(unsupportedCaseIndex);
  });

  it("reaches the agent in the built system prompt", () => {
    const promptText = buildReminderTestPrompt("Hey can you add new list that takes in only photos as reminders");
    expect(promptText).toContain("**Asked for a list, make the list**");
    expect(promptText).toContain("Hey can you add new list that takes in only photos as reminders");
  });
});
