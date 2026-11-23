// The Money page (option B "Calm", founder 2026-11-08): one inline script with the shell's store
// helper unchanged, nothing loaded from outside, the page controls every tool names, a receipt
// added from the camera or the photo library (<input type="file" accept="image/*">, kept with
// store.putFile, shown with store.fileUrl), and no purple in its colours.
import { readFileSync } from "node:fs";
import vm from "node:vm";
import { describe, expect, it } from "vitest";
import { pageActionsOf, pageOffersAction } from "../scripts/bundle-tools.mjs";

const html = readFileSync(new URL("../../sidekicks/money/index.html", import.meta.url), "utf8");
const manifest = JSON.parse(readFileSync(new URL("../../sidekicks/money/manifest.json", import.meta.url), "utf8"));

function pageScript(): string {
  const found = html.match(/<script>([\s\S]*?)<\/script>/);
  return found === null ? "" : found[1];
}

describe("money: the page", () => {
  it("pastes shell/sdk/midas-store.js unchanged, in one inline script, with nothing loaded from outside", () => {
    const storeHelper = readFileSync(new URL("../../shell/sdk/midas-store.js", import.meta.url), "utf8");
    expect(html.includes(storeHelper)).toBe(true);
    expect(html.split("<script>").length - 1).toBe(1);
    expect(html).not.toMatch(/<script\s|<link\s|https?:\/\/(?!www\.w3\.org\/2000\/svg)/);
    expect(html).not.toMatch(/localStorage|sessionStorage|indexedDB/);
  });

  it("offers every control its tools name", () => {
    for (const tool of manifest.agent.tools) {
      for (const action of pageActionsOf(tool)) {
        expect(pageOffersAction(html, action), `${tool.name}: ${action}`).toBe(true);
      }
    }
  });

  it("takes a receipt from the camera or the library and keeps it as a Midas file", () => {
    expect(html).toMatch(/<input type="file" accept="image\/\*"/);
    expect(pageScript()).toContain("store.putFile(");
    expect(pageScript()).toContain("store.fileUrl(");
  });

  it("has a light and a dark look", () => {
    expect(html).toContain("@media (prefers-color-scheme: dark)");
  });

  it("has no purple in its colours", () => {
    const hexColours = html.match(/#[0-9A-Fa-f]{6}\b/g) || [];
    expect(hexColours.length).toBeGreaterThan(10);
    for (const hex of hexColours) {
      const red = parseInt(hex.slice(1, 3), 16);
      const green = parseInt(hex.slice(3, 5), 16);
      const blue = parseInt(hex.slice(5, 7), 16);
      // Purple: red and blue both well above green, and blue close to red (a crimson such as
      // Cherry #C41E3A has far less blue than red and is not purple)
      expect(red > green + 24 && blue > green + 24 && blue > red * 0.6, hex).toBe(false);
    }
  });
});

describe("money: the page's MoneyLogic", () => {
  // The logic block run on its own, as the page runs it
  const logicStart = pageScript().indexOf("var MoneyLogic");
  const logicEnd = pageScript().indexOf("})();", logicStart) + "})();".length;
  const sandbox: { MoneyLogic?: Record<string, (...values: unknown[]) => unknown> } = {};
  vm.createContext(sandbox);
  vm.runInContext(pageScript().slice(logicStart, logicEnd) + "\nglobalThis.MoneyLogic = MoneyLogic;", sandbox);
  const Logic = sandbox.MoneyLogic!;

  it("reads typed dollars as cents and refuses anything else", () => {
    expect(Logic.parseDollars("12")).toBe(1200);
    expect(Logic.parseDollars("12.5")).toBe(1250);
    expect(Logic.parseDollars("$1,204.99")).toBe(120499);
    expect(Logic.parseDollars(".5")).toBe(50);
    expect(Logic.parseDollars("12.345")).toBeNull();
    expect(Logic.parseDollars("abc")).toBeNull();
  });

  it("writes cents as dollars with commas", () => {
    expect(Logic.formatCents(120418)).toBe("$1,204.18");
    expect(Logic.formatCents(5)).toBe("$0.05");
    expect(Logic.formatCents(-150)).toBe("-$1.50");
  });

  it("moves months across the year", () => {
    expect(Logic.shiftMonth("2026-01", -1)).toBe("2025-12");
    expect(Logic.shiftMonth("2026-12", 1)).toBe("2027-01");
  });
});
