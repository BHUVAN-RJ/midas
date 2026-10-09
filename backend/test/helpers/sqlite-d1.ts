import { DatabaseSync } from "node:sqlite";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

// A D1 stand-in backed by a real in-memory SQLite database, with the real migrations applied,
// so the auth SQL is exercised as written. Covers only the D1 calls the routes make.

const MIGRATION_URLS = [new URL("../../migrations/0001_auth.sql", import.meta.url)];

type SqlValue = string | number | null;

function toSqlValue(value: unknown): SqlValue {
  if (value === undefined) {
    return null;
  }
  return value as SqlValue;
}

function makeStatement(database: DatabaseSync, sql: string, params: SqlValue[]) {
  function bindParams(...newParams: unknown[]) {
    const sqlValues = newParams.map(toSqlValue);
    return makeStatement(database, sql, sqlValues);
  }
  async function firstRow() {
    const prepared = database.prepare(sql);
    const row = prepared.get(...params);
    return row ?? null;
  }
  async function allRows() {
    const prepared = database.prepare(sql);
    const rows = prepared.all(...params);
    return { results: rows, success: true };
  }
  async function runStatement() {
    const prepared = database.prepare(sql);
    const result = prepared.run(...params);
    return { success: true, meta: { changes: Number(result.changes) } };
  }
  function runNow() {
    const prepared = database.prepare(sql);
    prepared.run(...params);
  }
  return { bind: bindParams, first: firstRow, all: allRows, run: runStatement, runNow };
}

type FakeStatement = ReturnType<typeof makeStatement>;

export function makeSqliteD1() {
  const database = new DatabaseSync(":memory:");
  for (const migrationUrl of MIGRATION_URLS) {
    const migrationSql = readFileSync(fileURLToPath(migrationUrl), "utf8");
    database.exec(migrationSql);
  }

  function prepareStatement(sql: string) {
    return makeStatement(database, sql, []);
  }

  // D1 runs a batch as one transaction; so does this.
  async function runBatch(statements: FakeStatement[]) {
    database.exec("BEGIN");
    try {
      for (const statement of statements) {
        statement.runNow();
      }
      database.exec("COMMIT");
    } catch (error) {
      database.exec("ROLLBACK");
      throw error;
    }
    return [];
  }

  // Direct access for tests that inspect or age rows.
  function query(sql: string, ...params: SqlValue[]) {
    const prepared = database.prepare(sql);
    return prepared.all(...params) as Record<string, unknown>[];
  }

  return { prepare: prepareStatement, batch: runBatch, query };
}
