// Docs, briefs and repair prompts describe only the current record format (founder, 2026-10-20:
// old formats are quarantined in docs/legacy/LEGACY-RECORD-FORMATS.DO-NOT-READ.md). Each check
// names a marker of the old shapes; it fails if that text comes back outside the quarantine file.
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { buildSystemPrompt } from "../../runner/lib/prompt.mjs";

const repoRoot = new URL("../../", import.meta.url);

function readRepoText(relativePath: string): string {
  return readFileSync(new URL(relativePath, repoRoot), "utf8");
}

// Tracked files only, so untracked drafts in a checkout do not decide the result.
function trackedMarkdownFiles(): string[] {
  const listing = execFileSync("git", ["ls-files", "--", "docs", "runner"], { cwd: fileURLToPath(repoRoot), encoding: "utf8" });
  const allPaths = listing.split("\n");
  const markdownPaths = allPaths.filter(isSweptMarkdown);
  return markdownPaths;
}

// The quarantine file holds the old shapes by design; PRODUCT.md is the lead's to change.
function isSweptMarkdown(path: string): boolean {
  if (!path.endsWith(".md")) {
    return false;
  }
  return !path.startsWith("docs/legacy/") && path !== "docs/PRODUCT.md";
}

function promptFor(sidekickId: string): string {
  const job = { id: "rep-1", sidekickId, kind: "bug", transcript: "t", createdAt: "2026-10-20T10:00:00.000Z" };
  const manifestText = readRepoText(`sidekicks/${sidekickId}/manifest.json`);
  return buildSystemPrompt({ job, reportFiles: ["transcript.txt"], manifestText });
}

const OLD_SHAPE_MARKERS: RegExp[] = [
  /`task:/,
  /task:<id>/,
  /stored as task:/,
  /\{ at, title, body/,
  /epoch milliseconds/,
  /~ruleId/,
  /Retired, never write them/,
];

describe("docs and prompts on the current record format only", () => {
  it("finds no old-shape marker in any tracked doc, brief or runner file", () => {
    const files = trackedMarkdownFiles();
    expect(files).toContain("docs/NOTIFICATIONS.md");
    expect(files).toContain("runner/agents/reminders.md");
    const hits: string[] = [];
    for (const file of files) {
      const text = readRepoText(file);
      for (const marker of OLD_SHAPE_MARKERS) {
        if (marker.test(text)) {
          hits.push(`${file}: ${marker}`);
        }
      }
    }
    expect(hits).toEqual([]);
  });

  it("documents notes, not body, on the reminder record", () => {
    const notifications = readRepoText("docs/NOTIFICATIONS.md");
    expect(notifications).not.toContain("`body`");
    expect(notifications).not.toMatch(/^\s*body:/m);
    expect(notifications).toContain("| `notes` | string | no |");
  });

  it("gives both repair agents only today's shapes", () => {
    for (const sidekickId of ["reminders", "care-reminders"]) {
      const prompt = promptFor(sidekickId);
      expect(prompt).not.toContain("task:");
      expect(prompt).not.toContain("`body`");
      expect(prompt).not.toContain("epoch");
      expect(prompt).not.toContain("~ruleId");
      expect(prompt).toContain("stays as it is; write only the");
    }
  });

  it("keeps the docs section of the quarantine file filled", () => {
    const quarantine = readRepoText("docs/legacy/LEGACY-RECORD-FORMATS.DO-NOT-READ.md");
    const docsSectionStart = quarantine.indexOf("## Docs, briefs and prompts");
    expect(docsSectionStart).toBeGreaterThan(-1);
    const docsSection = quarantine.slice(docsSectionStart);
    expect(docsSection).not.toContain("(filled by the docs sweep)");
    expect(docsSection).toContain("### Repair prompts (runner/agents), as they were");
  });
});
