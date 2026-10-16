// Usage, from backend/: node scripts/backup-db.mjs --env staging|live
// Exports the whole D1 database to ~/midas-backups/ on this Mac (outside both repos) and
// uploads the same file to the midas-backups R2 bucket, then copies every user file the records
// refer to into ~/midas-backups/files/<env>/ (backup-files.mjs). Run before every remote
// migration (migrate.mjs does it for you). This plan is redone at 100 users (docs/CONCERNS.md).
import { existsSync, mkdirSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { backupFiles } from "./backup-files.mjs";
import { backupFileName } from "./db-tools.mjs";
import { BACKUP_BUCKET, environmentFromArgs } from "./environments.mjs";
import { runWrangler } from "./wrangler.mjs";

export const BACKUP_DIRECTORY = join(homedir(), "midas-backups");

// Returns the local path of the export. Throws if wrangler fails or writes no file, so a caller
// never continues without a backup. A brand-new database can export as an empty file.
export function backupDatabase(environment) {
  mkdirSync(BACKUP_DIRECTORY, { recursive: true });
  const fileName = backupFileName(environment, new Date());
  const localPath = join(BACKUP_DIRECTORY, fileName);

  runWrangler(["d1", "export", environment.database, "--remote", "--output", localPath, ...environment.wranglerEnvArgs]);
  if (!existsSync(localPath)) {
    throw new Error(`export produced no file at ${localPath}`);
  }
  const exportSize = statSync(localPath).size;

  const objectPath = `${BACKUP_BUCKET}/${environment.name}/${fileName}`;
  runWrangler(["r2", "object", "put", objectPath, "--file", localPath, "--content-type", "application/sql", "--remote"]);
  console.log(`backup saved (${exportSize} bytes): ${localPath} and r2://${objectPath}`);
  return localPath;
}

const isRunDirectly = import.meta.url === pathToFileURL(process.argv[1]).href;
if (isRunDirectly) {
  const environment = environmentFromArgs(process.argv.slice(2));
  if (environment === null) {
    console.error("usage: node scripts/backup-db.mjs --env staging|live");
    process.exit(1);
  }
  backupDatabase(environment);
  backupFiles(environment);
}
