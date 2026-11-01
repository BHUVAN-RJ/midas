// Every Sidekick tile has a light and a dark variant (founder, 2026-10-31, docs/briefs/
// build-22-2026-10-31.md "Icons"; docs/ICONS.md): every manifest in the repo gives
// icon.backgroundDark, the deploy gate refuses one that is not a colour (and still takes a manifest
// from before build 22 without it), and the repair agents and Make's builder are told to write both.
import { readdirSync, readFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { validateManifest } from "../scripts/bundle-tools.mjs";
import { buildSystemPrompt, TEMPLATE_BY_SIDEKICK } from "../../runner/lib/prompt.mjs";

const REPO_ROOT = join(__dirname, "..", "..");
const HEX = /^#[0-9A-Fa-f]{6}$/;

// Every manifest.json kept in the repo: base Sidekicks and user copies
function repoManifests(): Array<{ path: string; manifest: Record<string, unknown> }> {
  const found: Array<{ path: string; manifest: Record<string, unknown> }> = [];
  const sidekicksFolder = join(REPO_ROOT, "sidekicks");
  for (const sidekickId of readdirSync(sidekicksFolder)) {
    const path = join(sidekicksFolder, sidekickId, "manifest.json");
    if (existsSync(path)) {
      found.push({ path, manifest: JSON.parse(readFileSync(path, "utf8")) });
    }
  }
  const copiesFolder = join(REPO_ROOT, "copies");
  for (const sidekickId of readdirSync(copiesFolder)) {
    for (const copyName of readdirSync(join(copiesFolder, sidekickId))) {
      const path = join(copiesFolder, sidekickId, copyName, "sidekick", "manifest.json");
      if (existsSync(path)) {
        found.push({ path, manifest: JSON.parse(readFileSync(path, "utf8")) });
      }
    }
  }
  return found;
}

// Relative luminance (WCAG) of #RRGGBB
function luminance(hex: string): number {
  const channels = [1, 3, 5].map((start) => parseInt(hex.slice(start, start + 2), 16) / 255);
  const linear = channels.map((channel) => (channel <= 0.03928 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4));
  return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2];
}

describe("Sidekick tiles: light and dark", () => {
  it("every manifest in the repo has a dark tile colour, darker than its light one", () => {
    const manifests = repoManifests();
    expect(manifests.length).toBeGreaterThanOrEqual(4);
    for (const { path, manifest } of manifests) {
      const icon = manifest.icon as Record<string, string>;
      expect(icon.background, path).toMatch(HEX);
      expect(icon.backgroundDark, path).toMatch(HEX);
      expect(luminance(icon.backgroundDark), path).toBeLessThan(luminance(icon.background));
    }
  });

  it("the deploy gate refuses a dark colour that is not #RRGGBB, and takes one or none", () => {
    const base = { id: "plants", name: "Plants", reads: [], icon: { symbol: "leaf", background: "#9CAF88" } };
    expect(validateManifest(base, "plants")).toEqual([]);
    expect(validateManifest({ ...base, icon: { ...base.icon, backgroundDark: "#5E6B52" } }, "plants")).toEqual([]);
    expect(validateManifest({ ...base, icon: { ...base.icon, backgroundDark: "dark green" } }, "plants")).toEqual([
      "icon.backgroundDark must be a color like #B36800",
    ]);
    expect(validateManifest({ ...base, icon: { ...base.icon, backgroundDark: null } }, "plants")).toEqual([
      "icon.backgroundDark must be a color like #B36800",
    ]);
  });

  it("every repair agent's prompt carries the icon rule and docs/ICONS.md", () => {
    const iconsDoc = readFileSync(join(REPO_ROOT, "docs", "ICONS.md"), "utf8");
    for (const sidekickId of Object.keys(TEMPLATE_BY_SIDEKICK)) {
      const manifestText = readFileSync(join(REPO_ROOT, "sidekicks", sidekickId, "manifest.json"), "utf8");
      const job = { sidekickId, kind: "change", id: "r-1", createdAt: "2026-10-31T20:00:00.000Z", transcript: "make it green" };
      const prompt = buildSystemPrompt({ job, reportFiles: ["transcript.txt"], manifestText, checkoutRoot: REPO_ROOT, intelToolPath: "/r/i.mjs", checkToolPath: "/r/c.mjs" });
      expect(prompt, sidekickId).not.toContain("{{ICONS}}");
      expect(prompt, sidekickId).toContain("change `icon.background` and\n`icon.backgroundDark` together");
      expect(prompt, sidekickId).toContain(iconsDoc.trim());
    }
  });

  it("Make's builder instructions name the icon rule", () => {
    const builder = readFileSync(join(REPO_ROOT, "docs", "MAKE-BUILDER.md"), "utf8");
    expect(builder).toContain("`backgroundDark`");
    expect(builder).toContain("docs/ICONS.md");
  });
});
