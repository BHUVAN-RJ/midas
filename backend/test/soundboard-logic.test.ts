// The Sounds Sidekick's page logic (docs/briefs/soundboard-sidekick.md, section 2, founder
// 2026-11-07): names and tags, the board's order, search (name and tags as you type, any case),
// the record a save writes, and which starters are copied in on open (a deleted starter stays
// deleted). SoundsLogic is run straight from sidekicks/soundboard/index.html.
import { readFileSync } from "node:fs";
import vm from "node:vm";
import { describe, expect, it } from "vitest";

const html = readFileSync(new URL("../../sidekicks/soundboard/index.html", import.meta.url), "utf8");

function soundsLogicSource(pageHtml: string) {
  const start = pageHtml.indexOf("var SoundsLogic = (function createSoundsLogic() {");
  const end = pageHtml.indexOf("\n})();\n", start) + "\n})();\n".length;
  return pageHtml.slice(start, end);
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const Logic: any = vm.runInNewContext(soundsLogicSource(html) + "\n;SoundsLogic;", {});

type Value = Record<string, unknown>;

function plain<T>(value: T): T {
  return JSON.parse(JSON.stringify(value));
}

function sound(key: string, fields: Value) {
  return { key, value: { $type: "soundboard.sound", audio: "file:aaaaaaaa", ...fields } };
}

const NOW = "2026-11-07T20:00:00.000Z";

function starterKeys(starters: Value[]): string[] {
  const keys: string[] = [];
  for (const starter of starters) {
    keys.push(starter.key as string);
  }
  return keys;
}

describe("soundboard logic: names and tags", () => {
  it("guesses a name from a picked file name", () => {
    expect(Logic.nameFromFileName("vine_boom-2.mp3")).toBe("Vine boom 2");
    expect(Logic.nameFromFileName("fahh.mp3")).toBe("Fahh");
    expect(Logic.nameFromFileName("  bruh  sound .m4a")).toBe("Bruh sound");
    expect(Logic.nameFromFileName(".mp3")).toBe(".mp3");
    expect(Logic.nameFromFileName("")).toBe("");
  });

  it("keeps names to one line of at most 60 characters", () => {
    expect(Logic.cleanName("  Khatam   Tata\nBye Bye ")).toBe("Khatam Tata Bye Bye");
    expect(Logic.cleanName("x".repeat(80)).length).toBe(60);
    expect(Logic.cleanName("   ")).toBe("");
  });

  it("reads the Tags field: commas between tags, lower case, no repeats, no empties", () => {
    expect(plain(Logic.parseTags("Again, BRUH ,again,, sad   trombone"))).toEqual(["again", "bruh", "sad trombone"]);
    expect(plain(Logic.parseTags(""))).toEqual([]);
    expect(Logic.tagsText(["boom", "rock"])).toBe("boom, rock");
  });

  it("keeps at most 20 tags of at most 30 characters", () => {
    const many: string[] = [];
    for (let index = 0; index < 30; index += 1) {
      many.push("tag" + index);
    }
    expect(Logic.cleanTags(many).length).toBe(20);
    expect(Logic.cleanTags(["y".repeat(50)])[0].length).toBe(30);
  });

  it("adds and takes off tags", () => {
    expect(plain(Logic.retagged(["boom", "rock"], ["Bass"], ["rock"]))).toEqual(["boom", "bass"]);
    expect(plain(Logic.retagged(["boom"], ["boom"], []))).toEqual(["boom"]);
  });
});

describe("soundboard logic: the board", () => {
  const records = [
    sound("sound:zz", { name: "Late", order: 3, createdAt: "2026-11-07T10:00:00.000Z" }),
    sound("sound:aa", { name: "First", order: 1, createdAt: "2026-11-07T12:00:00.000Z" }),
    sound("sound:mm", { name: "No order", createdAt: "2026-11-07T09:00:00.000Z" }),
    sound("sound:bb", { name: "Second", order: 2, tags: ["Rock", "boom"], createdAt: "2026-11-07T11:00:00.000Z" }),
    { key: "settings:self", value: { seeded: [] } },
    { key: "widget:sounds", value: { name: "Sounds" } },
  ];

  it("orders sounds by order, a sound without one last, and ignores other records", () => {
    const entries = Logic.soundsInOrder(records);
    expect(plain(Logic.namesOf(entries))).toEqual(["First", "Second", "Late", "No order"]);
  });

  it("puts a new sound after the last", () => {
    expect(Logic.nextOrder(Logic.soundsInOrder(records))).toBe(4);
    expect(Logic.nextOrder([])).toBe(1);
  });

  it("searches name and tags, any case, every word somewhere", () => {
    const entries = Logic.soundsInOrder(records);
    expect(plain(Logic.namesOf(Logic.filterEntries(entries, "sec")))).toEqual(["Second"]);
    expect(plain(Logic.namesOf(Logic.filterEntries(entries, "ROCK")))).toEqual(["Second"]);
    expect(plain(Logic.namesOf(Logic.filterEntries(entries, "boom second")))).toEqual(["Second"]);
    expect(plain(Logic.namesOf(Logic.filterEntries(entries, "boom first")))).toEqual([]);
    expect(Logic.filterEntries(entries, "   ").length).toBe(4);
  });

  it("finds a sound by what was said: the exact name first, else the one name holding the words", () => {
    const entries = Logic.soundsInOrder([
      sound("sound:fahh", { name: "Fahh", order: 1 }),
      sound("sound:boom", { name: "Vine Boom", order: 2 }),
      sound("sound:boom2", { name: "Boom Boom", order: 3 }),
    ]);
    expect(Logic.findByName(entries, "fahh").entry.key).toBe("sound:fahh");
    expect(Logic.findByName(entries, "vine").entry.key).toBe("sound:boom");
    expect(Logic.findByName(entries, "boom").matches.length).toBe(2);
    expect(Logic.findByName(entries, "airhorn").matches.length).toBe(0);
    expect(Logic.findByName(entries, "").matches.length).toBe(0);
  });

  it("makes keys that differ for two sounds added in the same millisecond", () => {
    const first = Logic.newSoundKey(1762545600000, 0.1);
    const second = Logic.newSoundKey(1762545600000, 0.7);
    expect(first.startsWith("sound:")).toBe(true);
    expect(first).not.toBe(second);
  });
});

describe("soundboard logic: the record a save writes", () => {
  it("writes a new sound with its fields, and leaves out empty tags and a missing GIF", () => {
    const value = plain(Logic.soundRecord({ name: " Fahh ", tags: [], audio: "file:abcdefgh", image: null, order: 5 }, null, NOW));
    expect(value).toEqual({ name: "Fahh", audio: "file:abcdefgh", order: 5, createdAt: NOW });
  });

  it("keeps fields it does not know and the time it was added, drops $type", () => {
    const existing = { $type: "soundboard.sound", name: "Old", audio: "file:abcdefgh", image: "file:gifgifgif", order: 2, createdAt: "2026-11-01T00:00:00.000Z", plays: 7 };
    const value = plain(Logic.soundRecord({ name: "New" }, existing, NOW));
    expect(value).toEqual({ name: "New", audio: "file:abcdefgh", image: "file:gifgifgif", order: 2, createdAt: "2026-11-01T00:00:00.000Z", plays: 7 });
  });

  it("will not save a sheet without a name or a sound", () => {
    expect(plain(Logic.sheetProblems("", null))).toEqual(["name", "audio"]);
    expect(plain(Logic.sheetProblems("Fahh", "picked"))).toEqual([]);
    expect(plain(Logic.sheetProblems("Fahh", "file:abcdefgh"))).toEqual([]);
    expect(plain(Logic.sheetProblems("  ", "file:abcdefgh"))).toEqual(["name"]);
  });
});

describe("soundboard logic: starters and settings", () => {
  const starters = [
    { key: "fahh", name: "Fahh", tags: ["fah"], audioBase64: "AAAA", audioType: "audio/mpeg" },
    { key: "bruh", name: "Bruh", tags: [], audioBase64: "AAAA", audioType: "audio/mpeg" },
    { key: "", name: "Broken", audioBase64: "AAAA" },
    { key: "nosound", name: "No sound" },
  ];

  it("copies in only starters not yet seeded, so a deleted starter stays deleted", () => {
    const fresh = Logic.settingsFrom(null);
    expect(starterKeys(Logic.unseededStarters(starters, fresh))).toEqual(["fahh", "bruh"]);
    const afterFahh = Logic.settingsFrom({ seeded: ["fahh"] });
    expect(starterKeys(Logic.unseededStarters(starters, afterFahh))).toEqual(["bruh"]);
  });

  it("names a starter's record after its key and marks where it came from", () => {
    expect(Logic.starterSoundKey(starters[0])).toBe("sound:fahh");
    const value = plain(Logic.starterSoundRecord(starters[0], "file:audioaudio", "file:gifgifgif", 1, NOW));
    expect(value).toEqual({ name: "Fahh", tags: ["fah"], audio: "file:audioaudio", image: "file:gifgifgif", order: 1, starter: "fahh", createdAt: NOW });
  });

  it("plays sounds over each other unless overlap is false", () => {
    expect(Logic.settingsFrom(null).overlap).toBe(true);
    expect(Logic.settingsFrom({ overlap: false }).overlap).toBe(false);
    expect(plain(Logic.settingsFrom({ seeded: ["a", "a", 3, "b"] }).seeded)).toEqual(["a", "b"]);
  });

  it("keeps the settings record's other fields when it writes seeded and overlap", () => {
    const existing = { $type: "soundboard.settings", seeded: ["fahh"], overlap: true, createdAt: "2026-11-01T00:00:00.000Z", extra: 1 };
    const value = plain(Logic.settingsRecord({ seeded: ["fahh", "bruh"], overlap: false }, existing, NOW));
    expect(value).toEqual({ seeded: ["fahh", "bruh"], overlap: false, createdAt: "2026-11-01T00:00:00.000Z", extra: 1 });
  });
});
