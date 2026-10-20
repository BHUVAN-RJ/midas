import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import { describe, expect, it } from "vitest";

// Old record formats are quarantined (founder, 2026-10-20): only the upgrade-on-read converter
// and the migration script may still name the old shapes; every description of them lives in
// docs/legacy/LEGACY-RECORD-FORMATS.DO-NOT-READ.md. This scans the backend, runner and scripts
// code (not tests, not prompts) for the old-shape markers.

const REPO_ROOT = new URL("../../", import.meta.url).pathname;
const SCANNED_PATHS = ["backend/src", "backend/scripts", "backend/migrations", "runner/lib", "runner/bin", "runner/tools", "runner/install.sh", "scripts"];
const CODE_EXTENSIONS = [".ts", ".mjs", ".js", ".sql", ".sh", ".json"];
const ALLOWED_FILES = ["backend/scripts/record-upgrades.mjs", "backend/scripts/migrate-records.mjs"];
const QUARANTINE_FILE = "docs/legacy/LEGACY-RECORD-FORMATS.DO-NOT-READ.md";
const ALLOWED_HEADER = "OLD RECORD SHAPES ARE ALLOWED HERE ONLY";

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

function markerHits(filePath: string) {
  const text = readFileSync(join(REPO_ROOT, filePath), "utf8");
  const hits: string[] = [];
  for (const marker of OLD_SHAPE_MARKERS) {
    if (marker.pattern.test(text)) {
      hits.push(`${filePath}: ${marker.what}`);
    }
  }
  return hits;
}

describe("old record shapes are quarantined (founder, 2026-10-20)", () => {
  it("scans the files it means to (the converter and runner code are found)", () => {
    const files = scannedFiles();
    expect(files).toContain("backend/scripts/record-upgrades.mjs");
    expect(files).toContain("runner/lib/user-records.mjs");
    expect(files).toContain("backend/src/sync.ts");
  });

  it("no backend, runner or scripts code outside the converter and the migration names an old shape", () => {
    const hits: string[] = [];
    for (const filePath of scannedFiles()) {
      if (ALLOWED_FILES.includes(filePath)) {
        continue;
      }
      hits.push(...markerHits(filePath));
    }
    expect(hits).toEqual([]);
  });

  it("the converter and the migration say they are the only place old shapes are allowed, and point to the quarantine file", () => {
    for (const filePath of ALLOWED_FILES) {
      const header = readFileSync(join(REPO_ROOT, filePath), "utf8").slice(0, 600);
      expect(header, filePath).toContain(ALLOWED_HEADER);
      expect(header, filePath).toContain(QUARANTINE_FILE);
    }
  });

  it("the markers still match the old shapes the converter handles (the scan can fail)", () => {
    const converterHits = markerHits("backend/scripts/record-upgrades.mjs");
    expect(converterHits).toContain("backend/scripts/record-upgrades.mjs: task: key");
    expect(converterHits).toContain("backend/scripts/record-upgrades.mjs: settings:sidebar key");
    expect(converterHits).toContain("backend/scripts/record-upgrades.mjs: care ~rule record");
  });
});
