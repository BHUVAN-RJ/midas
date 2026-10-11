// Scanners for the no-data-loss rails (2026-10-10): migrations only add, the Worker deletes only
// a used sign-in challenge, nothing ever rewrites or removes an op.

// Statements that remove rows or schema. REPLACE counts: INSERT OR REPLACE deletes the old row.
const DESTRUCTIVE_SQL = [
  { name: "DROP", pattern: /\bDROP\b/i },
  { name: "DELETE", pattern: /\bDELETE\b/i },
  { name: "REPLACE", pattern: /\bREPLACE\b/i },
  { name: "TRUNCATE", pattern: /\bTRUNCATE\b/i },
];

// Deletes the Worker may run without the founder. Phase 3 adds the expired-row cleanup here.
export const ALLOWED_WORKER_DELETES = ["DELETE FROM auth_challenges WHERE id = ?"];

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

// For Worker source: deletes outside the allowed list, and any other destructive statement.
export function workerCodeViolations(codeText: string): string[] {
  const code = stripCodeComments(codeText);
  const violations: string[] = [];
  for (const deleteMatch of code.matchAll(DELETE_STATEMENT)) {
    if (!isAllowedDelete(deleteMatch[0])) {
      violations.push(deleteMatch[0].trim());
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
