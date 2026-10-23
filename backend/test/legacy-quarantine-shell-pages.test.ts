import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import { describe, expect, it } from "vitest";

// Old record formats are gone from the shell and the Sidekick pages (founder, 2026-10-20: live
// and staging are converted, so nothing reads or writes the old shapes any more). This scans the
// shell's code and the Sidekick pages and manifests (not the shell's tests) for the old-shape
// markers and for any upgrade-on-read code left behind.

const REPO_ROOT = new URL("../../", import.meta.url).pathname;
const SCANNED_PATHS = ["shell/Midas", "shell/MidasWidgets", "shell/Shared", "shell/sdk", "sidekicks"];
const CODE_EXTENSIONS = [".swift", ".js", ".html", ".json"];

const OLD_SHAPE_MARKERS = [
  { pattern: /['"`]task:/, what: "task: key" },
  { pattern: /settings:sidebar/, what: "settings:sidebar key" },
  { pattern: /[Uu]pgrade on read|not yet converted/, what: "upgrade-on-read code" },
  { pattern: /LEGACY-RECORD-FORMATS/, what: "pointer to the quarantine file" },
  { pattern: /epoch/i, what: "epoch-ms dates" },
  { pattern: /care-(item|alert|slot)/, what: "old care kind" },
  { pattern: /\bseriesId\b|\balertRules\b/, what: "retired care item field" },
  { pattern: /\b(record|value|existing)\.body\b|\[["']body["']\]/, what: "body read from a record" },
  { pattern: /legacy/i, what: "legacy reader" },
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

function markersIn(text: string) {
  const found: string[] = [];
  for (const marker of OLD_SHAPE_MARKERS) {
    if (marker.pattern.test(text)) {
      found.push(marker.what);
    }
  }
  return found;
}

function markerHits(filePath: string) {
  const text = readFileSync(join(REPO_ROOT, filePath), "utf8");
  const hits: string[] = [];
  for (const what of markersIn(text)) {
    hits.push(`${filePath}: ${what}`);
  }
  return hits;
}

describe("old record shapes are gone from the shell and the Sidekick pages (founder, 2026-10-20)", () => {
  it("scans the files it means to (the record parser, both pages and their manifests are found)", () => {
    const files = scannedFiles();
    expect(files).toContain("shell/Midas/ReminderRecord.swift");
    expect(files).toContain("shell/sdk/record-schema.js");
    expect(files).toContain("sidekicks/reminders/index.html");
    expect(files).toContain("sidekicks/care-reminders/index.html");
    expect(files).toContain("sidekicks/care-reminders/manifest.json");
  });

  it("no shell code, Sidekick page or manifest names an old shape or reads one", () => {
    const hits: string[] = [];
    for (const filePath of scannedFiles()) {
      hits.push(...markerHits(filePath));
    }
    expect(hits).toEqual([]);
  });

  // Lines the upgrade-on-read code had before 2026-10-20; each must still be caught.
  it("the markers catch the upgrade-on-read code that was removed (the scan can fail)", () => {
    const removedLines = [
      { line: "const taskRecords = await store.query('task:');", what: "task: key" },
      { line: "const OLD_SETTINGS_KEY = 'settings:sidebar';", what: "settings:sidebar key" },
      { line: "// Upgrade on read: a record not yet converted", what: "upgrade-on-read code" },
      { line: "if let epochMilliseconds = value.numberValue {", what: "epoch-ms dates" },
      { line: "} else if (typeof record.body === 'string') {", what: "body read from a record" },
      { line: "if let legacyText = value[\"body\"]?.stringValue {", what: "body read from a record" },
      { line: "delete value.seriesId;", what: "retired care item field" },
      { line: "where: { kind: 'care-item' }", what: "old care kind" },
      { line: "async function foldLegacyRecords(item, legacyAlerts, legacySlots) {", what: "legacy reader" },
    ];
    for (const removed of removedLines) {
      expect(markersIn(removed.line), removed.line).toContain(removed.what);
    }
    expect(markersIn("const reminderRecords = await store.query('reminder:');")).toEqual([]);
    expect(markersIn("answerStoreRequest(sidekickId: sidekickId, url: requestURL, task: urlSchemeTask)")).toEqual([]);
  });
});
