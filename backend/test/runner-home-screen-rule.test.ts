// Founder, 2026-10-26: "add rules for each of the Sidekick creators to show the exact steps on how
// to add that particular one". docs/WIDGETS.md carries the rule (every Sidekick that writes
// widget: records offers an "Add to Home Screen" row that writes the request) with the exact
// record shape, and every repair agent that changes widgets gets it through {{WIDGETS}}.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { buildSystemPrompt } from "../../runner/lib/prompt.mjs";

const REPO_ROOT = join(__dirname, "..", "..");
const RULE_HEADING = "## Add to Home Screen (founder, 2026-10-26)";
const RECORD_KIND_LINE = "kind: 'home-screen.widget',";
const RECORD_WIDGET_LINE = "widget: 'sidekick',";
const SHELL_OP = "{ op: 'shell' }";

function promptFor(sidekickId: string): string {
  const manifestText = readFileSync(join(REPO_ROOT, "sidekicks", sidekickId, "manifest.json"), "utf8");
  const job = { sidekickId, kind: "change", id: "r-90", createdAt: "2026-10-26T20:00:00.000Z", transcript: "put this on my home screen" };
  return buildSystemPrompt({ job, reportFiles: ["transcript.txt"], manifestText, checkoutRoot: REPO_ROOT, intelToolPath: "/r/intel.mjs", checkToolPath: "/r/check.mjs" });
}

describe("the Add to Home Screen rule for Sidekick makers", () => {
  it("is in docs/WIDGETS.md with the exact request and the version check", () => {
    const widgetsText = readFileSync(join(REPO_ROOT, "docs", "WIDGETS.md"), "utf8");
    const ruleStart = widgetsText.indexOf(RULE_HEADING);
    expect(ruleStart).toBeGreaterThan(-1);
    const rule = widgetsText.slice(ruleStart, widgetsText.indexOf("\n## ", ruleStart + 1));
    expect(rule).toContain("**Rule for every Sidekick that writes `widget:` records:**");
    expect(rule).toContain("\"Add to Home Screen\"");
    expect(rule).toContain(RECORD_KIND_LINE);
    expect(rule).toContain(RECORD_WIDGET_LINE);
    expect(rule).toContain("status: 'pending',");
    expect(rule).toContain(SHELL_OP);
    expect(rule).toContain("'unknown op shell'");
  });

  for (const sidekickId of ["hydration", "reminders"]) {
    it(`reaches the ${sidekickId} repair agent`, () => {
      const prompt = promptFor(sidekickId);
      expect(prompt).toContain(RULE_HEADING);
      expect(prompt).toContain(RECORD_KIND_LINE);
      expect(prompt).toContain(SHELL_OP);
      expect(prompt).toContain('"Add to Home Screen" row');
      expect(prompt).not.toMatch(/\{\{[A-Z_0-9]+\}\}/);
    });
  }

  it("the shell lists the kind the rule names", () => {
    const sheetSource = readFileSync(join(REPO_ROOT, "shell", "Midas", "HomeScreenWidgetSheet.swift"), "utf8");
    expect(sheetSource).toContain('static let homeScreenWidgetKind = "home-screen.widget"');
    expect(sheetSource).toContain("static let supportedKinds = [importAppleRemindersKind, homeScreenWidgetKind]");
  });
});
