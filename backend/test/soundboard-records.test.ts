// The Sounds Sidekick's record types (docs/briefs/soundboard-sidekick.md, section 2): sound:<id>
// (soundboard.sound) and settings:self (soundboard.settings) in manifest.json, checked the way
// the shell's write gate checks every set (shell/sdk/record-schema.js). The records the page's
// own code builds must pass; records the page never writes must not.
import { readFileSync } from "node:fs";
import vm from "node:vm";
import { describe, expect, it } from "vitest";
import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import MidasShellTypes from "../../shell/sdk/shell-types.js";
import { typesBlockProblems, validateManifest } from "../scripts/bundle-tools.mjs";

const folder = new URL("../../sidekicks/soundboard/", import.meta.url);
const html = readFileSync(new URL("index.html", folder), "utf8");
const manifest = JSON.parse(readFileSync(new URL("manifest.json", folder), "utf8"));

function soundsLogicSource(pageHtml: string) {
  const start = pageHtml.indexOf("var SoundsLogic = (function createSoundsLogic() {");
  const end = pageHtml.indexOf("\n})();\n", start) + "\n})();\n".length;
  return pageHtml.slice(start, end);
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const Logic: any = vm.runInNewContext(soundsLogicSource(html) + "\n;SoundsLogic;", {});
const NOW = "2026-11-07T20:00:00.000Z";

type Value = Record<string, unknown>;

// null when the record fits its type, else the reason the shell would refuse it
function typeProblem(key: string, value: Value): string | null {
  const stamped = MidasRecordSchema.stampType(manifest.types, key, JSON.parse(JSON.stringify(value)));
  return MidasRecordSchema.checkRecord(manifest.types, key, stamped);
}

describe("soundboard: manifest", () => {
  it("is Sounds on Lemon with a speaker, and its types are in its own namespace", () => {
    expect(validateManifest(manifest, "soundboard")).toEqual([]);
    expect(manifest.name).toBe("Sounds");
    expect(manifest.icon.background).toBe("#FFE600");
    expect(typesBlockProblems(manifest.types, "soundboard")).toEqual([]);
    expect(manifest.types["sound:"].$type).toBe("soundboard.sound");
    expect(manifest.types["settings:"].$type).toBe("soundboard.settings");
  });
});

describe("soundboard: the records the page writes fit their types", () => {
  it("a sound added on the page, with and without a GIF and tags", () => {
    const full = Logic.soundRecord({ name: "Fahh", tags: ["fah", "fail"], audio: "file:abcdef0123456789", image: "file:0123456789abcdef", order: 1 }, null, NOW);
    expect(typeProblem("sound:mw75cz3b5n0wx7", full)).toBeNull();
    const bare = Logic.soundRecord({ name: "Bruh", tags: [], audio: "file:abcdef0123456789", image: null, order: 2 }, null, NOW);
    expect(typeProblem("sound:mw75cz3b5n0wx8", bare)).toBeNull();
  });

  it("a starter sound", () => {
    const starter = { key: "khatam", name: "Khatam Tata Bye Bye", tags: ["rahul", "khatam", "tata", "bye"], audioBase64: "AA" };
    const value = Logic.starterSoundRecord(starter, "file:abcdef0123456789", "file:0123456789abcdef", 4, NOW);
    expect(typeProblem(Logic.starterSoundKey(starter), value)).toBeNull();
  });

  it("the settings: seeded starters and overlap", () => {
    const value = Logic.settingsRecord({ seeded: ["fahh", "bruh", "boom", "khatam"], overlap: false }, null, NOW);
    expect(typeProblem("settings:self", value)).toBeNull();
  });

  it("the widget, as the shell's own widget type", () => {
    for (const widget of Logic.widgetRecords()) {
      for (const choice of [widget.value, widget.fallback, widget.plain]) {
        const stamped = MidasRecordSchema.stampType(MidasShellTypes, widget.key, JSON.parse(JSON.stringify(choice)));
        expect(MidasRecordSchema.checkRecord(MidasShellTypes, widget.key, stamped)).toBeNull();
      }
    }
  });
});

describe("soundboard: records the page never writes are refused", () => {
  it("a sound without a clip, with an empty name, or with a clip that is not a file", () => {
    expect(typeProblem("sound:x", { name: "No clip" })).not.toBeNull();
    expect(typeProblem("sound:x", { name: "", audio: "file:abcdefgh" })).not.toBeNull();
    expect(typeProblem("sound:x", { name: "Data", audio: "data:audio/mpeg;base64,AAAA" })).not.toBeNull();
    expect(typeProblem("sound:x", { name: "Link", audio: "https://example.com/a.mp3" })).not.toBeNull();
  });

  it("tags that are not a list of short words, a name over 60, seeded that is not a list", () => {
    expect(typeProblem("sound:x", { name: "T", audio: "file:abcdefgh", tags: "boom" })).not.toBeNull();
    expect(typeProblem("sound:x", { name: "T", audio: "file:abcdefgh", tags: ["z".repeat(31)] })).not.toBeNull();
    expect(typeProblem("sound:x", { name: "n".repeat(61), audio: "file:abcdefgh" })).not.toBeNull();
    expect(typeProblem("settings:self", { seeded: "fahh" })).not.toBeNull();
    expect(typeProblem("settings:self", { overlap: "yes" })).not.toBeNull();
  });
});
