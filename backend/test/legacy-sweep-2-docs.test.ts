// Live and staging records were converted on 2026-10-20 (founder): no code reads or writes an old
// record shape any more, and the one-time migration is retired. Docs, briefs and repair prompts
// must not describe upgrading old records, on read or in memory, or the migration scripts as
// something that runs. Each marker below is first shown to match the sentence it was written for.
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { buildSystemPrompt } from "../../runner/lib/prompt.mjs";

const repoRoot = new URL("../../", import.meta.url);

function readRepoText(relativePath: string): string {
  return readFileSync(new URL(relativePath, repoRoot), "utf8");
}

// The quarantine file holds the history by design; PRODUCT.md is the lead's to change.
function isSweptMarkdown(path: string): boolean {
  if (!path.endsWith(".md")) {
    return false;
  }
  return !path.startsWith("docs/legacy/") && path !== "docs/PRODUCT.md";
}

// Tracked files only, so untracked drafts in a checkout do not decide the result.
function trackedMarkdownFiles(): string[] {
  const listing = execFileSync("git", ["ls-files", "--", "docs", "runner"], { cwd: fileURLToPath(repoRoot), encoding: "utf8" });
  const allPaths = listing.split("\n");
  const markdownPaths = allPaths.filter(isSweptMarkdown);
  return markdownPaths;
}

function promptFor(sidekickId: string): string {
  const job = { id: "rep-1", sidekickId, kind: "bug", transcript: "t", createdAt: "2026-10-20T10:00:00.000Z" };
  const manifestText = readRepoText(`sidekicks/${sidekickId}/manifest.json`);
  return buildSystemPrompt({ job, reportFiles: ["transcript.txt"], manifestText });
}

// Each marker with a sentence the docs held before this sweep, so the marker is known to catch it.
const RETIRED_UPGRADE_MARKERS: { pattern: RegExp; oldText: string }[] = [
  { pattern: /migrate-records\.mjs/, oldText: "`node scripts/migrate-records.mjs --env live --dry-run`" },
  { pattern: /record-upgrades\.mjs/, oldText: "upgraded in memory first with `backend/scripts/record-upgrades.mjs`" },
  { pattern: /upgraded in memory/, oldText: "every record the reporter has, older shapes upgraded in memory, passes" },
  { pattern: /upgrades older records/, oldText: "The page's code that upgrades older records when it reads them stays as it is" },
  { pattern: /folds older records/, oldText: "The page's code that folds older records into their item on load" },
  { pattern: /older records (upgraded on read|folded in on load)/, oldText: "older records upgraded on read" },
  { pattern: /by the page on read/, oldText: "carried into `snoozes` by the migration and by the page on read" },
  { pattern: /upgrade[- ]on[- ]read/i, oldText: "unless the change ships its migration (rewrite ops plus upgrade-on-read)" },
  { pattern: /ISO 8601 date or epoch/, oldText: "`reminder.at must be an ISO 8601 date or epoch milliseconds`" },
];

describe("docs and prompts after the live conversion (founder, 2026-10-20)", () => {
  it("each marker catches the old sentence it was written for", () => {
    const missed: string[] = [];
    for (const marker of RETIRED_UPGRADE_MARKERS) {
      if (!marker.pattern.test(marker.oldText)) {
        missed.push(String(marker.pattern));
      }
    }
    expect(missed).toEqual([]);
  });

  it("finds no upgrade-on-read or migration-script text in any tracked doc, brief or runner file", () => {
    const files = trackedMarkdownFiles();
    expect(files).toContain("runner/README.md");
    expect(files).toContain("docs/briefs/data-rework-product-changes.md");
    const hits: string[] = [];
    for (const file of files) {
      const text = readRepoText(file);
      for (const marker of RETIRED_UPGRADE_MARKERS) {
        if (marker.pattern.test(text)) {
          hits.push(`${file}: ${marker.pattern}`);
        }
      }
    }
    expect(hits).toEqual([]);
  });

  it("tells both repair agents to write only the declared types, with no page upgrade to keep", () => {
    for (const sidekickId of ["reminders", "care-reminders"]) {
      const prompt = promptFor(sidekickId);
      expect(prompt).toContain("Write only the types above.");
      expect(prompt).not.toMatch(/older records/);
      expect(prompt).not.toMatch(/upgrade/i);
    }
  });

  it("checks the reporter's records as stored, with no upgrade first", () => {
    const readme = readRepoText("runner/README.md");
    expect(readme).toContain("every record, as stored, must pass");
    expect(readme).not.toMatch(/upgrade/i);
  });

  it("quotes the shell's at message without the epoch form", () => {
    const notifications = readRepoText("docs/NOTIFICATIONS.md");
    expect(notifications).toContain("- `reminder.at must be an ISO 8601 date` (when `at` is present but not a date)");
  });
});
