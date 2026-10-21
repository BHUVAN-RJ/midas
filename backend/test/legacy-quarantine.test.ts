import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import { describe, expect, it } from "vitest";

// Old record formats are quarantined (founder, 2026-10-20) and retired from all code (founder,
// 2026-10-20, docs/PRODUCT.md "Old formats retired"): no code may name the old shapes; every
// description of them lives in docs/legacy/LEGACY-RECORD-FORMATS.DO-NOT-READ.md. This scans the
// backend, runner and scripts code (not tests, not prompts) for the old-shape markers.

const REPO_ROOT = new URL("../../", import.meta.url).pathname;
const SCANNED_PATHS = ["backend/src", "backend/scripts", "backend/migrations", "runner/lib", "runner/bin", "runner/tools", "runner/install.sh", "scripts"];
const CODE_EXTENSIONS = [".ts", ".mjs", ".js", ".sql", ".sh", ".json"];

const OLD_SHAPE_MARKERS = [
  { pattern: /\btask:/, what: "task: key" },
  { pattern: /settings:sidebar/, what: "settings:sidebar key" },
  { pattern: /~rule/, what: "care ~rule record" },
  { pattern: /@HHMM/, what: "care @HHMM record" },
  { pattern: /epoch m(s|illiseconds)/i, what: "epoch-ms dates" },
];

function hasCodeExtension(filePath: string) {
  return CODE_EXTENSIONS.some(function endsWithExtension(extension) {
    return filePath.endsWith(extension);
  });
}

// Every code file under a scanned path, as repo-relative paths; node_modules left out.
function collectFiles(absolutePath: string, found: string[]) {
  const stats = statSync(absolutePath, { throwIfNoEntry: false });
  if (stats === undefined) {
    return;
  }
  if (stats.isFile()) {
    if (hasCodeExtension(absolutePath)) {
      found.push(relative(REPO_ROOT, absolutePath));
    }
    return;
  }
  for (const entryName of readdirSync(absolutePath)) {
    if (entryName === "node_modules") {
      continue;
    }
    collectFiles(join(absolutePath, entryName), found);
  }
}

function scannedFiles() {
  const found: string[] = [];
  for (const scannedPath of SCANNED_PATHS) {
    collectFiles(join(REPO_ROOT, scannedPath), found);
  }
  return found;
}

// The old-shape markers a text contains, by name.
function textMarkerHits(text: string) {
  const hits: string[] = [];
  for (const marker of OLD_SHAPE_MARKERS) {
    if (marker.pattern.test(text)) {
      hits.push(marker.what);
    }
  }
  return hits;
}

function markerHits(filePath: string) {
  const text = readFileSync(join(REPO_ROOT, filePath), "utf8");
  return textMarkerHits(text).map(function withFilePath(what) {
    return `${filePath}: ${what}`;
  });
}

describe("old record shapes are quarantined (founder, 2026-10-20)", () => {
  it("scans the files it means to (the planner and runner code are found)", () => {
    const files = scannedFiles();
    expect(files).toContain("backend/scripts/user-copy-plan.mjs");
    expect(files).toContain("runner/lib/user-records.mjs");
    expect(files).toContain("backend/src/sync.ts");
  });

  it("no backend, runner or scripts code names an old shape", () => {
    const hits: string[] = [];
    for (const filePath of scannedFiles()) {
      hits.push(...markerHits(filePath));
    }
    expect(hits).toEqual([]);
  });

  it("every marker matches its old shape (the scan can fail)", () => {
    expect(textMarkerHits("store.set('task:' + id, v)")).toEqual(["task: key"]);
    expect(textMarkerHits("store.get('settings:sidebar')")).toEqual(["settings:sidebar key"]);
    expect(textMarkerHits("reminder:pills~rule1")).toEqual(["care ~rule record"]);
    expect(textMarkerHits("reminder:pills@HHMM")).toEqual(["care @HHMM record"]);
    expect(textMarkerHits("at is epoch ms")).toEqual(["epoch-ms dates"]);
  });
});
