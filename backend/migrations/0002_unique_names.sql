-- Two people cannot have the same name (founder, 2026-10-10). "Priya" and "priya" count as the
-- same name. Apply with: node scripts/migrate.mjs --env staging|live

CREATE UNIQUE INDEX users_name_unique ON users(name COLLATE NOCASE);
