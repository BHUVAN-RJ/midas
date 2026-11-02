// Usage (founder only, 2026-11-02; docs/briefs/account-deletion-2026-11-02.md):
//   cd ~/Desktop/Midas/midas/backend && node scripts/delete-account.mjs --env staging|live
//       every open request (age, due date, whether the alert reached your phone) and every done one
//   ... --user <userId>          what the person has, per table and R2 folder (changes nothing)
//   ... --user <userId> --yes    carries out the deletion, then removes them from ~/midas-backups
//   ... --user <userId> --check  the check afterwards: all zero, or what is left
// The Worker does the deletion (src/account-deletion.ts); this script holds no SQL. Token:
// MIDAS_STAGING_DELETION_TOKEN or MIDAS_LIVE_DELETION_TOKEN (the ACCOUNT_DELETION_TOKEN secret).
import { existsSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { BACKUP_DIRECTORY } from "./backup-db.mjs";
import { FILES_BACKUP_DIRECTORY } from "./backup-files.mjs";
import { BACKUP_BUCKET, environmentFromArgs } from "./environments.mjs";
import { runWrangler } from "./wrangler.mjs";

export const BACKEND_URLS = {
  staging: "https://midas-api-staging.midas-backend.workers.dev",
  live: "https://midas-api.midas-backend.workers.dev",
};

export const TOKEN_VARIABLES = {
  staging: "MIDAS_STAGING_DELETION_TOKEN",
  live: "MIDAS_LIVE_DELETION_TOKEN",
};

const USER_ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;

// { env, userId, mode: "list" | "preview" | "carry-out" | "check" } or { error }.
export function parseDeletionArgs(argv) {
  const environment = environmentFromArgs(argv);
  if (environment === null) {
    return { error: "usage: node scripts/delete-account.mjs --env staging|live [--user <id> [--yes | --check]]" };
  }
  const userIndex = argv.indexOf("--user");
  if (userIndex === -1) {
    return { environment, userId: null, mode: "list" };
  }
  const userId = argv[userIndex + 1] ?? "";
  if (!USER_ID_PATTERN.test(userId)) {
    return { error: "--user takes a user id (letters, digits, - or _)" };
  }
  const wantsCarryOut = argv.includes("--yes");
  const wantsCheck = argv.includes("--check");
  if (wantsCarryOut && wantsCheck) {
    return { error: "--yes and --check cannot go together" };
  }
  let mode = "preview";
  if (wantsCarryOut) {
    mode = "carry-out";
  } else if (wantsCheck) {
    mode = "check";
  }
  return { environment, userId, mode };
}

/* ---------- Backups on this Mac ---------- */

// Where an export holds a person's id: as a whole value ('ab_c', the user_id and about_user_id
// columns) or as the user part of a founder's inbox key ('req:ab_c:r1', 'person:ab_c') or of a
// deletion marker. Anything else, such as words in someone else's record, does not count.
const INBOX_KEY_KINDS = ["person", "req", "message", "card", "answer", "account-deleted"];

export function mentionsUserId(text, userId) {
  const quotedValue = `'${userId}'`;
  if (text.includes(quotedValue)) {
    return true;
  }
  for (const kind of INBOX_KEY_KINDS) {
    if (text.includes(`'${kind}:${userId}'`) || text.includes(`'${kind}:${userId}:`)) {
      return true;
    }
  }
  return false;
}

// The export split into statements, each with its ";" and the line end after it, so joining the
// pieces gives back the exact text. Quotes are followed, so a ";" inside a value does not split.
export function splitSqlStatements(sqlText) {
  const pieces = [];
  let start = 0;
  let isInString = false;
  for (let index = 0; index < sqlText.length; index += 1) {
    const character = sqlText[index];
    if (character === "'") {
      isInString = !isInString;
      continue;
    }
    if (character === ";" && !isInString) {
      let end = index + 1;
      if (sqlText[end] === "\n") {
        end += 1;
      }
      pieces.push(sqlText.slice(start, end));
      start = end;
      index = end - 1;
    }
  }
  if (start < sqlText.length) {
    pieces.push(sqlText.slice(start));
  }
  return pieces;
}

function isInsertStatement(piece) {
  return /^\s*INSERT\s+INTO\b/i.test(piece);
}

// The export without the rows that mention the user. Everything else (schema, other people's
// rows) stays byte for byte. Returns the new text and how many rows went.
export function withoutUserRows(sqlText, userId) {
  const pieces = splitSqlStatements(sqlText);
  const kept = [];
  let removed = 0;
  for (const piece of pieces) {
    if (isInsertStatement(piece) && mentionsUserId(piece, userId)) {
      removed += 1;
      continue;
    }
    kept.push(piece);
  }
  return { text: kept.join(""), removed };
}

// The database exports of one environment in ~/midas-backups (backup-db.mjs backupFileName).
export function exportFileNames(fileNames, environment) {
  const prefix = `${environment.name}-${environment.database}-`;
  const matching = [];
  for (const fileName of fileNames) {
    if (fileName.startsWith(prefix) && fileName.endsWith(".sql")) {
      matching.push(fileName);
    }
  }
  matching.sort();
  return matching;
}

// Rewrites each export that mentions the user and puts the new one over the R2 copy of the same
// name; removes the user's backed-up files. Returns a line per change for the founder.
export function removeUserFromBackups(environment, userId, deps = {}) {
  const backupDirectory = deps.backupDirectory ?? BACKUP_DIRECTORY;
  const filesDirectory = deps.filesDirectory ?? join(FILES_BACKUP_DIRECTORY, environment.name);
  const uploadExport = deps.uploadExport ?? uploadExportToR2;
  const lines = [];
  if (existsSync(backupDirectory)) {
    const exports = exportFileNames(readdirSync(backupDirectory), environment);
    for (const fileName of exports) {
      const localPath = join(backupDirectory, fileName);
      const original = readFileSync(localPath, "utf8");
      const scrubbed = withoutUserRows(original, userId);
      if (scrubbed.removed === 0) {
        continue;
      }
      writeFileSync(localPath, scrubbed.text);
      uploadExport(environment, fileName, localPath);
      lines.push(`${fileName}: ${scrubbed.removed} rows removed (here and in r2://${BACKUP_BUCKET}/${environment.name}/${fileName})`);
    }
  }
  const userFilesDirectory = join(filesDirectory, userId);
  if (USER_ID_PATTERN.test(userId) && existsSync(userFilesDirectory)) {
    rmSync(userFilesDirectory, { recursive: true, force: true });
    lines.push(`${userFilesDirectory}: removed`);
  }
  return lines;
}

function uploadExportToR2(environment, fileName, localPath) {
  const objectPath = `${BACKUP_BUCKET}/${environment.name}/${fileName}`;
  runWrangler(["r2", "object", "put", objectPath, "--file", localPath, "--content-type", "application/sql", "--remote"]);
}

/* ---------- Talking to the Worker ---------- */

export function deletionRequest(environment, token, path, method = "GET") {
  return {
    url: `${BACKEND_URLS[environment.name]}/account-deletions${path}`,
    init: { method, headers: { Authorization: `Deletion ${token}` } },
  };
}

function countLines(counts) {
  const lines = [];
  for (const [name, value] of Object.entries(counts ?? {})) {
    if (value > 0) {
      lines.push(`  ${name}: ${value}`);
    }
  }
  return lines;
}

export function formatList(reply) {
  const lines = [];
  const devicesNote = reply.founderSet ? `${reply.founderDevices} of your phones get the alerts` : "no founder set: alerts go nowhere";
  lines.push(devicesNote);
  if (reply.open.length === 0) {
    lines.push("No open requests.");
  }
  for (const request of reply.open) {
    const alertNote = request.alertDelivered ? "alert reached your phone" : `ALERT NOT DELIVERED (${request.alertResult ?? "none"})`;
    lines.push(`OPEN ${request.userName} (${request.userId}): asked ${request.ageDays} days ago, delete by ${request.dueDate}; ${alertNote}`);
    if (request.lastError !== null) {
      lines.push(`  last run stopped: ${request.lastError}`);
    }
  }
  for (const done of reply.done) {
    const runnerNote = done.runnerCleanedAt === null ? "Mac mini folders not removed yet" : `Mac mini: ${done.runnerResult}`;
    lines.push(`DONE ${done.userId}: deleted ${done.carriedOutAt}; ${runnerNote}`);
  }
  return lines.join("\n");
}

export function formatCounts(reply) {
  const lines = [`${reply.userId} (${reply.state}): ${reply.total} items`];
  lines.push(...countLines(reply.counts));
  if (reply.runner !== null && reply.runner !== undefined) {
    const runnerNote = reply.runner.cleanedAt === null ? "Mac mini folders not removed yet" : `Mac mini: ${reply.runner.result}`;
    lines.push(runnerNote);
  }
  const verdict = reply.allZero ? "All zero: nothing of theirs is left on the server." : `Left: ${reply.nonZero.join(", ")}`;
  lines.push(verdict);
  return lines.join("\n");
}

export function formatCarryOut(reply) {
  if (reply.deleted !== true) {
    const lines = [`Not finished: ${reply.error}`, "Left:", ...countLines(reply.remaining), "Run it again."];
    return lines.join("\n");
  }
  const lines = ["Deleted:", ...countLines(reply.counts)];
  const verdict = reply.allZero ? "Check: all zero." : "Check: NOT all zero, run --check.";
  lines.push(verdict);
  lines.push(`Your push: ${reply.alertResult}`);
  return lines.join("\n");
}

async function readReply(response) {
  const text = await response.text();
  try {
    return JSON.parse(text);
  } catch {
    return { error: text };
  }
}

// Runs one command; deps.fetch and deps.removeFromBackups are swapped in tests.
export async function runDeletionCommand(argv, deps = {}) {
  const parsed = parseDeletionArgs(argv);
  if (parsed.error !== undefined) {
    return { exitCode: 2, output: parsed.error };
  }
  const environmentVariables = deps.env ?? process.env;
  const token = environmentVariables[TOKEN_VARIABLES[parsed.environment.name]] ?? "";
  if (token.length === 0) {
    return { exitCode: 2, output: `${TOKEN_VARIABLES[parsed.environment.name]} is not set` };
  }
  const fetchImplementation = deps.fetch ?? globalThis.fetch;
  const removeFromBackups = deps.removeFromBackups ?? removeUserFromBackups;
  if (parsed.mode === "list") {
    const request = deletionRequest(parsed.environment, token, "");
    const response = await fetchImplementation(request.url, request.init);
    const reply = await readReply(response);
    return response.ok ? { exitCode: 0, output: formatList(reply) } : { exitCode: 1, output: `${response.status}: ${reply.error}` };
  }
  const userPath = `/${encodeURIComponent(parsed.userId)}`;
  if (parsed.mode === "preview" || parsed.mode === "check") {
    const request = deletionRequest(parsed.environment, token, userPath);
    const response = await fetchImplementation(request.url, request.init);
    const reply = await readReply(response);
    return response.ok ? { exitCode: 0, output: formatCounts(reply) } : { exitCode: 1, output: `${response.status}: ${reply.error}` };
  }
  const request = deletionRequest(parsed.environment, token, `${userPath}/carry-out`, "POST");
  const response = await fetchImplementation(request.url, request.init);
  const reply = await readReply(response);
  // Deleted before (from another Mac): the server has nothing left, this Mac's backups may still
  const isAlreadyDeleted = response.status === 409 && reply.error === "already deleted";
  if (isAlreadyDeleted) {
    const backupLines = removeFromBackups(parsed.environment, parsed.userId);
    const backupNote = backupLines.length === 0 ? "Backups on this Mac: nothing of theirs." : `Backups on this Mac:\n  ${backupLines.join("\n  ")}`;
    return { exitCode: 0, output: `Already deleted on the server (${reply.carriedOutAt}).\n${backupNote}` };
  }
  if (response.status !== 200 && response.status !== 500) {
    return { exitCode: 1, output: `${response.status}: ${reply.error}` };
  }
  const lines = [formatCarryOut(reply)];
  if (reply.deleted === true) {
    const backupLines = removeFromBackups(parsed.environment, parsed.userId);
    lines.push(backupLines.length === 0 ? "Backups on this Mac: nothing of theirs." : `Backups on this Mac:\n  ${backupLines.join("\n  ")}`);
  }
  return { exitCode: reply.deleted === true ? 0 : 1, output: lines.join("\n") };
}

const isRunDirectly = import.meta.url === pathToFileURL(process.argv[1]).href;
if (isRunDirectly) {
  const result = await runDeletionCommand(process.argv.slice(2));
  console.log(result.output);
  process.exitCode = result.exitCode;
}
