import { createHash } from "node:crypto";
import { describe, expect, it } from "vitest";
import { bundleVersion, findForbiddenPrimitives, inlineScriptHashes } from "../scripts/bundle-tools.mjs";

describe("inlineScriptHashes", () => {
  it("hashes each inline script body exactly as CSP does", () => {
    const html = "<p>x</p><script>let a = 1;</script><script>\nlet b = 2;\n</script>";
    const expectedFirst = createHash("sha256").update("let a = 1;").digest("base64");
    const expectedSecond = createHash("sha256").update("\nlet b = 2;\n").digest("base64");
    expect(inlineScriptHashes(html)).toEqual([`'sha256-${expectedFirst}'`, `'sha256-${expectedSecond}'`]);
  });

  it("returns nothing for a page with no scripts", () => {
    expect(inlineScriptHashes("<p>static</p>")).toEqual([]);
  });
});

describe("findForbiddenPrimitives", () => {
  it("passes a plain inline-script page", () => {
    expect(findForbiddenPrimitives("<script>fetch('/x')</script>")).toEqual([]);
    expect(findForbiddenPrimitives("<p>An important reminder</p><script>let important = 1;</script>")).toEqual([]);
  });

  it("rejects external scripts, import, require and WebSocket", () => {
    expect(findForbiddenPrimitives('<script src="https://x/y.js"></script>')).toContain("script tag with attributes");
    expect(findForbiddenPrimitives("<script>import('x')</script>")).toContain("import");
    expect(findForbiddenPrimitives("<script>require('x')</script>")).toContain("require");
    expect(findForbiddenPrimitives("<script>new WebSocket('wss://x')</script>")).toContain("WebSocket");
  });
});

describe("bundleVersion", () => {
  it("differs for different content at the same time and sorts by time", () => {
    const deployedAt = new Date("2026-10-07T21:00:00.000Z");
    const later = new Date("2026-10-07T21:00:01.000Z");
    const first = bundleVersion("<p>a</p>", deployedAt);
    expect(bundleVersion("<p>b</p>", deployedAt)).not.toBe(first);
    expect(bundleVersion("<p>a</p>", later) > first).toBe(true);
  });
});
