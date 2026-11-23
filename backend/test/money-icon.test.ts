// Money's icon (founder, 2026-11-09: "lets go with C and update the icon everywhere"): the shell
// draws the Wallet (shell/Shared/SidekickIcon.swift, MoneyWalletArtwork). The manifest's tile colours
// are the fallback on builds without that artwork and the colour the Add to Home Screen sheet uses,
// so they are the wallet's bill green, by day and at night (docs/ICONS.md).
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

const REPO_ROOT = join(__dirname, "..", "..");

function swiftConstant(source: string, name: string): string | undefined {
  const pattern = new RegExp(`static let ${name} = "(#[0-9A-Fa-f]{6})"`);
  const match = source.match(pattern);
  return match ? match[1] : undefined;
}

describe("Money icon", () => {
  const manifestPath = join(REPO_ROOT, "sidekicks", "money", "manifest.json");
  const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
  const iconSource = readFileSync(join(REPO_ROOT, "shell", "Shared", "SidekickIcon.swift"), "utf8");

  it("the shell draws the Wallet for money", () => {
    expect(iconSource).toContain('case "money":\n            return .moneyWallet');
  });

  it("the manifest's tile is the wallet's bill green: Money's Groceries green, deeper at night", () => {
    const billHex = swiftConstant(iconSource, "billHex");
    expect(billHex).toBe("#2E9E5B");
    expect(manifest.icon.background).toBe(billHex);
    expect(manifest.icon.backgroundDark).toBe("#1F7A45");
  });

  it("keeps a catalog symbol as the last fallback", () => {
    expect(manifest.icon.symbol).toBe("dollarsign.circle.fill");
  });
});
