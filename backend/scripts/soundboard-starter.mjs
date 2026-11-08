// The Sounds Sidekick's starter sounds (docs/briefs/soundboard-sidekick.md, section 2): the clips
// and GIFs in sidekicks/soundboard/starter/, listed in starters.json, go into the page as one
// data block at the end of <body>. The phone serves only index.html from a bundle, so the page
// carries the starters itself and copies each into the store on first open.
//
// The block is a <template>, not a <script type="application/json">: the deploy gate refuses any
// script tag with attributes (bundle-tools.mjs, "script tag with attributes"), and a template's
// text never runs, so the CSP script hashes are unaffected. One starter per line.
//
// Usage, from backend/:
//   node scripts/soundboard-starter.mjs           rewrites the block in sidekicks/soundboard/index.html
//   node scripts/soundboard-starter.mjs --check   exits 1 when the block is not what the files give
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { findForbiddenPrimitives } from "./bundle-tools.mjs";

export const BLOCK_OPEN = '<template id="starter-sounds">';
export const BLOCK_CLOSE = "</template>";

const SCRIPT_FOLDER = fileURLToPath(new URL(".", import.meta.url));
export const SOUNDBOARD_FOLDER = join(SCRIPT_FOLDER, "..", "..", "sidekicks", "soundboard");
export const STARTER_FOLDER = join(SOUNDBOARD_FOLDER, "starter");
export const PAGE_PATH = join(SOUNDBOARD_FOLDER, "index.html");

const CONTENT_TYPES = {
  mp3: "audio/mpeg",
  m4a: "audio/mp4",
  wav: "audio/wav",
  gif: "image/gif",
  png: "image/png",
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  webp: "image/webp",
};

export function contentTypeOf(fileName) {
  const dot = fileName.lastIndexOf(".");
  const extension = fileName.slice(dot + 1).toLowerCase();
  const contentType = CONTENT_TYPES[extension];
  if (contentType === undefined) {
    throw new Error(`no content type for ${fileName}`);
  }
  return contentType;
}

// The starters as the page reads them: { key, name, tags, audioType, audioBase64, imageType,
// imageBase64 }. readBytes(fileName) gives a file's bytes (a parameter so tests can stand in).
export function starterEntries(starterList, readBytes) {
  const entries = [];
  for (const starter of starterList) {
    const audioBytes = readBytes(starter.audio);
    const entry = {
      key: starter.key,
      name: starter.name,
      tags: starter.tags,
      audioType: contentTypeOf(starter.audio),
      audioBase64: Buffer.from(audioBytes).toString("base64"),
    };
    if (starter.image) {
      const imageBytes = readBytes(starter.image);
      entry.imageType = contentTypeOf(starter.image);
      entry.imageBase64 = Buffer.from(imageBytes).toString("base64");
    }
    entries.push(entry);
  }
  return entries;
}

// The whole block, open and close tags included: a JSON array, one starter per line
export function starterBlock(entries) {
  const lines = [];
  for (const entry of entries) {
    lines.push(JSON.stringify(entry));
  }
  const arrayText = "[\n" + lines.join(",\n") + "\n]";
  return BLOCK_OPEN + "\n" + arrayText + "\n" + BLOCK_CLOSE;
}

// Where the block sits in the page: { start, end } of the whole block, or null
export function findStarterBlock(html) {
  const start = html.indexOf(BLOCK_OPEN);
  if (start === -1) {
    return null;
  }
  const closeAt = html.indexOf(BLOCK_CLOSE, start);
  if (closeAt === -1) {
    return null;
  }
  return { start, end: closeAt + BLOCK_CLOSE.length };
}

// The page with only its block replaced; throws when the page has no block
export function replaceStarterBlock(html, block) {
  const found = findStarterBlock(html);
  if (found === null) {
    throw new Error(`index.html has no ${BLOCK_OPEN} … ${BLOCK_CLOSE} block`);
  }
  const before = html.slice(0, found.start);
  const after = html.slice(found.end);
  return before + block + after;
}

function readStarterFile(fileName) {
  return readFileSync(join(STARTER_FOLDER, fileName));
}

export function readStarterList() {
  const listText = readFileSync(join(STARTER_FOLDER, "starters.json"), "utf8");
  return JSON.parse(listText);
}

// The block the starter files give now
export function currentStarterBlock() {
  const entries = starterEntries(readStarterList(), readStarterFile);
  return starterBlock(entries);
}

function main() {
  const checkOnly = process.argv.includes("--check");
  const html = readFileSync(PAGE_PATH, "utf8");
  const block = currentStarterBlock();
  const updated = replaceStarterBlock(html, block);
  // Base64 could in theory spell a word the deploy gate refuses; never write a page it would reject
  const violations = findForbiddenPrimitives(updated);
  if (violations.length > 0) {
    console.error(`the page would fail the deploy gate: ${violations.join(", ")}`);
    process.exit(1);
  }
  if (checkOnly) {
    if (updated !== html) {
      console.error("the starter block in index.html is out of date; run node scripts/soundboard-starter.mjs");
      process.exit(1);
    }
    console.log("starter block up to date");
    return;
  }
  writeFileSync(PAGE_PATH, updated);
  console.log(`wrote ${readStarterList().length} starters (${block.length} characters) into index.html`);
}

const isMain = process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1];
if (isMain) {
  main();
}
