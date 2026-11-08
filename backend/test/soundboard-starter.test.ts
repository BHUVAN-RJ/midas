// The Sounds Sidekick's starter sounds (docs/briefs/soundboard-sidekick.md, section 2, founder
// 2026-11-07: "add fahh, bruh, and boom and also ... rahul gandhi 'khatam, good bye tata' ... add
// the gif frames as the main icon"). The phone serves only index.html from a bundle, so the clips
// and GIFs ride in the page as one data block at the end of <body>, written by
// backend/scripts/soundboard-starter.mjs. The block is a <template>, not a script: the deploy gate
// refuses any script tag with attributes, and a template never runs, so the CSP's script hashes
// cover only the page's one inline script.
import { existsSync, readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { findForbiddenPrimitives, inlineScriptHashes } from "../scripts/bundle-tools.mjs";

const folder = new URL("../../sidekicks/soundboard/", import.meta.url);
const html = readFileSync(new URL("index.html", folder), "utf8");
// Present in the repo; a repair job's sandbox has only the page, manifest and tools
const starterFolderUrl = new URL("starter/", folder);
const hasStarterFiles = existsSync(starterFolderUrl);

const BLOCK_OPEN = '<template id="starter-sounds">';
const BLOCK_CLOSE = "</template>";

type Starter = { key: string; name: string; tags: string[]; audioType: string; audioBase64: string; imageType?: string; imageBase64?: string };

function blockText(pageHtml: string) {
  const start = pageHtml.indexOf(BLOCK_OPEN);
  const end = pageHtml.indexOf(BLOCK_CLOSE, start);
  return pageHtml.slice(start + BLOCK_OPEN.length, end);
}

function starters(): Starter[] {
  return JSON.parse(blockText(html));
}

function bytesOf(base64: string) {
  return Buffer.from(base64, "base64");
}

// An MP3 starts with an ID3 tag or an MPEG frame sync (11 bits set)
function looksLikeMp3(bytes: Buffer) {
  const hasId3 = bytes.subarray(0, 3).toString("latin1") === "ID3";
  const hasFrameSync = bytes[0] === 0xff && (bytes[1] & 0xe0) === 0xe0;
  return hasId3 || hasFrameSync;
}

describe("soundboard starters: the block in the page", () => {
  it("is one template at the very end of <body>, after the page's only script", () => {
    const blockStart = html.indexOf(BLOCK_OPEN);
    expect(blockStart).toBeGreaterThan(html.lastIndexOf("</script>"));
    expect(html.indexOf(BLOCK_OPEN, blockStart + 1)).toBe(-1);
    const afterBlock = html.slice(html.indexOf(BLOCK_CLOSE, blockStart) + BLOCK_CLOSE.length);
    expect(afterBlock.trim()).toBe("</body>\n</html>");
  });

  it("leaves the deploy gate and the CSP hashes alone: no script tag with attributes, one hash", () => {
    expect(findForbiddenPrimitives(html)).toEqual([]);
    expect(inlineScriptHashes(html).length).toBe(1);
    expect(blockText(html)).not.toContain("<");
  });

  it("holds Fahh, Bruh, Vine Boom, Khatam Tata Bye Bye and Why Are You Gay, in that order, with their tags", () => {
    const summary: Array<[string, string, string[]]> = [];
    for (const starter of starters()) {
      summary.push([starter.key, starter.name, starter.tags]);
    }
    expect(summary).toEqual([
      ["fahh", "Fahh", ["fah", "fail"]],
      ["bruh", "Bruh", ["bruh"]],
      ["boom", "Vine Boom", ["boom", "rock"]],
      ["khatam", "Khatam Tata Bye Bye", ["rahul", "khatam", "tata", "bye"]],
      ["gay", "Why Are You Gay", ["why", "gay", "interview", "uganda"]],
    ]);
  });

  it("gives every starter a real MP3 clip and a GIF", () => {
    for (const starter of starters()) {
      expect(starter.audioType, starter.key).toBe("audio/mpeg");
      const audio = bytesOf(starter.audioBase64);
      expect(audio.length, starter.key).toBeGreaterThan(2000);
      expect(looksLikeMp3(audio), starter.key).toBe(true);
      expect(starter.imageType, starter.key).toBe("image/gif");
      const image = bytesOf(starter.imageBase64 || "");
      expect(image.subarray(0, 6).toString("latin1"), starter.key).toMatch(/^GIF8[79]a$/);
    }
  });

  it("puts one starter on each line", () => {
    const lines = blockText(html).trim().split("\n");
    expect(lines[0]).toBe("[");
    expect(lines[lines.length - 1]).toBe("]");
    expect(lines.length).toBe(starters().length + 2);
  });
});

describe("soundboard starters: the generator", () => {
  it.skipIf(!hasStarterFiles)("the block is exactly what the files in sidekicks/soundboard/starter give", async () => {
    const generator = await import("../scripts/soundboard-starter.mjs");
    expect(generator.replaceStarterBlock(html, generator.currentStarterBlock())).toBe(html);
  });

  it("rewrites only the block, and refuses a page without one", async () => {
    const generator = await import("../scripts/soundboard-starter.mjs");
    const page = "<body>\n<script>code()</script>\n" + BLOCK_OPEN + "\n[]\n" + BLOCK_CLOSE + "\n</body>";
    const entries = generator.starterEntries([{ key: "k", name: "K", tags: ["t"], audio: "k.mp3", image: "k.gif" }], function readStandIn(fileName: string) {
      return Buffer.from(fileName);
    });
    const block = generator.starterBlock(entries);
    const rewritten = generator.replaceStarterBlock(page, block);
    expect(rewritten.startsWith("<body>\n<script>code()</script>\n")).toBe(true);
    expect(rewritten.endsWith("\n</body>")).toBe(true);
    expect(JSON.parse(blockText(rewritten))).toEqual([
      { key: "k", name: "K", tags: ["t"], audioType: "audio/mpeg", audioBase64: Buffer.from("k.mp3").toString("base64"), imageType: "image/gif", imageBase64: Buffer.from("k.gif").toString("base64") },
    ]);
    expect(function replaceWithoutBlock() {
      generator.replaceStarterBlock("<body></body>", block);
    }).toThrow();
  });
});
