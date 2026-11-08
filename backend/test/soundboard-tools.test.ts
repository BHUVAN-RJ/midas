// The Sounds Sidekick's tools (jess router, founder 2026-10-21: every action a person can take in
// the page is a tool; docs/briefs/soundboard-sidekick.md, section 2). sidekicks/soundboard/tools.js
// is loaded the way the deploy gate and the phone load it; every tool is called on real-shaped
// records and every record it would write is checked against manifest.json, as the shell's write
// gate checks it. Also the bundle as a whole: the deploy gate, the store helper pasted unchanged,
// one inline script, no purple.
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import { checkBundleFiles } from "../scripts/bundle-tools.mjs";
import { copiedBlocks, loadToolsScript, sidekickToolsProblems } from "../scripts/sidekick-tools.mjs";

const folder = new URL("../../sidekicks/soundboard/", import.meta.url);
const toolsText = readFileSync(new URL("tools.js", folder), "utf8");
const html = readFileSync(new URL("index.html", folder), "utf8");
const manifestText = readFileSync(new URL("manifest.json", folder), "utf8");
const manifest = JSON.parse(manifestText);

const loaded = loadToolsScript(toolsText);
if (!("tools" in loaded)) {
  throw new Error(loaded.problem);
}
const tools = loaded.tools;

const NOW = "2026-11-07T20:00:00.000Z";

type Value = Record<string, unknown>;
type Records = Array<{ key: string; value: Value }>;
type Op = { op: string; key: string; value?: Value };
type Outcome = { ops?: Op[]; refused?: string; result: { text: string; [field: string]: unknown } };

function baseRecords(settingsFields: Value = {}): Records {
  return [
    { key: "settings:self", value: { $type: "soundboard.settings", seeded: ["fahh", "bruh", "boom", "khatam"], overlap: true, createdAt: "2026-11-07T18:00:00.000Z", ...settingsFields } },
    { key: "sound:boom", value: { $type: "soundboard.sound", name: "Vine Boom", tags: ["boom", "rock"], audio: "file:boomaudio001", image: "file:boomimage001", order: 3, starter: "boom", createdAt: "2026-11-07T18:00:02.000Z" } },
    { key: "sound:bruh", value: { $type: "soundboard.sound", name: "Bruh", tags: ["bruh"], audio: "file:bruhaudio001", image: "file:bruhimage001", order: 2, starter: "bruh", createdAt: "2026-11-07T18:00:01.000Z" } },
    { key: "sound:fahh", value: { $type: "soundboard.sound", name: "Fahh", tags: ["fah", "fail"], audio: "file:fahhaudio001", image: "file:fahhimage001", order: 1, starter: "fahh", createdAt: "2026-11-07T18:00:00.000Z" } },
    { key: "sound:khatam", value: { $type: "soundboard.sound", name: "Khatam Tata Bye Bye", tags: ["rahul", "khatam", "tata", "bye"], audio: "file:khatamaudio01", image: "file:khatamimage01", order: 4, starter: "khatam", createdAt: "2026-11-07T18:00:03.000Z" } },
    { key: "sound:mw75cz3b", value: { $type: "soundboard.sound", name: "Boom Boom", audio: "file:mineaudio0001", order: 5, createdAt: "2026-11-07T19:00:00.000Z", plays: 3 } },
    { key: "widget:sounds", value: { $type: "midas.widget", name: "Sounds" } },
  ];
}

function deepFreeze<T>(value: T): T {
  if (value && typeof value === "object") {
    for (const field of Object.keys(value as object)) {
      deepFreeze((value as Record<string, unknown>)[field]);
    }
    Object.freeze(value);
  }
  return value;
}

function call(verb: string, input: Value, records: Records = baseRecords()): Outcome {
  const outcome = tools.handlers[verb](input, deepFreeze(records), NOW);
  return JSON.parse(JSON.stringify(outcome));
}

function opFor(outcome: Outcome, key: string): Op | undefined {
  for (const op of outcome.ops || []) {
    if (op.key === key) {
      return op;
    }
  }
  return undefined;
}

// Every set must pass the shell's write gate
function expectOpsFitTheirTypes(outcome: Outcome) {
  for (const op of outcome.ops || []) {
    if (op.op !== "set") {
      continue;
    }
    const stamped = MidasRecordSchema.stampType(manifest.types, op.key, JSON.parse(JSON.stringify(op.value)));
    expect(MidasRecordSchema.checkRecord(manifest.types, op.key, stamped), op.key).toBeNull();
  }
}

