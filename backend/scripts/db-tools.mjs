// Pure helpers for the database scripts (assign, backup), kept apart from the wrangler calls so
// they can be tested. `wrangler d1 execute --command` takes no bound parameters, so values are
// quoted here, and only after they pass the same checks the routes use.

const SIDEKICK_ID_PATTERN = /^[a-z0-9-]{1,40}$/;
const MAX_NAME_LENGTH = 50;

// A SQL string literal: single quotes doubled. Refuses control characters outright.
export function sqlLiteral(text) {
  if (typeof text !== "string" || /[\u0000-\u001f]/.test(text)) {
    throw new Error("value cannot be used in SQL");
  }
  const escapedText = text.replaceAll("'", "''");
  return `'${escapedText}'`;
}

export function checkAssignArgs(userName, sidekickId) {
  const problems = [];
  const trimmedName = typeof userName === "string" ? userName.trim() : "";
  if (trimmedName.length === 0 || trimmedName.length > MAX_NAME_LENGTH) {
    problems.push(`name must be 1 to ${MAX_NAME_LENGTH} characters`);
  }
  if (!SIDEKICK_ID_PATTERN.test(sidekickId ?? "")) {
    problems.push("sidekick id must be lowercase letters, digits and dashes");
  }
  return problems;
}

// Names are unique regardless of case (migration 0002), so this finds at most one user.
export function findUserSql(userName) {
  const nameLiteral = sqlLiteral(userName.trim());
  return `SELECT id, name FROM users WHERE name = ${nameLiteral} COLLATE NOCASE`;
}

// Insert only. Assigning a Sidekick the user already has changes nothing.
export function assignmentSql(userId, sidekickId, assignedAt) {
  const userLiteral = sqlLiteral(userId);
  const sidekickLiteral = sqlLiteral(sidekickId);
  const timeLiteral = sqlLiteral(assignedAt.toISOString());
  return `INSERT OR IGNORE INTO assignments (user_id, sidekick_id, assigned_at) VALUES (${userLiteral}, ${sidekickLiteral}, ${timeLiteral})`;
}

// Gives every user a Sidekick (jess for everyone, founder 2026-10-22). Insert only: a user who
// already has it keeps their row.
export function assignToEveryoneSql(sidekickId, assignedAt) {
  const sidekickLiteral = sqlLiteral(sidekickId);
  const timeLiteral = sqlLiteral(assignedAt.toISOString());
  return `INSERT OR IGNORE INTO assignments (user_id, sidekick_id, assigned_at) SELECT id, ${sidekickLiteral}, ${timeLiteral} FROM users`;
}

// How many users there are, how many have the Sidekick on their home, and how many deleted it
// (build 22: deleting sets removed_at and keeps the row, so INSERT OR IGNORE never gives it back).
export function assignmentCountsSql(sidekickId) {
  const sidekickLiteral = sqlLiteral(sidekickId);
  return `SELECT (SELECT COUNT(*) FROM users) AS users, COUNT(CASE WHEN removed_at IS NULL THEN 1 END) AS active, COUNT(removed_at) AS removed FROM assignments WHERE sidekick_id = ${sidekickLiteral}`;
}

// Rows from `wrangler d1 execute --json` output: an array with one result set per statement.
export function rowsFromWranglerJson(outputText) {
  const resultSets = JSON.parse(outputText);
  const firstResultSet = resultSets[0] ?? {};
  return firstResultSet.results ?? [];
}

// "live-midas-20261011T090000Z.sql": sorts by time, names the environment and database.
export function backupFileName(environment, takenAt) {
  const isoTime = takenAt.toISOString();
  const withoutSeparators = isoTime.replace(/[-:]/g, "");
  const timestamp = withoutSeparators.replace(/\.\d+Z$/, "Z");
  return `${environment.name}-${environment.database}-${timestamp}.sql`;
}
