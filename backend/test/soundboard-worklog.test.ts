// jess work log links (founder, 2026-10-31; shell/sdk/midas-store.js header): a work log card
// opens the Sidekick at the record jess changed, and the store helper finds, centres and marks
// the element whose `data-key` is that record's key. On Sounds every tile must carry its record's
// full key (`sound:<key>`), or a link from "Renamed Fahh" opens the board with nothing marked.
// These run the page's own tileHtml and starter key code from sidekicks/soundboard/index.html.
import { readFileSync } from "node:fs";
import vm from "node:vm";
import { describe, expect, it } from "vitest";

const html = readFileSync(new URL("../../sidekicks/soundboard/index.html", import.meta.url), "utf8");

// The source of one `function <name>(` in the page, up to the closing brace at two-space indent
function pageFunction(name: string): string {
  const start = html.indexOf("  function " + name + "(");
  expect(start, name).toBeGreaterThan(-1);
  const end = html.indexOf("\n  }\n", start) + "\n  }\n".length;
  return html.slice(start, end);
}

function soundsLogicSource(): string {
  const start = html.indexOf("var SoundsLogic = (function createSoundsLogic() {");
  const end = html.indexOf("\n})();\n", start) + "\n})();\n".length;
  return html.slice(start, end);
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const Logic: any = vm.runInNewContext(soundsLogicSource() + "\n;SoundsLogic;", {});

// tileHtml run in a sandbox with the page's escapeHtml and a stand-in speaker icon
function tileFor(record: { key: string; value: Record<string, unknown> }): string {
  const entries = Logic.soundsInOrder([record]);
  expect(entries.length).toBe(1);
  const sandboxSource = pageFunction("escapeHtml") + pageFunction("tileHtml") + "\n;tileHtml;";
  const sandbox = { state: { playingCounts: {} }, Logic, speakerIcon: speakerIconStandIn };
  const tileHtml = vm.runInNewContext(sandboxSource, sandbox);
  return tileHtml(entries[0]);
}

function speakerIconStandIn(): string {
  return "<svg></svg>";
}

function dataKeysIn(tileMarkup: string): string[] {
  const keys: string[] = [];
  const pattern = /data-key="([^"]*)"/g;
  let found = pattern.exec(tileMarkup);
  while (found !== null) {
    keys.push(found[1]);
    found = pattern.exec(tileMarkup);
  }
  return keys;
}

describe("Sounds and jess work log links", () => {
  it("pastes the store helper that marks a record's element by data-key", () => {
    const helper = readFileSync(new URL("../../shell/sdk/midas-store.js", import.meta.url), "utf8");
    expect(helper).toContain("getAttribute('data-key')");
    expect(html.includes(helper)).toBe(true);
  });

  it("each tile carries its record's full key once, so the helper finds it", () => {
    const record = { key: "sound:m1abc-xyz", value: { $type: "soundboard.sound", name: "Airhorn", audio: "file:abcdefgh" } };
    const tile = tileFor(record);
    expect(dataKeysIn(tile)).toEqual(["sound:m1abc-xyz"]);
  });

  it("a starter's tile carries the key the starter record is written under", () => {
    const starterKey = Logic.starterSoundKey({ key: "fahh" });
    expect(starterKey).toBe("sound:fahh");
    const record = { key: starterKey, value: { $type: "soundboard.sound", name: "Fahh", audio: "file:abcdefgh", starter: "fahh" } };
    expect(dataKeysIn(tileFor(record))).toEqual(["sound:fahh"]);
  });
});
