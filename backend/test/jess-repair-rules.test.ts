// The repair agent is told that tools.js and the manifest's agent block move with every page
// change (jess router, founder 2026-10-21, phase 5). A copy whose tools.js no longer matches its
// page is refused by the gate (sidekick-tools-gate.test.ts). Tool removal is allowed since the
// jess router review (founder 2026-10-21, item 4): that rule and its prompt lines are tested in
// jess-review-decisions.test.ts.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { buildSystemPrompt } from "../../runner/lib/prompt.mjs";

const REPO_ROOT = join(__dirname, "..", "..");

describe("the repair agent's prompt", () => {
  for (const sidekickId of ["reminders", "care-reminders"]) {
    it(`tells the ${sidekickId} agent that tools.js and the agent block move with the page`, () => {
      const manifestText = readFileSync(join(REPO_ROOT, "sidekicks", sidekickId, "manifest.json"), "utf8");
      const job = { id: "r1", sidekickId, kind: "change", transcript: "make it bigger", createdAt: "2026-10-21T00:00:00Z" };
      const prompt = buildSystemPrompt({ job, reportFiles: ["transcript.txt"], manifestText });
      expect(prompt).toContain("`sidekick/index.html`, `sidekick/tools.js` and");
      expect(prompt).toContain("## Voice tools (`sidekick/tools.js` and the `agent` block)");
      expect(prompt).toContain(`named\n  \`${sidekickId}.<verb>\``);
      expect(prompt).toContain("/* copied from index.html: begin */");
      expect(prompt).toContain(`\`${sidekickId}-tools*.test.ts\``);
    });
  }
});
