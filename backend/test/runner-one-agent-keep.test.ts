// What every copy of a Sidekick must keep (founder, 2026-11-13, "Repair facts live with each
// Sidekick", option A): each base sidekicks/<id>/manifest.json carries a `repair` block with the
// facts that used to sit only in runner/agents/<id>.md; the one agent reads it from the platform
// checkout, never from the person's copy, as "What this Sidekick must keep". The same section names
// the primitive's core blocks as protected and says a new feature goes in its own block.
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import {
  buildSharedRepairPrompt,
  coreBlocksIn,
  protectedBlocksText,
  repairBlockProblems,
} from "../../runner/lib/prompt.mjs";

const REPO_ROOT = join(__dirname, "..", "..");
const BASE_SIDEKICKS = ["reminders", "care-reminders", "hydration", "todo", "reminder-test", "money"];
const KEEP_HEADING = "## What this Sidekick must keep";

function manifestTextOf(sidekickId: string): string {
  return readFileSync(join(REPO_ROOT, "sidekicks", sidekickId, "manifest.json"), "utf8");
}

function baseKeepOf(sidekickId: string): string[] {
  return JSON.parse(manifestTextOf(sidekickId)).repair.keep;
}

function promptFor(sidekickId: string, manifestText: string, checkoutRoot = REPO_ROOT): string {
  return buildSharedRepairPrompt({
    job: { sidekickId, kind: "change", id: "r-keep", createdAt: "2026-11-13T10:00:00.000Z", transcript: "make it blue" },
    reportFiles: ["transcript.txt"],
    manifestText,
    checkoutRoot,
    intelToolPath: "/r/intel.mjs",
    checkToolPath: "/r/check.mjs",
  });
}

// The "What this Sidekick must keep" section alone, up to the next "## " heading.
function keepSectionOf(prompt: string): string {
  const start = prompt.indexOf(KEEP_HEADING);
  expect(start).toBeGreaterThan(-1);
  const end = prompt.indexOf("\n## ", start + KEEP_HEADING.length);
  return prompt.slice(start, end);
}

// A copy's manifest with its own `repair` block (a repair could write one) and other edits.
function copyManifestWith(sidekickId: string, changes: Record<string, unknown>): string {
  const manifest = JSON.parse(manifestTextOf(sidekickId));
  const changed = { ...manifest, ...changes };
  return JSON.stringify(changed, null, 2);
}

// A checkout with only this Sidekick's base manifest, so the test controls its repair block.
function scratchCheckoutWith(sidekickId: string, baseManifest: Record<string, unknown>): string {
  const checkoutRoot = mkdtempSync(join(tmpdir(), "w4-keep-"));
  mkdirSync(join(checkoutRoot, "sidekicks", sidekickId), { recursive: true });
  writeFileSync(join(checkoutRoot, "sidekicks", sidekickId, "manifest.json"), JSON.stringify(baseManifest));
  return checkoutRoot;
}

describe("each base manifest carries a repair block", () => {
  for (const sidekickId of BASE_SIDEKICKS) {
    it(`${sidekickId}: a valid repair block with at least one fact`, () => {
      const manifest = JSON.parse(manifestTextOf(sidekickId));
      expect(repairBlockProblems(manifest)).toEqual([]);
      expect(manifest.repair.keep.length).toBeGreaterThan(0);
    });
  }

  // The facts named in the founder's decision, which until now lived only in runner/agents/<id>.md.
  it("holds the facts the per-Sidekick files had: Water's widget tap and 45-minute quiet", () => {
    const water = baseKeepOf("hydration").join("\n");
    expect(water).toContain("A widget tap");
    expect(water).toContain("Never rewrite `ml` from `entries`");
    expect(water).toContain("silences the reminders for 45 minutes");
  });

  it("Money: integer cents, USD only, categories never removed or renamed", () => {
    const money = baseKeepOf("money").join("\n");
    expect(money).toContain("integer cents");
    expect(money).toContain('`currency` is `"USD"` only');
    expect(money).toContain("Categories are added, never removed or renamed");
  });

  it("Care: everyHours next to repeat, never inside it", () => {
    const care = baseKeepOf("care-reminders").join("\n");
    expect(care).toContain("`everyHours` (2, 3 or 4) is a field of its own next to `repeat`, never inside it");
  });

  it("Reminders and its test copy: history packs many done items to a record", () => {
    for (const sidekickId of ["reminders", "reminder-test"]) {
      const reminders = baseKeepOf(sidekickId).join("\n");
      expect(reminders).toContain("packed many to a record in `history:<nnnn>`");
    }
  });
});

