import { readdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import {
  ACCOUNT_DELETION_DELETES,
  ACCOUNT_DELETION_FILE,
  migrationViolations,
  scriptViolations,
  workerCodeViolations,
} from "./helpers/sql-safety";

// No user data may be lost (2026-10-10). These read the real files on every run.

const BACKEND_DIRECTORY = fileURLToPath(new URL("../", import.meta.url));

function filesIn(subdirectory: string, extension: string): string[] {
  const directory = `${BACKEND_DIRECTORY}${subdirectory}/`;
  const fileNames = readdirSync(directory);
  const matching: string[] = [];
  for (const fileName of fileNames) {
    if (fileName.endsWith(extension)) {
      matching.push(directory + fileName);
    }
  }
  return matching;
}

// scan gets the file text and its path relative to backend/ (e.g. "src/account-deletion.ts").
function violationsByFile(paths: string[], scan: (text: string, filePath: string) => string[]): Record<string, string[]> {
  const found: Record<string, string[]> = {};
  for (const path of paths) {
    const relativePath = path.slice(BACKEND_DIRECTORY.length);
    const violations = scan(readFileSync(path, "utf8"), relativePath);
    if (violations.length > 0) {
      found[path] = violations;
    }
  }
  return found;
}

describe("the real files", () => {
  it("migrations only add: no DROP, DELETE, REPLACE or TRUNCATE in any migration", () => {
    const migrationPaths = filesIn("migrations", ".sql");
    expect(migrationPaths.length).toBeGreaterThanOrEqual(3);
    expect(violationsByFile(migrationPaths, migrationViolations)).toEqual({});
  });

  it("the Worker deletes only a used sign-in challenge and never rewrites rows by replace", () => {
    const sourcePaths = filesIn("src", ".ts");
    expect(sourcePaths.length).toBeGreaterThanOrEqual(3);
    expect(violationsByFile(sourcePaths, workerCodeViolations)).toEqual({});
  });

  it("account deletion's deletes are in src/account-deletion.ts, and only there", () => {
    const sourcePaths = filesIn("src", ".ts");
    const accountDeletionPath = `${BACKEND_DIRECTORY}${ACCOUNT_DELETION_FILE}`;
    expect(sourcePaths).toContain(accountDeletionPath);
    const accountDeletionCode = readFileSync(accountDeletionPath, "utf8");
    const withoutTheException = workerCodeViolations(accountDeletionCode, "src/elsewhere.ts");
    expect(withoutTheException).toHaveLength(ACCOUNT_DELETION_DELETES.length);
  });

  it("the founder's scripts contain no delete at all", () => {
    const scriptPaths = filesIn("scripts", ".mjs");
    expect(scriptPaths.length).toBeGreaterThanOrEqual(5);
    expect(violationsByFile(scriptPaths, scriptViolations)).toEqual({});
  });
});

describe("the scanners catch what they exist for", () => {
  it("flags destructive migrations, ignoring comments", () => {
    expect(migrationViolations("DROP TABLE users;")).toEqual(["DROP"]);
    expect(migrationViolations("ALTER TABLE users DROP COLUMN name;")).toEqual(["DROP"]);
    expect(migrationViolations("delete from sessions;")).toEqual(["DELETE"]);
    expect(migrationViolations("INSERT OR REPLACE INTO users VALUES (1);")).toEqual(["REPLACE"]);
    expect(migrationViolations("-- a deleted row is never dropped\nCREATE TABLE t (id TEXT);")).toEqual([]);
  });

  it("flags any Worker delete except the challenge one, and any op rewrite", () => {
    const allowedDelete = 'boundStatement(db, "DELETE FROM auth_challenges WHERE id = ? RETURNING *", id)';
    expect(workerCodeViolations(allowedDelete)).toEqual([]);
    expect(workerCodeViolations('db.prepare("DELETE FROM ops WHERE user_id = ?")')).toEqual(["DELETE FROM ops WHERE user_id = ?"]);
    expect(workerCodeViolations('db.prepare("DELETE FROM auth_challenges")')).toEqual(["DELETE FROM auth_challenges"]);
    expect(workerCodeViolations("db.prepare(`delete from users where id = ?`)")).toHaveLength(1);
    expect(workerCodeViolations('db.prepare("UPDATE ops SET value = ?")')).toEqual(["UPDATE ops"]);
    expect(workerCodeViolations('db.prepare("INSERT OR REPLACE INTO ops VALUES (?)")')).toEqual(["REPLACE"]);
    expect(workerCodeViolations('db.prepare("DROP TABLE ops")')).toEqual(["DROP"]);
    expect(workerCodeViolations("// never DELETE FROM ops\nconst x = 1;")).toEqual([]);
  });

  it("allows account deletion's exact statements in src/account-deletion.ts only (founder, 2026-11-02)", () => {
    expect(ACCOUNT_DELETION_DELETES).toHaveLength(17);
    for (const statement of ACCOUNT_DELETION_DELETES) {
      const code = `boundStatement(db, "${statement}", userId)`;
      expect(workerCodeViolations(code, ACCOUNT_DELETION_FILE)).toEqual([]);
      expect(workerCodeViolations(code, "src/account.ts")).toEqual([statement]);
      expect(workerCodeViolations(code)).toEqual([statement]);
      expect(scriptViolations(code)).toEqual([statement]);
    }
    const multiLine = 'boundStatement(\n  db,\n  "DELETE FROM users WHERE id = ?",\n  userId,\n)';
    expect(workerCodeViolations(multiLine, ACCOUNT_DELETION_FILE)).toEqual([]);
    expect(workerCodeViolations(multiLine, "src/account-deletion.test.ts")).toHaveLength(1);
  });

  it("flags a widened account deletion statement even in src/account-deletion.ts", () => {
    const widened = [
      'db.prepare("DELETE FROM ops")',
      'db.prepare("DELETE FROM ops WHERE user_id = ? OR 1=1")',
      'db.prepare("DELETE FROM ops WHERE user_id = ? OR user_id IS NOT NULL")',
      'db.prepare("DELETE FROM users WHERE id = ? OR id != ?")',
      'db.prepare("DELETE FROM users")',
      'db.prepare("DELETE FROM ops WHERE sidekick_id = ?")',
      'db.prepare("DELETE FROM ops WHERE user_id = ? AND sidekick_id = ?")',
      'db.prepare("delete from ops where user_id = ? or 1=1")',
      'db.prepare("DELETE FROM ops WHERE user_id = ?" + " OR 1=1")',
      "db.prepare(`DELETE FROM ops WHERE user_id = ?${extra}`)",
      "db.prepare(`DELETE FROM ops WHERE user_id = ?\n OR 1=1`)",
      'db.prepare("DELETE FROM sessions WHERE user_id = ? RETURNING *")',
    ];
    for (const code of widened) {
      expect(workerCodeViolations(code, ACCOUNT_DELETION_FILE)).toHaveLength(1);
    }
  });

  it("flags a delete in a script even of a challenge", () => {
    expect(scriptViolations('const sql = "DELETE FROM auth_challenges WHERE id = ?";')).toHaveLength(1);
    expect(scriptViolations('const sql = "INSERT OR IGNORE INTO assignments VALUES (1)";')).toEqual([]);
  });
});
