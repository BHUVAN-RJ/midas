// Founder, 2026-11-02 and 2026-11-07: every personal Sidekick has repair, Sounds (soundboard)
// included (docs/briefs/soundboard-sidekick.md, "Repair agent"). These check that a repair job for
// Sounds finds its own agent prompt, that the prompt carries Sounds' record contract and the widget
// rules, tells the agent never to read or edit the generated starter-sounds block, and keeps the
// guardian path the other prompts have.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { buildSystemPrompt, templateNameForSidekick } from "../../runner/lib/prompt.mjs";

const REPO_ROOT = join(__dirname, "..", "..");

function soundboardManifestText(): string {
  return readFileSync(join(REPO_ROOT, "sidekicks", "soundboard", "manifest.json"), "utf8");
}

function promptFor(sidekickId: string, manifestText: string): string {
  const job = { sidekickId, kind: "change", id: "r-77", createdAt: "2026-11-07T21:00:00.000Z", transcript: "make the tiles bigger" };
  return buildSystemPrompt({ job, reportFiles: ["transcript.txt"], manifestText, checkoutRoot: REPO_ROOT, intelToolPath: "/r/intel.mjs", checkToolPath: "/r/check.mjs" });
}

describe("Sounds' repair agent", () => {
  it("a repair job for soundboard finds the soundboard prompt", () => {
    expect(templateNameForSidekick("soundboard")).toBe("soundboard");
  });

  it("the prompt is Sounds', with its records, its tests' names and the widget rules, every placeholder filled", () => {
    const prompt = promptFor("soundboard", soundboardManifestText());
    expect(prompt).toContain("# You repair one user's copy of the soundboard Sidekick");
    expect(prompt).toContain("make the tiles bigger");
    expect(prompt).toContain('"$type": "soundboard.sound"');
    expect(prompt).toContain('"$type": "soundboard.settings"');
    expect(prompt).toContain("# Sidekick widgets");
    expect(prompt).toContain("`soundboard-<topic>.test.ts`");
    expect(prompt).not.toContain("hydration-<topic>");
    expect(prompt).not.toMatch(/\{\{[A-Z_0-9]+\}\}/);
  });

  it("tells the agent the starter block is generated: never read whole, never edited by hand", () => {
    const prompt = promptFor("soundboard", soundboardManifestText());
    expect(prompt).toContain('<template id="starter-sounds">');
    expect(prompt).toContain("never read whole and never edit by hand");
    expect(prompt).toContain("Never Read the file without a `limit`");
  });

  it("tells the agent to keep playing through Web Audio, since the page's CSP has no media-src", () => {
    const prompt = promptFor("soundboard", soundboardManifestText());
    expect(prompt).toContain("no `media-src`");
    expect(prompt).toContain("decodeAudioData");
  });

  it("hands the guardian the check command and the reversal rule, like the other prompts", () => {
    const promptText = readFileSync(join(REPO_ROOT, "runner", "agents", "soundboard.md"), "utf8");
    const start = promptText.indexOf("- When an existing test blocks what the user asked for");
    expect(start).toBeGreaterThan(-1);
    const delegation = promptText.slice(start, promptText.indexOf("\n- ", start + 1));
    expect(delegation).toContain("`node {{CHECK_TOOL}}`");
    expect(delegation).toContain("A user reversing an earlier");
  });
});
