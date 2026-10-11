// Next 7 Days in the reminders Sidekick: a day with no reminders shows only its header, with no
// empty line under it (founder, 2026-10-11).
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const bundleHtml = readFileSync(new URL("../../sidekicks/reminders/index.html", import.meta.url), "utf8");

describe("Next 7 Days empty days", () => {
  it("draws no empty line for a day without reminders", () => {
    expect(bundleHtml).not.toContain("empty-day");
  });

  it("still draws a header for every day and rows only when the day has some", () => {
    expect(bundleHtml).toMatch(/html \+= weekDayHeaderHTML\(dayName\(day\), day\);/);
    expect(bundleHtml).toMatch(/if \(dayEntries\.length > 0\) \{\s*html \+= compactRowsHtml\(dayEntries\);/);
  });
});
