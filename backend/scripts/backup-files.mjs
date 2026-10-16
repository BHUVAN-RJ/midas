// User files backup (unified data plan, section 7: "backup-db.mjs gains an R2 files copy").
// Every file a record refers to ("file:<id>" anywhere in a stored value) is copied from the
// environment's files bucket to ~/midas-backups/files/<env>/<userId>/<fileId> on this Mac. Files
// already there are not fetched again (files are never changed once stored). Nothing is deleted.
// The pure parts are exported for the tests; the wrangler calls are injected.
import { existsSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { rowsFromWranglerJson } from "./db-tools.mjs";
import { captureWrangler, runWrangler } from "./wrangler.mjs";

export const FILES_BACKUP_DIRECTORY = join(homedir(), "midas-backups", "files");
const FILE_REFERENCE_PATTERN = /^file:([A-Za-z0-9_-]{1,64})$/;
const USER_ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;

// Live records only: a tombstone has no value. The LIKE narrows the rows the script reads; the
// exact check is done on the parsed value.
export const FILE_ROWS_SQL = "SELECT user_id, value FROM ops WHERE deleted = 0 AND value LIKE '%\"file:%'";

// Every "file:<id>" string inside a JSON value, however deep.
export function fileIdsInValue(value) {
  const fileIds = [];
  collectFileIds(value, fileIds);
  return fileIds;
}

function collectFileIds(value, fileIds) {
  if (typeof value === "string") {
    const match = FILE_REFERENCE_PATTERN.exec(value);
    if (match !== null) {
      fileIds.push(match[1]);
    }
    return;
  }
  if (Array.isArray(value)) {
    for (const item of value) {
      collectFileIds(item, fileIds);
    }
    return;
  }
  if (typeof value === "object" && value !== null) {
    for (const fieldName of Object.keys(value)) {
      collectFileIds(value[fieldName], fileIds);
    }
  }
}

// The files the ops rows refer to, as { userId, fileId }, each once, in a stable order.
export function fileReferences(opRows) {
  const seen = new Set();
  const references = [];
  for (const row of opRows) {
    if (typeof row.user_id !== "string" || !USER_ID_PATTERN.test(row.user_id) || typeof row.value !== "string") {
      continue;
    }
    let parsedValue;
    try {
      parsedValue = JSON.parse(row.value);
    } catch {
      continue;
    }
    for (const fileId of fileIdsInValue(parsedValue)) {
      const referenceKey = `${row.user_id}/${fileId}`;
      if (!seen.has(referenceKey)) {
        seen.add(referenceKey);
        references.push({ userId: row.user_id, fileId });
      }
    }
  }
  references.sort(compareReferences);
  return references;
}

function compareReferences(first, second) {
  const firstKey = `${first.userId}/${first.fileId}`;
  const secondKey = `${second.userId}/${second.fileId}`;
  if (firstKey < secondKey) {
    return -1;
  }
  return firstKey > secondKey ? 1 : 0;
}

// Copies every referenced file that is not already backed up. Returns the references fetched.
export function backupFiles(environment, options = {}) {
  const capture = options.capture ?? captureWrangler;
  const run = options.run ?? runWrangler;
  const directory = options.directory ?? join(FILES_BACKUP_DIRECTORY, environment.name);
  const rowsJson = capture(["d1", "execute", environment.database, "--remote", "--json", "--command", FILE_ROWS_SQL, ...environment.wranglerEnvArgs]);
  const references = fileReferences(rowsFromWranglerJson(rowsJson));
  const fetched = [];
  for (const reference of references) {
    const userDirectory = join(directory, reference.userId);
    const localPath = join(userDirectory, reference.fileId);
    if (existsSync(localPath)) {
      continue;
    }
    mkdirSync(userDirectory, { recursive: true });
    run(["r2", "object", "get", `${environment.filesBucket}/${reference.userId}/${reference.fileId}`, "--file", localPath, "--remote"]);
    fetched.push(reference);
  }
  console.log(`files backup: ${references.length} referenced, ${fetched.length} fetched to ${directory}`);
  return fetched;
}
