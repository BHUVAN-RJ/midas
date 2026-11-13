// This person's notes (founder, 2026-11-13, D5; docs/briefs/repair-lanes.md W4): a short dated
// log kept with the person's copy in tests/PERSON_NOTES.md. Each fixed repair adds one line from
// outcome.json "note"; the agent cannot edit the log itself; the log travels with the published
// copy like the copy's tests.
import { existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import {
  NOTE_MAX_CHARACTERS,
  NOTES_MAX_LINES,
  PERSON_NOTES_FILE,
  PERSON_NOTES_HEADING,
  appendNoteLine,
  appendPersonNoteFromOutcome,
  cleanNote,
  firstSentence,
  formatNoteLine,
  noteDate,
  noteForOutcome,
  noteLines,
  readPersonNotes,
} from "../../runner/lib/person-notes.mjs";
import { compareTests, readFetchedTests } from "../../runner/lib/copy-tests.mjs";
import { stageDeployFolder } from "../../runner/lib/deploy.mjs";

// A local-time instant, so the date in the line is the runner's own day.
const NOV_13_LATE = new Date(2026, 10, 13, 23, 30, 0);

function makeJobFolder(outcome: Record<string, unknown> | null, notesText: string | null = null): string {
  const jobFolder = mkdtempSync(join(tmpdir(), "w4-notes-"));
  mkdirSync(join(jobFolder, "tests"), { recursive: true });
  mkdirSync(join(jobFolder, "sidekick"), { recursive: true });
  if (outcome !== null) {
    writeFileSync(join(jobFolder, "outcome.json"), JSON.stringify(outcome));
  }
  if (notesText !== null) {
    writeFileSync(join(jobFolder, "tests", PERSON_NOTES_FILE), notesText);
  }
  return jobFolder;
}

describe("a note line", () => {
  it("is one line, without its own list marker, at most the limit", () => {
    expect(cleanNote("  Search tab hidden.\n Search stays\tin the top bar. ")).toBe("Search tab hidden. Search stays in the top bar.");
    expect(cleanNote("- Streak hidden.")).toBe("Streak hidden.");
    const longNote = "word ".repeat(100);
    const cleaned = cleanNote(longNote);
    expect(cleaned?.length).toBe(NOTE_MAX_CHARACTERS);
    expect(cleaned?.endsWith("…")).toBe(true);
    expect(cleanNote("   ")).toBeNull();
    expect(cleanNote(" - ")).toBeNull();
    expect(cleanNote(42)).toBeNull();
  });

  it("is dated with the runner's local day and names the repair", () => {
    expect(noteDate(NOV_13_LATE)).toBe("2026-11-13");
    expect(formatNoteLine({ note: "Streak hidden.", now: NOV_13_LATE, reportId: "r-9" })).toBe("- 2026-11-13: Streak hidden. (repair r-9)");
    expect(formatNoteLine({ note: "Streak hidden.", now: NOV_13_LATE, reportId: null })).toBe("- 2026-11-13: Streak hidden.");
  });
});

describe("which outcome adds a line", () => {
  it("a fixed repair adds its note, or the summary's first sentence when it wrote none", () => {
    expect(noteForOutcome({ result: "fixed", summary: "Hid the streak. Kept the code.", note: "Streak hidden." })).toBe("Streak hidden.");
    expect(noteForOutcome({ result: "fixed", summary: "Hid the streak. Kept the code." })).toBe("Hid the streak.");
    expect(noteForOutcome({ result: "fixed", summary: "Hid the streak", note: "  " })).toBe("Hid the streak");
    expect(firstSentence("One. Two.")).toBe("One.");
  });

  it("unsupported and no_change publish nothing, so they add nothing", () => {
    expect(noteForOutcome({ result: "unsupported", summary: "No.", unsupportedAction: "x", note: "Should not land." })).toBeNull();
    expect(noteForOutcome({ result: "no_change", summary: "Already there.", note: "Should not land." })).toBeNull();
    expect(noteForOutcome(null)).toBeNull();
  });
});

describe("appending to the log in the job folder", () => {
  it("starts the log on the first fixed repair", () => {
    const jobFolder = makeJobFolder({ result: "fixed", summary: "s", note: "Search tab hidden. Search stays in the top bar." });
    const result = appendPersonNoteFromOutcome({ jobFolder, now: NOV_13_LATE, reportId: "r-1" });
    expect(result).toEqual({ appended: true, line: "- 2026-11-13: Search tab hidden. Search stays in the top bar. (repair r-1)" });
    const stored = readPersonNotes(jobFolder);
    expect(stored).toBe(`${PERSON_NOTES_HEADING}\n\n- 2026-11-13: Search tab hidden. Search stays in the top bar. (repair r-1)\n`);
  });

  it("keeps every earlier line and adds the new one last", () => {
    const earlier = `${PERSON_NOTES_HEADING}\n\n- 2026-11-07: Search tab hidden. (repair r-1)\n`;
    const jobFolder = makeJobFolder({ result: "fixed", summary: "s", note: "Search back in the tab bar." }, earlier);
    appendPersonNoteFromOutcome({ jobFolder, now: NOV_13_LATE, reportId: "r-2" });
    expect(noteLines(readPersonNotes(jobFolder))).toEqual([
      "- 2026-11-07: Search tab hidden. (repair r-1)",
      "- 2026-11-13: Search back in the tab bar. (repair r-2)",
    ]);
  });

  it("stays short: past the limit the oldest lines go", () => {
    const manyLines: string[] = [];
    for (let index = 0; index < NOTES_MAX_LINES; index += 1) {
      manyLines.push(`- 2026-01-01: change ${index}.`);
    }
    const updated = appendNoteLine(`${PERSON_NOTES_HEADING}\n\n${manyLines.join("\n")}\n`, "- 2026-11-13: newest.");
    const lines = noteLines(updated);
    expect(lines.length).toBe(NOTES_MAX_LINES);
    expect(lines[0]).toBe("- 2026-01-01: change 1.");
    expect(lines[lines.length - 1]).toBe("- 2026-11-13: newest.");
  });

  it("writes nothing for an unsupported repair or a missing outcome", () => {
    const unsupportedFolder = makeJobFolder({ result: "unsupported", summary: "s", unsupportedAction: "a", note: "x" });
    expect(appendPersonNoteFromOutcome({ jobFolder: unsupportedFolder, now: NOV_13_LATE })).toEqual({ appended: false });
    expect(existsSync(join(unsupportedFolder, "tests", PERSON_NOTES_FILE))).toBe(false);
    const noOutcomeFolder = makeJobFolder(null);
    expect(appendPersonNoteFromOutcome({ jobFolder: noOutcomeFolder, now: NOV_13_LATE })).toEqual({ appended: false });
  });
});

describe("where the log lives: the copy's tests/ folder", () => {
  it("goes out with the published copy", () => {
    const jobFolder = makeJobFolder({ result: "fixed", summary: "s", note: "Streak hidden." });
    writeFileSync(join(jobFolder, "sidekick", "index.html"), "<p>page</p>");
    writeFileSync(join(jobFolder, "sidekick", "manifest.json"), "{}");
    appendPersonNoteFromOutcome({ jobFolder, now: NOV_13_LATE, reportId: "r-3" });
    const deployFolder = `${jobFolder}.deploy`;
    stageDeployFolder({ jobFolder, deployFolder });
    const deployed = readFileSync(join(deployFolder, "tests", PERSON_NOTES_FILE), "utf8");
    expect(deployed).toContain("- 2026-11-13: Streak hidden. (repair r-3)");
  });

  it("comes back with the next job's fetch", () => {
    const fetchFolder = mkdtempSync(join(tmpdir(), "w4-fetch-"));
    mkdirSync(join(fetchFolder, "tests"), { recursive: true });
    writeFileSync(join(fetchFolder, "tests", PERSON_NOTES_FILE), `${PERSON_NOTES_HEADING}\n\n- 2026-11-13: Streak hidden.\n`);
    const fetched = readFetchedTests(fetchFolder);
    expect(fetched[PERSON_NOTES_FILE]).toContain("Streak hidden.");
  });

  it("an agent that edits the log fails the job, as for any file that was in tests/", () => {
    const before = { [PERSON_NOTES_FILE]: Buffer.from("- 2026-11-07: Search tab hidden.\n"), "TEST_CHANGES.md": Buffer.from("") };
    const after = { [PERSON_NOTES_FILE]: Buffer.from("- 2026-11-07: Search tab shown.\n"), "TEST_CHANGES.md": Buffer.from("") };
    const report = compareTests({ before, after });
    expect(report.problems).toContain(`test changed without a test-guardian entry in TEST_CHANGES.md: ${PERSON_NOTES_FILE}`);
  });
});
