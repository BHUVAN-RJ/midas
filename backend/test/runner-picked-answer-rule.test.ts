import { describe, expect, it } from "vitest";
// @ts-expect-error plain ESM runner module without types
import { PICKED_ANSWER_RULE, transcriptWithAnswer } from "../../runner/lib/prompt.mjs";

// Job d82c7640 (2026-11-22): To-Do "Make this different", the person picked "Other layout" on the
// card, and the agent answered unsupported as unclear. A picked answer must carry the rule that it
// is never unclear; a request with no card answer must not.

describe("a picked card answer is never unclear", () => {
  it("adds the rule after the answer line", () => {
    const job = { transcript: "Make this different", sort: { answer: "Other layout" } };
    const text = transcriptWithAnswer(job);
    expect(text).toContain('they answered: "Other layout"');
    expect(text).toContain(PICKED_ANSWER_RULE);
    expect(text.indexOf(PICKED_ANSWER_RULE)).toBeGreaterThan(text.indexOf("Other layout"));
    expect(PICKED_ANSWER_RULE).toMatch(/never because the request is vague/);
  });

  it("leaves a request with no card answer as the person's words only", () => {
    const job = { transcript: "Add a few emojis on the screen", sort: null };
    expect(transcriptWithAnswer(job)).toBe("Add a few emojis on the screen");
  });
});
