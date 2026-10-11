import { readdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { migrationViolations, scriptViolations, workerCodeViolations } from "./helpers/sql-safety";

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

function violationsByFile(paths: string[], scan: (text: string) => string[]): Record<string, string[]> {
  const found: Record<string, string[]> = {};
  for (const path of paths) {
    const violations = scan(readFileSync(path, "utf8"));
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

  it("flags a delete in a script even of a challenge", () => {
    expect(scriptViolations('const sql = "DELETE FROM auth_challenges WHERE id = ?";')).toHaveLength(1);
    expect(scriptViolations('const sql = "INSERT OR IGNORE INTO assignments VALUES (1)";')).toEqual([]);
  });
});
