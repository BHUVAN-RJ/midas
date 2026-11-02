// Founder, 2026-10-25: every personal Sidekick has repair; the To-Do Sidekick
// (docs/briefs/todo-sidekick.md, step 5, 2026-10-31) included. These check that a repair job for
// todo finds its own agent prompt, that the prompt carries To-Do's record contract (reminder: keys
// with recur, at only when timed), the voice tools and the guardian path, and that the other
// Sidekicks' prompts are unchanged by it.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { buildSystemPrompt, templateNameForSidekick } from "../../runner/lib/prompt.mjs";

const REPO_ROOT = join(__dirname, "..", "..");

function todoManifestText(): string {
  return readFileSync(join(REPO_ROOT, "sidekicks", "todo", "manifest.json"), "utf8");
}

function promptFor(sidekickId: string, manifestText: string): string {
  const job = { sidekickId, kind: "feature", id: "r-77", createdAt: "2026-10-31T20:00:00.000Z", transcript: "let me repeat every two weeks" };
  return buildSystemPrompt({ job, reportFiles: ["transcript.txt"], manifestText, checkoutRoot: REPO_ROOT, intelToolPath: "/r/intel.mjs", checkToolPath: "/r/check.mjs" });
}

describe("To-Do's repair agent", () => {
  it("a repair job for todo finds the todo prompt", () => {
    expect(templateNameForSidekick("todo")).toBe("todo");
  });

  it("the prompt is To-Do's, with its records, the voice tools and the notification contract", () => {
    const prompt = promptFor("todo", todoManifestText());
    expect(prompt).toContain("# You repair one user's copy of the todo Sidekick");
    expect(prompt).toContain("let me repeat every two weeks");
    expect(prompt).toContain('"$type": "todo.item"');
    expect(prompt).toContain('"$type": "todo.settings"');
    expect(prompt).toContain("The repeat is `recur`, not the engine's `repeat`");
    expect(prompt).toContain("an untimed to-do has no `at` and");
    expect(prompt).toContain("`todo.<verb>`");
    expect(prompt).toContain("### 4.2 The `reminder:` record");
    expect(prompt).toContain("# Sidekick widgets");
    expect(prompt).toContain("`todo-<topic>.test.ts`");
    expect(prompt).toContain("r-77");
    expect(prompt).not.toContain("hydration-<topic>");
    expect(prompt).not.toMatch(/\{\{[A-Z_0-9]+\}\}/);
  });

  it("hands the guardian the check command and the reversal rule, like the other prompts", () => {
    const promptText = readFileSync(join(REPO_ROOT, "runner", "agents", "todo.md"), "utf8");
    const start = promptText.indexOf("- When an existing test blocks what the user asked for");
    expect(start).toBeGreaterThan(-1);
    const delegation = promptText.slice(start, promptText.indexOf("\n- ", start + 1));
    expect(delegation).toContain("`node {{CHECK_TOOL}}`");
    expect(delegation).toContain("A user reversing an earlier");
  });

  it("leaves Water's prompt Water's", () => {
    const waterManifest = readFileSync(join(REPO_ROOT, "sidekicks", "hydration", "manifest.json"), "utf8");
    const waterPrompt = promptFor("hydration", waterManifest);
    expect(waterPrompt).toContain("# You repair one user's copy of the hydration Sidekick");
    expect(waterPrompt).not.toContain("todo.item");
  });
});
