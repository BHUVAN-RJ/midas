// Scripts must turn their own location into a file path with fileURLToPath, never URL.pathname:
// pathname keeps "%20" for a space, so a checkout under "Application Support" (the repair runner's)
// could not find its files (founder's live deploy, 2026-10-20).
import { readdirSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { describe, expect, it } from "vitest";

const scriptsFolder = resolve(__dirname, "../scripts");

function scriptsUsingPathname(): string[] {
  const offenders: string[] = [];
  for (const name of readdirSync(scriptsFolder)) {
    if (!name.endsWith(".mjs")) {
      continue;
    }
    const text = readFileSync(join(scriptsFolder, name), "utf8");
    if (/import\.meta\.url\)\.pathname/.test(text)) {
      offenders.push(name);
    }
  }
  return offenders;
}

describe("script paths", () => {
  it("never read a file path from URL.pathname", () => {
    expect(scriptsUsingPathname()).toEqual([]);
  });

  it("decodes a space in the script's folder", async () => {
    const { fileURLToPath } = await import("node:url");
    const location = new URL("file:///Users/x/Library/Application%20Support/midas/backend/scripts/a.mjs");
    expect(fileURLToPath(new URL("../../sidekicks/", location))).toBe("/Users/x/Library/Application Support/midas/sidekicks/");
  });
});
