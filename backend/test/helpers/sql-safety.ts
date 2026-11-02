// Scanners for the no-data-loss rails (2026-10-10): migrations only add, the Worker deletes only
// a used sign-in challenge, nothing ever rewrites or removes an op. One exception: account
// deletion (founder, 2026-11-02), below.

// Statements that remove rows or schema. REPLACE counts: INSERT OR REPLACE deletes the old row.
const DESTRUCTIVE_SQL = [
  { name: "DROP", pattern: /\bDROP\b/i },
  { name: "DELETE", pattern: /\bDELETE\b/i },
  { name: "REPLACE", pattern: /\bREPLACE\b/i },
  { name: "TRUNCATE", pattern: /\bTRUNCATE\b/i },
];

// Deletes the Worker may run without the founder. Phase 3 adds the expired-row cleanup here.
export const ALLOWED_WORKER_DELETES = ["DELETE FROM auth_challenges WHERE id = ?"];

// Account deletion (founder, 2026-11-02, docs/PRODUCT.md "Settings and delete"): the one exception
// to "the op log is append only" and "the Worker never deletes". Allowed only in this file, only
// as these exact statements (whitespace normalized), each a whole string literal on its own.
export const ACCOUNT_DELETION_FILE = "src/account-deletion.ts";
export const ACCOUNT_DELETION_DELETES = [
  "DELETE FROM repair_events WHERE report_id IN (SELECT id FROM repair_reports WHERE user_id = ?)",
  "DELETE FROM jess_pending_requests WHERE user_id = ? OR report_id IN (SELECT id FROM repair_reports WHERE user_id = ?)",
  "DELETE FROM repair_reports WHERE user_id = ?",
  "DELETE FROM voice_logs WHERE user_id = ?",
  "DELETE FROM jess_requests WHERE user_id = ?",
  "DELETE FROM ops WHERE user_id = ?",
  "DELETE FROM assignments WHERE user_id = ?",
  "DELETE FROM sidekick_removals WHERE user_id = ?",
  "DELETE FROM push_devices WHERE user_id = ?",
  "DELETE FROM repair_blocked WHERE user_id = ?",
  "DELETE FROM sessions WHERE user_id = ?",
  "DELETE FROM passkeys WHERE user_id = ?",
  "DELETE FROM auth_challenges WHERE user_id = ?",
  "DELETE FROM make_events WHERE user_id = ? OR about_user_id = ?",
  "DELETE FROM account_deletion_requests WHERE user_id = ?",
  "DELETE FROM users WHERE id = ?",
  "DELETE FROM ops WHERE user_id = ? AND sidekick_id = ? AND seq IN (SELECT value FROM json_each(?))",
];

const DELETE_STATEMENT = /\bDELETE\s+FROM\s+[^"`'\n]*/gi;
const OTHER_DESTRUCTIVE_CODE = [
  { name: "DROP", pattern: /\bDROP\s+(TABLE|INDEX|VIEW|TRIGGER|COLUMN)\b/i },
  { name: "REPLACE", pattern: /\bREPLACE\s+INTO\b|\bOR\s+REPLACE\b/i },
  { name: "UPDATE ops", pattern: /\bUPDATE\s+ops\b/i },
  { name: "TRUNCATE", pattern: /\bTRUNCATE\b/i },
];

export function stripSqlComments(sqlText: string): string {
  const withoutBlockComments = sqlText.replace(/\/\*[\s\S]*?\*\//g, "");
  return withoutBlockComments.replace(/--[^\n]*/g, "");
}

// Comment lines in TS/JS are dropped so prose like "never DELETE FROM ops" is not flagged.
export function stripCodeComments(codeText: string): string {
  const withoutBlockComments = codeText.replace(/\/\*[\s\S]*?\*\//g, "");
  return withoutBlockComments.replace(/^\s*\/\/[^\n]*/gm, "");
}

export function migrationViolations(sqlText: string): string[] {
  const statements = stripSqlComments(sqlText);
  const violations: string[] = [];
  for (const destructive of DESTRUCTIVE_SQL) {
    if (destructive.pattern.test(statements)) {
      violations.push(destructive.name);
    }
  }
  return violations;
}

function isAllowedDelete(deleteStatement: string): boolean {
  const normalized = deleteStatement.replace(/\s+/g, " ");
  const trimmed = normalized.trim();
  for (const allowed of ALLOWED_WORKER_DELETES) {
    if (trimmed === allowed || trimmed.startsWith(`${allowed} `)) {
      return true;
    }
  }
  return false;
}

// The statement must be a whole string literal: opened and closed by the same quote, and the
// literal then ends the argument (",", ")"). A newline, a "${...}" or a "+" after it could widen it.
function isWholeStringArgument(code: string, matchStart: number, matchText: string): boolean {
  const openingQuote = code[matchStart - 1];
  const closingIndex = matchStart + matchText.length;
  const closingQuote = code[closingIndex];
  const isQuote = openingQuote === '"' || openingQuote === "'" || openingQuote === "`";
  if (!isQuote || closingQuote !== openingQuote) {
    return false;
  }
  const afterLiteral = code.slice(closingIndex + 1);
  return /^\s*[,)]/.test(afterLiteral);
}

function isAllowedAccountDeletion(code: string, matchStart: number, matchText: string, filePath: string): boolean {
  if (filePath !== ACCOUNT_DELETION_FILE) {
    return false;
  }
  const normalized = matchText.replace(/\s+/g, " ");
  const trimmed = normalized.trim();
  const isListed = ACCOUNT_DELETION_DELETES.includes(trimmed);
  return isListed && isWholeStringArgument(code, matchStart, matchText);
}

// For Worker source: deletes outside the allowed list, and any other destructive statement.
// filePath is relative to backend/ (e.g. "src/account-deletion.ts").
export function workerCodeViolations(codeText: string, filePath = ""): string[] {
  const code = stripCodeComments(codeText);
  const violations: string[] = [];
  for (const deleteMatch of code.matchAll(DELETE_STATEMENT)) {
    const matchText = deleteMatch[0];
    const matchStart = deleteMatch.index ?? 0;
    const allowedEverywhere = isAllowedDelete(matchText);
    const allowedHere = isAllowedAccountDeletion(code, matchStart, matchText, filePath);
    if (!allowedEverywhere && !allowedHere) {
      violations.push(matchText.trim());
    }
  }
  for (const destructive of OTHER_DESTRUCTIVE_CODE) {
    if (destructive.pattern.test(code)) {
      violations.push(destructive.name);
    }
  }
  return violations;
}

// For the founder's scripts: no delete of any kind.
export function scriptViolations(codeText: string): string[] {
  const code = stripCodeComments(codeText);
  const violations: string[] = [];
  for (const deleteMatch of code.matchAll(DELETE_STATEMENT)) {
    violations.push(deleteMatch[0].trim());
  }
  for (const destructive of OTHER_DESTRUCTIVE_CODE) {
    if (destructive.pattern.test(code)) {
      violations.push(destructive.name);
    }
  }
  return violations;
}
