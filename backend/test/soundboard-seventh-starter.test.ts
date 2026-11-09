// Founder, 2026-11-08: "add the happy happy happy cat thing". A seventh starter, "Happy Happy Happy"
// (key `cat`), after Bhai Maro Mujhe Maro (docs/PRODUCT.md, Sounds section; docs/briefs/
// soundboard-sidekick.md, "As built"). A phone that already copied in the first six copies in only
// the starters after them, the cat first. Written so a later starter does not break it.
// Runs the page's own SoundsLogic and reads the page's own starter block.
import { readFileSync } from "node:fs";
import vm from "node:vm";
import { describe, expect, it } from "vitest";
import { BLOCK_OPEN, BLOCK_CLOSE, findStarterBlock } from "../scripts/soundboard-starter.mjs";

const html = readFileSync(new URL("../../sidekicks/soundboard/index.html", import.meta.url), "utf8");

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

const FIRST_SIX = ["fahh", "bruh", "boom", "khatam", "gay", "maro"];

describe("Sounds: the seventh starter, Happy Happy Happy (founder, 2026-11-08)", () => {
  it("the page carries cat right after the first six, with its name, tags, clip and GIF", () => {
    const starters = pageStarters();
    const keys = keysOf(starters);
    expect(keys.slice(0, 7)).toEqual([...FIRST_SIX, "cat"]);
    const cat = starters[6];
    expect(cat.name).toBe("Happy Happy Happy");
    expect(cat.tags).toEqual(["happy", "cat", "dance"]);
    const audioBytes = Buffer.from(cat.audioBase64, "base64");
    const imageBytes = Buffer.from(cat.imageBase64, "base64");
    expect(audioBytes.subarray(0, 3).toString("latin1")).toBe("ID3");
    expect(imageBytes.subarray(0, 6).toString("latin1")).toBe("GIF89a");
    // a real clip and a real GIF, not an empty stand-in
    expect(audioBytes.length).toBeGreaterThan(10000);
    expect(imageBytes.length).toBeGreaterThan(10000);
  });

  it("search finds it by happy, cat or dance", () => {
    const cat = pageStarters()[6];
    const record = Logic.starterSoundRecord(cat, "file:cataudio0001", "file:catgif00001", 7, "2026-11-08T09:00:00.000Z");
    for (const query of ["happy", "CAT", "dance", "happy cat"]) {
      expect(Logic.matchesQuery(record, query)).toBe(true);
    }
    expect(Logic.matchesQuery(record, "maro")).toBe(false);
  });

  it("a phone that already copied in the first six copies in the cat next and none of the six", () => {
    const allKeys = keysOf(pageStarters());
    const waiting = Logic.unseededStarters(pageStarters(), settingsSeeded(FIRST_SIX));
    expect(keysOf(waiting)).toEqual(allKeys.slice(6));
    expect(Logic.starterSoundKey(waiting[0])).toBe("sound:cat");
  });
});
