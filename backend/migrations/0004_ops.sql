-- Records backed up to the server (D4, 2026-10-10). Every store write and every store delete
-- is one row; nothing here is ever changed or removed (a delete is a row with deleted = 1).
-- seq is assigned by the server, never reused, and orders all ops (last write wins per key).
-- value is the record's JSON text exactly as the Sidekick wrote it; NULL for a delete.
-- Apply with: node scripts/migrate.mjs --env staging|live

CREATE TABLE ops (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  op_id TEXT NOT NULL UNIQUE,
  user_id TEXT NOT NULL REFERENCES users(id),
  sidekick_id TEXT NOT NULL,
  key TEXT NOT NULL,
  value TEXT,
  deleted INTEGER NOT NULL CHECK (deleted IN (0, 1)),
  client_time TEXT,
  received_at TEXT NOT NULL
);
CREATE INDEX ops_by_user_seq ON ops(user_id, seq);

-- The database itself refuses to rewrite an op.
CREATE TRIGGER ops_are_never_updated BEFORE UPDATE ON ops
BEGIN
  SELECT RAISE(ABORT, 'ops are append only');
END;
