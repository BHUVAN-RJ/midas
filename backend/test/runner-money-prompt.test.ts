// Founder, 2026-11-02: no Sidekick ships without its repair agent; Money (founder, 2026-11-08)
// included. These check that a repair job for money finds its own agent prompt, that the prompt
// carries Money's record contract (integer cents, USD, the receipt from jess), the add-only rule
// for categories, the behaviour-not-looks test rule (2026-10-30) and the guardian path, and that
// the other Sidekicks' prompts are unchanged by it.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { buildSystemPrompt, templateNameForSidekick } from "../../runner/lib/prompt.mjs";

const REPO_ROOT = join(__dirname, "..", "..");

function moneyManifestText(): string {
  return readFileSync(join(REPO_ROOT, "sidekicks", "money", "manifest.json"), "utf8");
}

function promptFor(sidekickId: string, manifestText: string): string {
  const job = { sidekickId, kind: "feature", id: "r-88", createdAt: "2026-11-08T20:00:00.000Z", transcript: "add a Pets category" };
  return buildSystemPrompt({ job, reportFiles: ["transcript.txt"], manifestText, checkoutRoot: REPO_ROOT, intelToolPath: "/r/intel.mjs", checkToolPath: "/r/check.mjs" });
}

describe("Money's repair agent", () => {
  it("a repair job for money finds the money prompt", () => {
    expect(templateNameForSidekick("money")).toBe("money");
  });

  it("the prompt is Money's, with its records, the receipt handover and the add-only categories", () => {
    const prompt = promptFor("money", moneyManifestText());
    expect(prompt).toContain("# You repair one user's copy of the money Sidekick");
    expect(prompt).toContain("add a Pets category");
    expect(prompt).toContain('"$type": "money.expense"');
    expect(prompt).toContain("**integer cents**");
    expect(prompt).toContain('Keep `"midas/photo": "receipt"` on `money.add_expense`');
    expect(prompt).toContain("**Never remove or rename a category**");
    expect(prompt).toContain("`money.<verb>`");
    expect(prompt).toContain("`money-<topic>.test.ts`");
    expect(prompt).toContain("r-88");
    expect(prompt).not.toContain("hydration-<topic>");
    expect(prompt).not.toContain("hydration.day");
    expect(prompt).not.toMatch(/\{\{[A-Z_0-9]+\}\}/);
  });

  it("asks for behaviour tests and tells the guardian about detail-only tests (2026-10-30)", () => {
    const promptText = readFileSync(join(REPO_ROOT, "runner", "agents", "money.md"), "utf8");
    expect(promptText).toContain("**A new test checks what the copy does, not where things sit or how they look**");
    const start = promptText.indexOf("- When an existing test blocks what the user asked for");
    expect(start).toBeGreaterThan(-1);
    const delegation = promptText.slice(start, promptText.indexOf("\n- ", start + 1));
    expect(delegation).toContain("When the test only pins a position, an order, a count that grows");
    expect(delegation).toContain("`node {{CHECK_TOOL}}`");
    expect(delegation).toContain("A user reversing an earlier");
  });

  it("leaves Water's prompt Water's", () => {
    const waterManifest = readFileSync(join(REPO_ROOT, "sidekicks", "hydration", "manifest.json"), "utf8");
    const waterPrompt = promptFor("hydration", waterManifest);
    expect(waterPrompt).toContain("# You repair one user's copy of the hydration Sidekick");
    expect(waterPrompt).not.toContain("money.expense");
  });
});
