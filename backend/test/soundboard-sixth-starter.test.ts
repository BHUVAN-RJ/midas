// Founder, 2026-11-08: "just add the fkn sounds - hindhi one 'oh bhai maro mujhe maro'". A sixth
// starter, "Bhai Maro Mujhe Maro" (key `maro`), after Why Are You Gay (docs/PRODUCT.md, Sounds
// section; docs/briefs/soundboard-sidekick.md, "As built"). A phone that already copied in the
// first five must copy in only the new one on its next open; a deleted starter stays deleted.
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

function findStarter(key: string): Starter {
  const starters = pageStarters();
  const index = keysOf(starters).indexOf(key);
  expect(index).toBeGreaterThanOrEqual(0);
  return starters[index];
}

function settingsSeeded(seeded: string[]) {
  return Logic.settingsFrom({ $type: "soundboard.settings", seeded, overlap: true });
}

const FIRST_FIVE = ["fahh", "bruh", "boom", "khatam", "gay"];

describe("Sounds: the sixth starter, Bhai Maro Mujhe Maro (founder, 2026-11-08)", () => {
  it("the page carries maro right after gay, with its name, tags, clip and GIF", () => {
    const keys = keysOf(pageStarters());
    const gayIndex = keys.indexOf("gay");
    expect(gayIndex).toBeGreaterThanOrEqual(0);
    expect(keys[gayIndex + 1]).toBe("maro");
    const maro = findStarter("maro");
    expect(maro.name).toBe("Bhai Maro Mujhe Maro");
    expect(maro.tags).toEqual(["bhai", "maro", "mujhe", "pakistan", "cricket"]);
    const audioBytes = Buffer.from(maro.audioBase64, "base64");
    const imageBytes = Buffer.from(maro.imageBase64, "base64");
    expect(audioBytes.subarray(0, 3).toString("latin1")).toBe("ID3");
    expect(imageBytes.subarray(0, 6).toString("latin1")).toBe("GIF89a");
    // a real clip and a real GIF, not an empty stand-in
    expect(audioBytes.length).toBeGreaterThan(10000);
    expect(imageBytes.length).toBeGreaterThan(10000);
  });

  it("search finds it by maro, bhai or mujhe", () => {
    const maro = findStarter("maro");
    const record = Logic.starterSoundRecord(maro, "file:maroaudio001", "file:marogif0001", 6, "2026-11-08T09:00:00.000Z");
    for (const query of ["maro", "BHAI", "mujhe", "bhai maro"]) {
      expect(Logic.matchesQuery(record, query)).toBe(true);
    }
    expect(Logic.matchesQuery(record, "fahh")).toBe(false);
  });

  it("a phone that already copied in the first five copies in only sound:maro", () => {
    const waiting = Logic.unseededStarters(pageStarters(), settingsSeeded(FIRST_FIVE));
    expect(keysOf(waiting)).toEqual(["maro"]);
    expect(Logic.starterSoundKey(waiting[0])).toBe("sound:maro");
  });

  it("the new starter's record is a valid sound with its starter key", () => {
    const maro = findStarter("maro");
    const value = Logic.starterSoundRecord(maro, "file:maroaudio001", "file:marogif0001", 6, "2026-11-08T09:00:00.000Z");
    expect(value.name).toBe("Bhai Maro Mujhe Maro");
    expect(value.starter).toBe("maro");
    expect(value.audio).toBe("file:maroaudio001");
    expect(value.image).toBe("file:marogif0001");
  });
});
