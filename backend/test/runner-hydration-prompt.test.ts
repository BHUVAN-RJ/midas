// Founder, 2026-10-25: every personal Sidekick has repair, Water (hydration) included. These check
// that a repair job for Water finds its own agent prompt, that the prompt carries Water's record
// contract, the widget rules (its widgets are records its page writes) and the guardian path, and
// that adding WIDGETS.md to the prompt values leaves care-reminders' prompt unchanged.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { buildSystemPrompt, templateNameForSidekick } from "../../runner/lib/prompt.mjs";

const REPO_ROOT = join(__dirname, "..", "..");
const WIDGETS_HEADING = "# Sidekick widgets";

function hydrationManifestText(): string {
  return readFileSync(join(REPO_ROOT, "sidekicks", "hydration", "manifest.json"), "utf8");
}

function promptFor(sidekickId: string, manifestText: string): string {
  const job = { sidekickId, kind: "change", id: "r-42", createdAt: "2026-10-25T20:00:00.000Z", transcript: "make the buttons bigger" };
  return buildSystemPrompt({ job, reportFiles: ["transcript.txt"], manifestText, checkoutRoot: REPO_ROOT, intelToolPath: "/r/intel.mjs", checkToolPath: "/r/check.mjs" });
}

describe("Water's repair agent", () => {
  it("a repair job for hydration finds the hydration prompt", () => {
    expect(templateNameForSidekick("hydration")).toBe("hydration");
  });

  it("the prompt is Water's, with its records, the widget rules and the notification contract", () => {
    const prompt = promptFor("hydration", hydrationManifestText());
    expect(prompt).toContain("# You repair one user's copy of the hydration Sidekick");
    expect(prompt).toContain("make the buttons bigger");
    expect(prompt).toContain('"$type": "hydration.day"');
    expect(prompt).toContain("Any write to today's record makes the reminders quiet for 45 minutes");
    expect(prompt).toContain(WIDGETS_HEADING);
    expect(prompt).toContain("### 4.2 The `reminder:` record");
    expect(prompt).toContain("`hydration-<topic>.test.ts`");
    expect(prompt).not.toContain("care-reminders-<topic>");
    expect(prompt).not.toMatch(/\{\{[A-Z_0-9]+\}\}/);
  });

  it("hands the guardian the check command and the reversal rule, like the other prompts", () => {
    const promptText = readFileSync(join(REPO_ROOT, "runner", "agents", "hydration.md"), "utf8");
    const start = promptText.indexOf("- When an existing test blocks what the user asked for");
    expect(start).toBeGreaterThan(-1);
    const delegation = promptText.slice(start, promptText.indexOf("\n- ", start + 1));
    expect(delegation).toContain("`node {{CHECK_TOOL}}`");
    expect(delegation).toContain("A user reversing an earlier");
  });

  // Reminders' prompt carries the widget rules too since 2026-10-26 (founder: Reminders makes its own
  // widget with the widget builder).
  it("the care-reminders prompt does not gain the widget rules", () => {
    expect(promptFor("care-reminders", "{}")).not.toContain(WIDGETS_HEADING);
  });
});
