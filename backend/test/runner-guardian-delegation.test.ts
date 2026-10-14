// The repair agent hands test-guardian what the updated guardian needs (main f17f8bb,
// 2026-10-13): the user's repair request as the authority for that user's copy (report id, date,
// transcript words), and treats REFUSED and NEEDS-EVIDENCE alike (the test stands).
import { describe, expect, it } from "vitest";
import { buildSystemPrompt } from "../../runner/lib/prompt.mjs";
import { makeScratch } from "./helpers/runner-fixture";

describe("delegation to test-guardian in the agent prompt", () => {
  const { checkout } = makeScratch();
  const job = {
    id: "rep-42",
    sidekickId: "reminders",
    kind: "change",
    createdAt: "2026-10-13T20:15:00.000Z",
    transcript: "sort my lists by name, not by colour",
  };
  const prompt = buildSystemPrompt({ job, reportFiles: ["transcript.txt"], checkoutRoot: checkout, intelToolPath: "/r/intel.mjs", checkToolPath: "/r/check.mjs" });

  it("names the user's repair request as the authority, with the report id and date filled in", () => {
    expect(prompt).toContain("report id rep-42");
    expect(prompt).toContain("reported 2026-10-13T20:15:00.000Z");
    expect(prompt).toContain("the user's words from the transcript, quoted");
    expect(prompt).toContain("covers this\n  user's copy only");
    expect(prompt).not.toContain("{{REPORT_ID}}");
    expect(prompt).not.toContain("{{REPORTED_AT}}");
  });

  it("expects the guardian's three answers and stops on the two that do not accept", () => {
    expect(prompt).toContain("ACCEPTED, REFUSED or NEEDS-EVIDENCE");
    expect(prompt).toContain("On REFUSED or NEEDS-EVIDENCE the test stands");
    expect(prompt).toContain("finish as `unsupported` with the guardian's answer in the summary");
  });

  it("keeps the add-only rule: the agent never changes a test or the log itself", () => {
    expect(prompt).toContain("Never change or delete an existing test file, and never write `TEST_CHANGES.md`");
    expect(prompt).toContain("subagent type `test-guardian`");
  });

  it("fills unknown when the claim reply carries no created-at", () => {
    const withoutDate = buildSystemPrompt({ job: { ...job, createdAt: undefined }, reportFiles: ["transcript.txt"], checkoutRoot: checkout, intelToolPath: "/r/intel.mjs", checkToolPath: "/r/check.mjs" });
    expect(withoutDate).toContain("reported unknown");
  });
});
