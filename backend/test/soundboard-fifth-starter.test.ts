// Founder, 2026-11-07, after Sounds went live: a fifth starter, "Why Are You Gay" (key `gay`),
// and "remove that completely" about the "+" Add Sound flow (docs/briefs/soundboard-sidekick.md,
// "As built"). A phone that already copied in the first four (`settings:self.seeded` = fahh,
// bruh, boom, khatam) must copy in only the new one on its next open; a deleted starter stays
// deleted; and the page has no way left to add a sound. Runs the page's own SoundsLogic and reads
// the page's own starter block.
import { readFileSync } from "node:fs";
import vm from "node:vm";
import { describe, expect, it } from "vitest";
import { BLOCK_OPEN, BLOCK_CLOSE, findStarterBlock } from "../scripts/soundboard-starter.mjs";

const html = readFileSync(new URL("../../sidekicks/soundboard/index.html", import.meta.url), "utf8");
const toolsText = readFileSync(new URL("../../sidekicks/soundboard/tools.js", import.meta.url), "utf8");
const manifestText = readFileSync(new URL("../../sidekicks/soundboard/manifest.json", import.meta.url), "utf8");

function soundsLogicSource(): string {
  const start = html.indexOf("var SoundsLogic = (function createSoundsLogic() {");
  const end = html.indexOf("\n})();\n", start) + "\n})();\n".length;
  return html.slice(start, end);
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const Logic: any = vm.runInNewContext(soundsLogicSource() + "\n;SoundsLogic;", {});

type Starter = { key: string; name: string; tags: string[]; audioBase64: string; imageBase64: string };

// The starters as the page reads them: the JSON inside <template id="starter-sounds">
function pageStarters(): Starter[] {
  const found = findStarterBlock(html);
  expect(found).not.toBeNull();
  const blockText = html.slice(found!.start + BLOCK_OPEN.length, found!.end - BLOCK_CLOSE.length);
  return JSON.parse(blockText);
}

function keysOf(starters: Starter[]): string[] {
  const keys: string[] = [];
  for (const starter of starters) {
    keys.push(starter.key);
  }
  return keys;
}

function settingsSeeded(seeded: string[]) {
  return Logic.settingsFrom({ $type: "soundboard.settings", seeded, overlap: true });
}

describe("Sounds: the fifth starter", () => {
  it("the page carries Why Are You Gay after Khatam, with its tags, clip and GIF", () => {
    const starters = pageStarters();
    expect(keysOf(starters)).toEqual(["fahh", "bruh", "boom", "khatam", "gay"]);
    const gay = starters[4];
    expect(gay.name).toBe("Why Are You Gay");
    expect(gay.tags).toEqual(["why", "gay", "interview", "uganda"]);
    const audioBytes = Buffer.from(gay.audioBase64, "base64");
    const imageBytes = Buffer.from(gay.imageBase64, "base64");
    expect(audioBytes.subarray(0, 3).toString("latin1")).toBe("ID3");
    expect(imageBytes.subarray(0, 6).toString("latin1")).toBe("GIF89a");
  });

  it("a phone that already copied in the first four copies in only sound:gay", () => {
    const waiting = Logic.unseededStarters(pageStarters(), settingsSeeded(["fahh", "bruh", "boom", "khatam"]));
    expect(keysOf(waiting)).toEqual(["gay"]);
    expect(Logic.starterSoundKey(waiting[0])).toBe("sound:gay");
  });

  it("a starter the person deleted stays deleted when the new one arrives", () => {
    // Bruh was deleted earlier: its key is still in seeded, so only gay is copied in
    const waiting = Logic.unseededStarters(pageStarters(), settingsSeeded(["fahh", "bruh", "boom", "khatam"]));
    expect(keysOf(waiting)).not.toContain("bruh");
    const freshPhone = Logic.unseededStarters(pageStarters(), settingsSeeded([]));
    expect(keysOf(freshPhone)).toEqual(["fahh", "bruh", "boom", "khatam", "gay"]);
  });

  it("the new starter's record is a valid sound with its starter key and the next order", () => {
    const gay = pageStarters()[4];
    const value = Logic.starterSoundRecord(gay, "file:gayaudio0001", "file:gaygif00001", 5, "2026-11-08T09:00:00.000Z");
    expect(value.name).toBe("Why Are You Gay");
    expect(value.starter).toBe("gay");
    expect(value.order).toBe(5);
    expect(value.audio).toBe("file:gayaudio0001");
    expect(value.image).toBe("file:gaygif00001");
  });
});

describe("Sounds: no adding from the phone (founder, 2026-11-07)", () => {
  it("the page has no + button, no Add Sound, no file pickers and no Added toast", () => {
    expect(html).not.toContain('data-action="open-add"');
    expect(html).not.toContain("Add Sound");
    expect(html).not.toMatch(/type="file"|pick-audio|pick-image|Choose Sound|Choose GIF/);
    expect(html).not.toContain("'Added '");
    expect(Logic.nameFromFileName).toBeUndefined();
  });

  it("the Edit sheet needs only a name", () => {
    expect(Logic.sheetProblems("")).toEqual(["name"]);
    expect(Logic.sheetProblems("Fahh")).toEqual([]);
  });

  it("jess has no add tool and is told sounds are not added from the phone", () => {
    const manifest = JSON.parse(manifestText);
    const toolNames: string[] = [];
    for (const tool of manifest.agent.tools) {
      toolNames.push(tool.name);
    }
    for (const name of toolNames) {
      expect(name).not.toMatch(/add|upload|create/);
    }
    expect(manifest.agent.notFor.join(" ")).toContain("no way to add one from the phone");
    expect(toolsText).not.toContain("picked on the page");
  });
});
