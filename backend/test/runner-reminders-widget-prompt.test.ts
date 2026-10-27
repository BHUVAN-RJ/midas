// Founder, 2026-10-26: the Reminders Sidekick now writes its own Home Screen widget (widget:today)
// through the widget builder, so its repair agent may change that widget like Water's can: the
// prompt carries docs/WIDGETS.md, names the widget record and treats a widget change as supported
// (a new piece, tap, source or size stays shell work, unsupported).
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { buildSystemPrompt } from "../../runner/lib/prompt.mjs";

const REPO_ROOT = join(__dirname, "..", "..");
const WIDGETS_HEADING = "# Sidekick widgets";

function remindersPrompt(): string {
  const manifestText = readFileSync(join(REPO_ROOT, "sidekicks", "reminders", "manifest.json"), "utf8");
  const job = { sidekickId: "reminders", kind: "change", id: "r-77", createdAt: "2026-10-26T20:00:00.000Z", transcript: "show five reminders on my widget" };
  return buildSystemPrompt({ job, reportFiles: ["transcript.txt"], manifestText, checkoutRoot: REPO_ROOT, intelToolPath: "/r/intel.mjs", checkToolPath: "/r/check.mjs" });
}

describe("Reminders' repair agent and its widget", () => {
  it("carries the widget rules, filled in", () => {
    const prompt = remindersPrompt();
    expect(prompt).toContain("show five reminders on my widget");
    expect(prompt).toContain("## WIDGETS.md (the widget: records this page writes, as built)");
    expect(prompt).toContain(WIDGETS_HEADING);
    expect(prompt).toContain("{ if: '$item.late', then: 'red', else: 'secondary' }");
    expect(prompt).not.toMatch(/\{\{[A-Z_0-9]+\}\}/);
  });

  it("names the widget record and makes a widget change supported", () => {
    const promptText = readFileSync(join(REPO_ROOT, "runner", "agents", "reminders.md"), "utf8");
    expect(promptText).toContain("3. **A change to the widget** the page writes (`widget:today`)");
    expect(promptText).toContain("- `widget:today` (`midas.widget`, the shell's own type, not declared here)");
    expect(promptText).toContain("a widget piece, tap or size the shell does not have");
    expect(promptText).not.toContain("anything outside the page (widgets,");
    expect(promptText).toContain("For case 5, 6 or 7: change nothing");
  });
});