function pageSoundsLogic() {
  const start = html.indexOf("var SoundsLogic = (function createSoundsLogic() {");
  const end = html.indexOf("\n})();\n", start) + "\n})();\n".length;
  return html.slice(start, end);
}

describe("soundboard: the bundle and its tools", () => {
  it("passes the deploy gate: page, manifest and tools.js together", () => {
    expect(checkBundleFiles(html, manifestText, "soundboard", toolsText).problems).toEqual([]);
  });

  it("has the six tools the page's actions give, one handler each, and no play or add tool", () => {
    const verbs: string[] = [];
    for (const tool of manifest.agent.tools) {
      verbs.push(tool.name.slice("soundboard.".length));
    }
    verbs.sort();
    expect(verbs).toEqual(["delete", "list", "rename", "search", "set_overlap", "tag"]);
    const handlerNames = Object.keys(tools.handlers);
    handlerNames.sort();
    expect(handlerNames).toEqual(verbs);
  });

  it("carries the page's SoundsLogic character for character", () => {
    const blocks = copiedBlocks(toolsText);
    expect(blocks.length).toBe(1);
    expect(blocks[0].text).toBe(pageSoundsLogic());
  });

  it("would be refused if the page's logic changed without tools.js", () => {
    const changedPage = html.replace("const NAME_MAX = 60;", "const NAME_MAX = 40;");
    expect(changedPage).not.toBe(html);
    const problems = sidekickToolsProblems(manifest, toolsText, changedPage, "soundboard");
    expect(problems.length).toBe(1);
    expect(problems[0]).toContain("no longer matches index.html");
  });

  it("pastes shell/sdk/midas-store.js unchanged, in one inline script, with nothing loaded from outside", () => {
    const storeHelper = readFileSync(new URL("../../shell/sdk/midas-store.js", import.meta.url), "utf8");
    expect(html.includes(storeHelper)).toBe(true);
    expect(html.split("<script>").length - 1).toBe(1);
    expect(html).not.toMatch(/<script\s|<link\s|<audio|new Audio\(|https?:\/\/(?!www\.w3\.org\/2000\/svg)/);
    expect(html).not.toMatch(/localStorage|sessionStorage|indexedDB/);
  });

  it("plays through Web Audio from the page's own files endpoint (the CSP has no media-src)", () => {
    expect(html).toContain("decodeAudioData");
    expect(html).toContain("createBufferSource");
    expect(html).toContain("window.location.origin + '/_midas/files/'");
  });

  it("has no purple in its colours, light or night", () => {
    const codeEnd = html.indexOf('<template id="starter-sounds">');
    const code = html.slice(0, codeEnd);
    const hexColours = code.match(/#[0-9A-Fa-f]{6}\b/g) || [];
    expect(hexColours.length).toBeGreaterThan(10);
    for (const hex of hexColours) {
      const red = parseInt(hex.slice(1, 3), 16);
      const green = parseInt(hex.slice(3, 5), 16);
      const blue = parseInt(hex.slice(5, 7), 16);
      // Purple: red and blue both well above green
      expect(red > green + 24 && blue > green + 24, hex).toBe(false);
    }
  });
});

describe("soundboard tools: reading", () => {
  it("lists the board in its order", () => {
    const outcome = call("list", {});
    expect(outcome.ops).toEqual([]);
    expect(outcome.result.names).toEqual(["Fahh", "Bruh", "Vine Boom", "Khatam Tata Bye Bye", "Boom Boom"]);
    expect(outcome.result.text).toBe("5 sounds: Fahh, Bruh, Vine Boom, Khatam Tata Bye Bye, Boom Boom");
  });

  it("lists nothing on an empty board", () => {
    const outcome = call("list", {}, [baseRecords()[0]]);
    expect(outcome.result.text).toBe("No Sounds");
    expect(outcome.result.names).toEqual([]);
  });

  it("searches name and tags like the page's field", () => {
    expect(call("search", { query: "RAHUL" }).result.names).toEqual(["Khatam Tata Bye Bye"]);
    expect(call("search", { query: "boom" }).result.names).toEqual(["Vine Boom", "Boom Boom"]);
    expect(call("search", { query: "boom" }).result.text).toBe("Found 2: Vine Boom, Boom Boom");
    expect(call("search", { query: "airhorn" }).result.text).toBe("No Sounds");
    expect(call("search", { query: "  " }).refused).toBe("empty-query");
  });

  it("tells jess the names and how sounds play, nothing else", () => {
    const context = JSON.parse(JSON.stringify(tools.context(deepFreeze(baseRecords({ overlap: false })), NOW)));
    expect(context).toEqual({ count: 5, sounds: ["Fahh", "Bruh", "Vine Boom", "Khatam Tata Bye Bye", "Boom Boom"], playing: "one at a time" });
  });
});

describe("soundboard tools: changing", () => {
  it("renames a sound and keeps everything else on its record", () => {
    const outcome = call("rename", { name: "fahh", newName: "  Faaah " });
    expect(outcome.result.text).toBe("Renamed to Faaah");
    const op = opFor(outcome, "sound:fahh");
    expect(op?.op).toBe("set");
    expect(op?.value).toEqual({ name: "Faaah", tags: ["fah", "fail"], audio: "file:fahhaudio001", image: "file:fahhimage001", order: 1, starter: "fahh", createdAt: "2026-11-07T18:00:00.000Z" });
    expectOpsFitTheirTypes(outcome);
  });

  it("keeps fields the page does not know when it renames", () => {
    const outcome = call("rename", { name: "Boom Boom", newName: "Double Boom" });
    expect(opFor(outcome, "sound:mw75cz3b")?.value?.plays).toBe(3);
  });

  it("refuses a rename that names no sound, several sounds, an empty name or the same name", () => {
    expect(call("rename", { name: "airhorn", newName: "X" }).refused).toBe("no-such-sound");
    const several = call("rename", { name: "boom", newName: "X" });
    expect(several.refused).toBe("which-sound");
    expect(several.result.text).toBe("Which one: Vine Boom, Boom Boom?");
    expect(call("rename", { name: "Bruh", newName: "   " }).refused).toBe("name-not-offered");
    expect(call("rename", { name: "Bruh", newName: "Bruh" }).refused).toBe("nothing-to-change");
  });

  it("adds and takes off tags, in lower case", () => {
    const outcome = call("tag", { name: "Vine Boom", add: ["Bass", "boom"], remove: ["rock"] });
    expect(outcome.result.text).toBe("Vine Boom: boom, bass");
    expect(opFor(outcome, "sound:boom")?.value?.tags).toEqual(["boom", "bass"]);
    expectOpsFitTheirTypes(outcome);
  });

  it("leaves the tags field out when the last tag comes off, and refuses a change to nothing", () => {
    const outcome = call("tag", { name: "Bruh", add: [], remove: ["BRUH"] });
    expect(outcome.result.text).toBe("Bruh: no tags");
    expect(opFor(outcome, "sound:bruh")?.value).not.toHaveProperty("tags");
    expectOpsFitTheirTypes(outcome);
    expect(call("tag", { name: "Bruh", add: ["bruh"], remove: [] }).refused).toBe("nothing-to-change");
  });

  it("deletes a sound by name", () => {
    const outcome = call("delete", { name: "khatam" });
    expect(outcome.result.text).toBe("Deleted Khatam Tata Bye Bye");
    expect(outcome.ops).toEqual([{ op: "delete", key: "sound:khatam" }]);
  });

  it("deleting a starter that is not in seeded yet adds it, so the page does not copy it in again", () => {
    const outcome = call("delete", { name: "Fahh" }, baseRecords({ seeded: ["bruh"] }));
    expect(opFor(outcome, "sound:fahh")?.op).toBe("delete");
    expect(opFor(outcome, "settings:self")?.value?.seeded).toEqual(["bruh", "fahh"]);
    expectOpsFitTheirTypes(outcome);
  });

  it("refuses to delete a sound it cannot single out", () => {
    expect(call("delete", { name: "boom" }).refused).toBe("which-sound");
    expect(call("delete", { name: "airhorn" }).refused).toBe("no-such-sound");
  });

  it("switches between playing over each other and one at a time", () => {
    const outcome = call("set_overlap", { overlap: false });
    expect(outcome.result.text).toBe("One sound at a time");
    expect(opFor(outcome, "settings:self")?.value).toEqual({ seeded: ["fahh", "bruh", "boom", "khatam"], overlap: false, createdAt: "2026-11-07T18:00:00.000Z" });
    expectOpsFitTheirTypes(outcome);
    expect(call("set_overlap", { overlap: true }).refused).toBe("nothing-to-change");
  });

  it("changes nothing on a refusal", () => {
    for (const outcome of [call("rename", { name: "nope", newName: "X" }), call("delete", { name: "nope" }), call("set_overlap", { overlap: true })]) {
      expect(outcome.ops).toBeUndefined();
      expect(typeof outcome.result.text).toBe("string");
    }
  });
});
