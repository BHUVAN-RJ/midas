// Founder, 2026-11-08: "add hindi 'Kuch Bhi' sound effect". An eighth starter, "Kuch Bhi"
// (key `kuch`), after Happy Happy Happy (docs/PRODUCT.md, Sounds section; docs/briefs/
// soundboard-sidekick.md, "As built"). A phone that already copied in the first seven copies in only
// the starters after them, Kuch Bhi first. Written so a later starter does not break it.
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

const FIRST_SEVEN = ["fahh", "bruh", "boom", "khatam", "gay", "maro", "cat"];

describe("Sounds: the eighth starter, Kuch Bhi (founder, 2026-11-08)", () => {
  it("the page carries kuch right after the first seven, with its name, tags, clip and GIF", () => {
    const starters = pageStarters();
    const keys = keysOf(starters);
    expect(keys.slice(0, 8)).toEqual([...FIRST_SEVEN, "kuch"]);
    const kuch = starters[7];
    expect(kuch.name).toBe("Kuch Bhi");
    expect(kuch.tags).toEqual(["kuch", "bhi", "arnab", "whatever"]);
    const audioBytes = Buffer.from(kuch.audioBase64, "base64");
    const imageBytes = Buffer.from(kuch.imageBase64, "base64");
    expect(audioBytes.subarray(0, 3).toString("latin1")).toBe("ID3");
    expect(imageBytes.subarray(0, 6).toString("latin1")).toBe("GIF89a");
    // a real clip and a real GIF, not an empty stand-in
    expect(audioBytes.length).toBeGreaterThan(10000);
    expect(imageBytes.length).toBeGreaterThan(10000);
  });

  it("search finds it by kuch, bhi or arnab", () => {
    const kuch = pageStarters()[7];
    const record = Logic.starterSoundRecord(kuch, "file:kuchaudio001", "file:kuchgif0001", 8, "2026-11-08T09:00:00.000Z");
    for (const query of ["kuch", "BHI", "arnab", "kuch bhi"]) {
      expect(Logic.matchesQuery(record, query)).toBe(true);
    }
    expect(Logic.matchesQuery(record, "happy")).toBe(false);
  });

  it("a phone that already copied in the first seven copies in Kuch Bhi next and none of the seven", () => {
    const allKeys = keysOf(pageStarters());
    const waiting = Logic.unseededStarters(pageStarters(), settingsSeeded(FIRST_SEVEN));
    expect(keysOf(waiting)).toEqual(allKeys.slice(7));
    expect(Logic.starterSoundKey(waiting[0])).toBe("sound:kuch");
  });
});
