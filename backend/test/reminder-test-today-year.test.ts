// The date under Today shows the year: "Saturday, October 24, 2026" (user report e298466e,
// 2026-10-24: "there's no year so can you add year as well").
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const bundleHtml = readFileSync(new URL("../../sidekicks/reminder-test/index.html", import.meta.url), "utf8");

describe("Today's date shows the year", () => {
  it("formatLongDate ends with the year", () => {
    const body = bundleHtml.match(/function formatLongDate\(dateText\) \{([\s\S]*?)\n  \}/);
    expect(body).not.toBeNull();
    expect(body![1]).toMatch(/' ' \+ date\.day \+ ', ' \+ date\.year;/);
  });

  it("the Today title block uses formatLongDate for today", () => {
    expect(bundleHtml).toMatch(/titleBlockHTML\(viewName\('today'\), formatLongDate\(todayText\(\)\)/);
  });
});
