// The title being typed in a row wraps onto the next line instead of scrolling sideways in one
// line (user report 13edb182, 2026-10-16). Return still starts the next reminder; a title stays
// one line of text. Moved from R J's repaired copy into the base (founder, 2026-10-21, PRODUCT.md
// "Repairs that fix wrong behaviour go to the base").
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const bundleHtml = readFileSync(new URL("../../sidekicks/reminder-test/index.html", import.meta.url), "utf8");

describe("row title wraps while typing", () => {
  it("the row's title box is a one-row textarea, not a single-line input", () => {
    expect(bundleHtml).toMatch(/<textarea id="edit-input" class="row-input" rows="1"/);
    expect(bundleHtml).not.toMatch(/<input id="edit-input"/);
  });

  it("the title box wraps and grows with its text", () => {
    const rule = bundleHtml.match(/\.row-input \{([\s\S]*?)\}/);
    expect(rule).not.toBeNull();
    expect(rule![1]).toMatch(/resize: none/);
    expect(rule![1]).toMatch(/overflow: hidden/);
    expect(bundleHtml).toMatch(/input\.style\.height = input\.scrollHeight \+ 'px'/);
  });

  it("Return still starts the next reminder and line breaks never reach the title", () => {
    const keydown = bundleHtml.match(/function handleEditKeydown\(event\) \{([\s\S]*?)\n  \}/);
    expect(keydown).not.toBeNull();
    expect(keydown![1]).toMatch(/event\.key === 'Enter'[\s\S]*event\.preventDefault\(\);[\s\S]*handleReturn\(\)/);
    const onInput = bundleHtml.match(/function handleEditInput\(event\) \{([\s\S]*?)\n  \}/);
    expect(onInput).not.toBeNull();
    expect(onInput![1]).toMatch(/replace\(\/\\r\?\\n\/g, ' '\)/);
  });
});
