// The deploy gate checks the `repair` block (founder, 2026-11-13, "Repair facts live with each
// Sidekick"; lead request): validateManifest refuses a broken block, so a base manifest whose facts
// the one repair agent could not read never deploys. The runner uses the same function.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { checkBundleFiles, repairBlockProblems as gateRepairBlockProblems, validateManifest } from "../scripts/bundle-tools.mjs";
import { repairBlockProblems as promptRepairBlockProblems } from "../../runner/lib/prompt.mjs";

const REPO_ROOT = join(__dirname, "..", "..");
const BASE_SIDEKICKS = ["reminders", "care-reminders", "hydration", "todo", "reminder-test", "money"];

function baseFile(sidekickId: string, fileName: string): string {
  return readFileSync(join(REPO_ROOT, "sidekicks", sidekickId, fileName), "utf8");
}

function baseManifestWith(sidekickId: string, repair: unknown): Record<string, unknown> {
  const manifest = JSON.parse(baseFile(sidekickId, "manifest.json"));
  return { ...manifest, repair };
}

describe("validateManifest checks the repair block", () => {
  for (const sidekickId of BASE_SIDEKICKS) {
    it(`${sidekickId}: the base manifest with its repair block passes`, () => {
      const manifest = JSON.parse(baseFile(sidekickId, "manifest.json"));
      expect(manifest.repair.keep.length).toBeGreaterThan(0);
      expect(validateManifest(manifest, sidekickId)).toEqual([]);
    });

    it(`${sidekickId}: an empty keep list is refused`, () => {
      const manifest = baseManifestWith(sidekickId, { keep: [] });
      expect(validateManifest(manifest, sidekickId)).toEqual(["repair.keep must be a non-empty array"]);
    });
  }

  it("refuses every broken shape and accepts a manifest with no repair block", () => {
    const withoutBlock = JSON.parse(baseFile("money", "manifest.json"));
    delete withoutBlock.repair;
    expect(validateManifest(withoutBlock, "money")).toEqual([]);
    expect(validateManifest(baseManifestWith("money", "keep it"), "money")).toEqual(["repair must be an object"]);
    expect(validateManifest(baseManifestWith("money", { keep: ["a"], rules: [] }), "money")).toEqual(["repair has unknown keys: rules"]);
    expect(validateManifest(baseManifestWith("money", { keep: ["one", 2] }), "money")).toEqual(["repair.keep[1] must be a non-empty string"]);
    expect(validateManifest(baseManifestWith("money", { keep: ["a\nb"] }), "money")).toEqual(["repair.keep[0] must be one line"]);
  });

  it("the whole gate (checkBundleFiles) refuses Money's real files with a broken repair block", () => {
    const html = baseFile("money", "index.html");
    const toolsText = baseFile("money", "tools.js");
    const goodManifestText = baseFile("money", "manifest.json");
    expect(checkBundleFiles(html, goodManifestText, "money", toolsText).problems).toEqual([]);
    const brokenManifestText = JSON.stringify(baseManifestWith("money", { keep: [""] }));
    const problems = checkBundleFiles(html, brokenManifestText, "money", toolsText).problems;
    expect(problems).toContain("manifest.json: repair.keep[0] must be a non-empty string");
  });

  it("the runner and the gate use one function, so they accept the same blocks", () => {
    expect(promptRepairBlockProblems).toBe(gateRepairBlockProblems);
  });
});
