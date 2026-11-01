// The reminders Sidekick bundle (sidekicks/reminders/index.html) against the deploy gate and
// D6: one inline script, data only through the Midas store, the store helper pasted unchanged,
// and a valid manifest.
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { findForbiddenPrimitives, inlineScriptHashes } from "../scripts/bundle-tools.mjs";

const sidekickFolder = new URL("../../sidekicks/reminders/", import.meta.url);
const bundleHtml = readFileSync(new URL("index.html", sidekickFolder), "utf8");
const manifest = JSON.parse(readFileSync(new URL("manifest.json", sidekickFolder), "utf8"));
const storeHelperSource = readFileSync(new URL("../../shell/sdk/midas-store.js", import.meta.url), "utf8");

describe("reminders bundle", () => {
  it("passes the deploy gate", () => {
    expect(findForbiddenPrimitives(bundleHtml)).toEqual([]);
  });

  it("has exactly one inline script and no external resources", () => {
    const scriptTagCount = bundleHtml.split("<script").length - 1;
    expect(scriptTagCount).toBe(1);
    expect(inlineScriptHashes(bundleHtml)).toHaveLength(1);
    expect(bundleHtml).not.toMatch(/<link\b/i);
    expect(bundleHtml).not.toMatch(/\ssrc\s*=/i);
  });

  it("keeps no data in browser storage (D6)", () => {
    expect(bundleHtml).not.toMatch(/localStorage|indexedDB|sessionStorage/i);
  });

  it("contains the shell's midas-store.js unchanged", () => {
    expect(bundleHtml).toContain(storeHelperSource.trim());
  });
});

describe("reminders manifest", () => {
  it("names the Sidekick, its icon and its reads (D6)", () => {
    expect(manifest.id).toBe("reminders");
    expect(manifest.name).toBe("Reminders");
    expect(manifest.icon).toEqual({ symbol: "checklist", background: "#FF9500", backgroundDark: "#B36800" });
    expect(manifest.reads).toEqual([]);
  });
});
