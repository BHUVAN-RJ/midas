// This person's notes (founder, 2026-11-13, D5): a short dated log kept with each person's copy of
// a Sidekick, one line per published repair: what the copy changed and why ("Search tab hidden.
// Search stays in the top bar."). The one repair agent reads it before every repair, so a later
// repair keeps what an earlier one did unless the person reverses it.
//
// Where it lives: tests/PERSON_NOTES.md in the copy. The copy's tests/ folder already travels with
// every published version (deploy.mjs stages it, deploy-sidekick.mjs stores it under
// <version>/tests/ in R2, fetch-sidekick-copy.mjs brings it back for the next job), and nothing
// under tests/ is ever served to the phone. Inside a job the agent may read it but never change it:
// the job's guard hook blocks writes under tests/, and compareTests fails the job when a file that
// was in tests/ changed. The agent hands its line over in outcome.json ("note"); the runner adds
// the date and appends it after compareTests and before the publish.
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { OUTCOME_FILE } from "./job-folder.mjs";

export const PERSON_NOTES_FILE = "PERSON_NOTES.md";
export const PERSON_NOTES_HEADING = "# This person's notes";
// One line is a sentence or two, not a summary of the diff.
export const NOTE_MAX_CHARACTERS = 200;
// "A short log": the newest lines are kept when it grows past this. 100 lines is about two years
// of a repair a week on one copy.
export const NOTES_MAX_LINES = 100;
// What the prompt shows when it carries no notes: either the copy has none yet, or the runner built
// the prompt without the job folder. Both cases are covered by sending the agent to the file.
export const NO_NOTES_TEXT = "(no notes in this prompt: read tests/PERSON_NOTES.md if it exists; when it does not, this is the first repair of this copy since notes began)";

export function personNotesPath(jobFolder) {
  return join(jobFolder, "tests", PERSON_NOTES_FILE);
}

// The log's text as stored, or "" when the copy has none yet.
export function readPersonNotes(jobFolder) {
  const notesPath = personNotesPath(jobFolder);
  if (!existsSync(notesPath)) {
    return "";
  }
  return readFileSync(notesPath, "utf8");
}

function isNoteLine(line) {
  return line.startsWith("- ");
}

// The dated lines of a log, oldest first. The heading and blank lines are not entries.
export function noteLines(notesText) {
  const allLines = notesText.split("\n");
  const trimmedLines = allLines.map((line) => line.trimEnd());
  return trimmedLines.filter(isNoteLine);
}

// What the prompt shows: the dated lines, or a plain sentence when there are none.
export function personNotesForPrompt(notesText) {
  const lines = noteLines(notesText);
  if (lines.length === 0) {
    return NO_NOTES_TEXT;
  }
  return lines.join("\n");
}

// One line, no markdown list marker of its own, no line breaks, at most NOTE_MAX_CHARACTERS.
// Null when nothing usable is left.
export function cleanNote(rawNote) {
  if (typeof rawNote !== "string") {
    return null;
  }
  const oneLine = rawNote.replace(/\s+/g, " ").trim();
  // A leading "-" or "*" would read as a second list marker inside the log line.
  const withoutMarker = oneLine.replace(/^[-*]+\s*/, "");
  if (withoutMarker.length === 0) {
    return null;
  }
  if (withoutMarker.length <= NOTE_MAX_CHARACTERS) {
    return withoutMarker;
  }
  const shortened = withoutMarker.slice(0, NOTE_MAX_CHARACTERS - 1).trimEnd();
  return `${shortened}…`;
}

// The first sentence of the founder's summary: used only when a fixed job wrote no note, so the
// log still says what changed.
export function firstSentence(summaryText) {
  if (typeof summaryText !== "string") {
    return null;
  }
  const sentenceMatch = /^(.+?[.!?])(\s|$)/.exec(summaryText.trim());
  if (sentenceMatch === null) {
    return summaryText.trim();
  }
  return sentenceMatch[1];
}

// The local calendar day of the runner as YYYY-MM-DD (the founder reads these dates).
export function noteDate(now) {
  const year = String(now.getFullYear());
  const month = String(now.getMonth() + 1).padStart(2, "0");
  const day = String(now.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

export function formatNoteLine({ note, now, reportId }) {
  const reportPart = typeof reportId === "string" && reportId.length > 0 ? ` (repair ${reportId})` : "";
  return `- ${noteDate(now)}: ${note}${reportPart}`;
}

// The new log text: the heading, then the kept lines plus the new one, newest last.
export function appendNoteLine(notesText, newLine) {
  const existingLines = noteLines(notesText);
  const allLines = [...existingLines, newLine];
  const keptLines = allLines.slice(-NOTES_MAX_LINES);
  return `${PERSON_NOTES_HEADING}\n\n${keptLines.join("\n")}\n`;
}

function readOutcomeObject(jobFolder) {
  const outcomePath = join(jobFolder, OUTCOME_FILE);
  if (!existsSync(outcomePath)) {
    return null;
  }
  try {
    const parsed = JSON.parse(readFileSync(outcomePath, "utf8"));
    if (parsed === null || typeof parsed !== "object") {
      return null;
    }
    return parsed;
  } catch {
    return null;
  }
}

// The line a fixed job adds: the agent's note, else the summary's first sentence. Null for any
// other result (unsupported and no_change publish nothing, so the log does not move).
export function noteForOutcome(outcome) {
  if (outcome === null || outcome.result !== "fixed") {
    return null;
  }
  const fromNote = cleanNote(outcome.note);
  if (fromNote !== null) {
    return fromNote;
  }
  return cleanNote(firstSentence(outcome.summary));
}

// Called by the runner after compareTests passes and before the publish, so the new line goes out
// with the fix. Returns { appended: false } or { appended: true, line }.
export function appendPersonNoteFromOutcome({ jobFolder, now = new Date(), reportId = null }) {
  const outcome = readOutcomeObject(jobFolder);
  const note = noteForOutcome(outcome);
  if (note === null) {
    return { appended: false };
  }
  const line = formatNoteLine({ note, now, reportId });
  const updatedText = appendNoteLine(readPersonNotes(jobFolder), line);
  writeFileSync(personNotesPath(jobFolder), updatedText);
  return { appended: true, line };
}
