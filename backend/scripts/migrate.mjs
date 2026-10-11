// Usage, from backend/: node scripts/migrate.mjs --env staging|live
// Backs the database up first (backup-db.mjs), then applies any new migrations. If the backup
// fails, nothing is migrated. Wrangler lists the migrations and asks before applying them.
import { backupDatabase } from "./backup-db.mjs";
import { environmentFromArgs } from "./environments.mjs";
import { runWrangler } from "./wrangler.mjs";

const environment = environmentFromArgs(process.argv.slice(2));
if (environment === null) {
  console.error("usage: node scripts/migrate.mjs --env staging|live");
  process.exit(1);
}

try {
  backupDatabase(environment);
} catch (error) {
  console.error(`backup failed, nothing migrated: ${error instanceof Error ? error.message : error}`);
  process.exit(1);
}
runWrangler(["d1", "migrations", "apply", environment.database, "--remote", ...environment.wranglerEnvArgs]);