describe("repairBlockProblems", () => {
  it("accepts a manifest with no repair block", () => {
    expect(repairBlockProblems({ id: "x" })).toEqual([]);
  });

  it("refuses a block that is not { keep: [one-line facts] }", () => {
    expect(repairBlockProblems({ repair: ["a"] })).toEqual(["repair must be an object"]);
    expect(repairBlockProblems({ repair: { keep: [] } })).toEqual(["repair.keep must be a non-empty array"]);
    expect(repairBlockProblems({ repair: { keep: ["a"], extra: 1 } })).toEqual(["repair has unknown keys: extra"]);
    expect(repairBlockProblems({ repair: { keep: ["ok", ""] } })).toEqual(["repair.keep[1] must be a non-empty string"]);
    expect(repairBlockProblems({ repair: { keep: ["two\nlines"] } })).toEqual(["repair.keep[0] must be one line"]);
    expect(repairBlockProblems({ repair: { keep: ["x".repeat(601)] } })).toEqual(["repair.keep[0] is longer than 600 characters"]);
  });
});

describe("the one agent's prompt: What this Sidekick must keep", () => {
  for (const sidekickId of BASE_SIDEKICKS) {
    it(`${sidekickId}: every fact of the base repair block is in the section`, () => {
      const section = keepSectionOf(promptFor(sidekickId, manifestTextOf(sidekickId)));
      for (const fact of baseKeepOf(sidekickId)) {
        expect(section).toContain(`- ${fact}`);
      }
    });
  }

  it("reads the base manifest from the platform checkout, never the person's copy", () => {
    const baseManifest = JSON.parse(manifestTextOf("reminders"));
    const checkoutRoot = scratchCheckoutWith("reminders", { ...baseManifest, repair: { keep: ["Platform fact only."] } });
    const copyText = copyManifestWith("reminders", { repair: { keep: ["Copy fact the agent wrote."] } });
    const section = keepSectionOf(promptFor("reminders", copyText, checkoutRoot));
    expect(section).toContain("- Platform fact only.");
    expect(section).not.toContain("Copy fact the agent wrote.");
  });

  it("refuses the job when the base repair block is broken, instead of running without its facts", () => {
    const baseManifest = JSON.parse(manifestTextOf("money"));
    const checkoutRoot = scratchCheckoutWith("money", { ...baseManifest, repair: { keep: [] } });
    expect(() => promptFor("money", manifestTextOf("money"), checkoutRoot)).toThrow("sidekicks/money/manifest.json repair block");
  });

  it("a Sidekick the platform does not have gets the section with no facts, not an error", () => {
    const checkoutRoot = mkdtempSync(join(tmpdir(), "w4-keep-none-"));
    const section = keepSectionOf(promptFor("money", manifestTextOf("money"), checkoutRoot));
    expect(section).toContain("the platform has no `sidekicks/money/manifest.json`");
  });

  it("a request that can only break a kept fact is unsupported (case 9)", () => {
    const prompt = promptFor("money", manifestTextOf("money"));
    expect(prompt).toContain("9. **Needs breaking what this Sidekick must keep**");
    expect(prompt).toContain("For case 6, 7, 8 or 9: change nothing");
    expect(keepSectionOf(prompt)).toContain("is\ncase 9 (section \"First\")");
  });
});

describe("protected primitive blocks", () => {
  const LOOK_TABLE = [
    "| ID | Name | Tag | Default variation |",
    "|---|---|---|---|",
    "| TD-LOOK-01 | Page style | core | `look: paper` |",
    "| TD-LOOK-05 | Density | on request | `density: comfy` |",
  ].join("\n");

  it("coreBlocksIn reads the core rows of a block table and skips the on-request ones", () => {
    expect(coreBlocksIn(LOOK_TABLE)).toEqual([{ id: "TD-LOOK-01", name: "Page style" }]);
  });

  it("To-Do's prompt names its core blocks as protected, and not its on-request ones", () => {
    const section = keepSectionOf(promptFor("todo", manifestTextOf("todo")));
    expect(section).toContain("### Protected blocks");
    expect(section).toContain("- `TD-LOOK-01` Page style (`docs/primitives/todo/blocks/look.md`)");
    expect(section).toContain("- `TD-ITEM-04` Repeat (`docs/primitives/todo/blocks/item.md`)");
    expect(section).toContain("- `TD-DONE-06` Undo with name");
    expect(section).not.toContain("TD-LOOK-05");
    expect(section).not.toContain("TD-LOOK-06");
  });

  it("the rule: do not change what a protected block does; a new feature goes in its own block", () => {
    const section = keepSectionOf(promptFor("todo", manifestTextOf("todo")));
    expect(section).toContain("Do not change what a protected block does");
    expect(section).toContain("A new\nfeature goes in its own block");
    expect(section).toContain("It calls a protected block's functions; it never\nrewrites them.");
  });

  it("a Sidekick with no primitive says it has no protected blocks", () => {
    const section = keepSectionOf(promptFor("money", manifestTextOf("money")));
    expect(section).toContain("None: this Sidekick was not built from primitive blocks.");
  });

  it("the protected list comes from the base manifest: a copy naming another primitive changes nothing", () => {
    const copyText = copyManifestWith("money", { primitive: "todo" });
    const section = keepSectionOf(promptFor("money", copyText));
    expect(section).not.toContain("TD-LOOK-01");
    expect(protectedBlocksText({ baseManifest: { primitive: "todo" }, sidekickId: "money", checkoutRoot: REPO_ROOT })).toContain("TD-LOOK-01");
  });
});
