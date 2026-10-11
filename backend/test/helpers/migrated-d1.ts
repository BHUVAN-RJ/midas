import { DatabaseSync } from "node:sqlite";
import { readdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

// A D1 stand-in backed by a real in-memory SQLite database with every migration in
// backend/migrations applied in file order, the way `wrangler d1 migrations apply` runs them.
// Covers only the D1 calls the routes make. (sqlite-d1.ts applies 0001 only.)

const MIGRATIONS_DIRECTORY = fileURLToPath(new URL("../../migrations/", import.meta.url));

type SqlValue = string | number | null;

function toSqlValue(value: unknown): SqlValue {
  if (value === undefined) {
    return null;
  }
  return value as SqlValue;
}

export function migrationFileNames(): string[] {
  const allFileNames = readdirSync(MIGRATIONS_DIRECTORY);
  const sqlFileNames = allFileNames.filter(isSqlFileName);
  sqlFileNames.sort();
  return sqlFileNames;
}

function isSqlFileName(fileName: string): boolean {
  return fileName.endsWith(".sql");
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
    return { success: true, meta: { changes: Number(result.changes), last_row_id: Number(result.lastInsertRowid) } };
  }
  function runNow() {
    const prepared = database.prepare(sql);
    const result = prepared.run(...params);
    return { success: true, meta: { changes: Number(result.changes), last_row_id: Number(result.lastInsertRowid) } };
  }
  return { bind: bindParams, first: firstRow, all: allRows, run: runStatement, runNow };
}

type FakeStatement = ReturnType<typeof makeStatement>;

export function makeMigratedD1() {
  const database = new DatabaseSync(":memory:");
  for (const fileName of migrationFileNames()) {
    const migrationSql = readFileSync(MIGRATIONS_DIRECTORY + fileName, "utf8");
    database.exec(migrationSql);
  }

  function prepareStatement(sql: string) {
    return makeStatement(database, sql, []);
  }

  // D1 runs a batch as one transaction; so does this.
  async function runBatch(statements: FakeStatement[]) {
    const results = [];
    database.exec("BEGIN");
    try {
      for (const statement of statements) {
        results.push(statement.runNow());
      }
      database.exec("COMMIT");
    } catch (error) {
      database.exec("ROLLBACK");
      throw error;
    }
    return results;
  }

  // Direct access for tests that inspect, seed or age rows.
  function query(sql: string, ...params: SqlValue[]) {
    const prepared = database.prepare(sql);
    return prepared.all(...params) as Record<string, unknown>[];
  }

  function execute(sql: string, ...params: SqlValue[]) {
    const prepared = database.prepare(sql);
    prepared.run(...params);
  }

  return { prepare: prepareStatement, batch: runBatch, query, execute };
}
