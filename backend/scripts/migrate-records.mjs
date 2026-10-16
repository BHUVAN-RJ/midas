// Usage, from backend/:
//   node scripts/migrate-records.mjs --env staging|live --dry-run        shows the plan, writes nothing
//   node scripts/migrate-records.mjs --env staging|live [--user <id>]    backs up, then writes
// Moves every user's records to the unified shapes (unified data plan, section 8): one batch of
// new ops per user rewrites old shapes (task: -> reminder: plus a tombstone; body -> notes; epoch
// ms -> ISO; $type added; care ~rule and @HHMM records folded into their item plus tombstones;
// settings:sidebar -> settings:self). Nothing is deleted: tombstones are new rows, old rows stay.
// Every new value is checked against the Sidekick's manifest schemas (sidekicks/<id>/manifest.json)
// before anything is written; a value that fails stops the run for that user. Op ids are
// deterministic, so a rerun stores nothing twice. Order (plan): backup, staging, Midas Test, then
// the founder runs live.
import { createHash } from "node:crypto";
import { readFileSync, existsSync } from "node:fs";
import { pathToFileURL } from "node:url";
import { backupDatabase } from "./backup-db.mjs";
import { rowsFromWranglerJson, sqlLiteral } from "./db-tools.mjs";
import { environmentFromArgs, positionalArgs } from "./environments.mjs";
import { itemCount, migrationOpId, recordsAfter, replayOps, upgradeSidekickRecords } from "./record-upgrades.mjs";
import { captureWrangler, runWrangler } from "./wrangler.mjs";

const OPS_SQL = "SELECT seq, user_id, sidekick_id, key, value, deleted FROM ops ORDER BY seq";
const OPS_PER_INSERT = 40;

function stop(message) {
  console.error(message);
  process.exit(1);
}

function takeOption(args, name) {
  const flagIndex = args.indexOf(`--${name}`);
  if (flagIndex === -1) {
    return null;
  }
  const value = args[flagIndex + 1];
  args.splice(flagIndex, 2);
  return value ?? "";
}

function takeFlag(args, name) {
  const flagIndex = args.indexOf(`--${name}`);
  if (flagIndex === -1) {
    return false;
  }
  args.splice(flagIndex, 1);
  return true;
}

function sha256Hex(text) {
  return createHash("sha256").update(text, "utf8").digest("hex");
}

function readManifest(sidekickId) {
  const manifestPath = new URL(`../../sidekicks/${sidekickId}/manifest.json`, import.meta.url);
  if (!existsSync(manifestPath)) {
    return null;
  }
  return JSON.parse(readFileSync(manifestPath, "utf8"));
}

// The plan for every (user, Sidekick): what to write, what to tombstone, and the item counts.
export function planMigration(opRows, manifestFor, onlyUserId = null) {
  const plans = [];
  for (const group of replayOps(opRows)) {
    if (onlyUserId !== null && group.userId !== onlyUserId) {
      continue;
    }
    const manifest = manifestFor(group.sidekickId);
    const plan = upgradeSidekickRecords(group.sidekickId, group.records, manifest);
    const itemsBefore = itemCount(group.records);
    const itemsAfter = itemCount(recordsAfter(group.records, plan));
    plans.push({ userId: group.userId, sidekickId: group.sidekickId, plan, itemsBefore, itemsAfter });
  }
  return plans;
}

// The INSERT statements for one plan: writes first, then tombstones, each op once.
export function insertStatements(userId, sidekickId, plan, now) {
  const rows = [];
  for (const write of plan.writes) {
    rows.push({ opId: migrationOpId(sha256Hex, userId, sidekickId, write.key, write.value), key: write.key, value: JSON.stringify(write.value), deleted: 0 });
  }
  for (const key of plan.deletes) {
    rows.push({ opId: migrationOpId(sha256Hex, userId, sidekickId, key, null), key, value: null, deleted: 1 });
  }
  const statements = [];
  for (let start = 0; start < rows.length; start += OPS_PER_INSERT) {
    const chunk = rows.slice(start, start + OPS_PER_INSERT);
    const valueLists = [];
    for (const row of chunk) {
      const valueLiteral = row.value === null ? "NULL" : sqlLiteral(row.value);
      valueLists.push(`(${sqlLiteral(row.opId)}, ${sqlLiteral(userId)}, ${sqlLiteral(sidekickId)}, ${sqlLiteral(row.key)}, ${valueLiteral}, ${row.deleted}, ${sqlLiteral(now)}, ${sqlLiteral(now)})`);
    }
    statements.push(`INSERT INTO ops (op_id, user_id, sidekick_id, key, value, deleted, client_time, received_at) VALUES ${valueLists.join(", ")} ON CONFLICT(op_id) DO NOTHING`);
  }
  return statements;
}

function describePlan(entry) {
  const { userId, sidekickId, plan, itemsBefore, itemsAfter } = entry;
  const lines = [`${userId} ${sidekickId}: ${plan.writes.length} writes, ${plan.deletes.length} tombstones, ${plan.unchanged} unchanged, items ${itemsBefore} -> ${itemsAfter}`];
  for (const problem of plan.problems) {
    lines.push(`  PROBLEM ${problem.key}: ${problem.problem}`);
  }
  return lines.join("\n");
}

const isRunDirectly = import.meta.url === pathToFileURL(process.argv[1]).href;
if (isRunDirectly) {
  const commandArgs = process.argv.slice(2);
  const environment = environmentFromArgs(commandArgs);
  const remainingArgs = positionalArgs(commandArgs);
  const onlyUserId = takeOption(remainingArgs, "user");
  const isDryRun = takeFlag(remainingArgs, "dry-run");
  if (environment === null || remainingArgs.length > 0) {
    stop("usage: node scripts/migrate-records.mjs --env staging|live [--user <id>] [--dry-run]");
  }

  const opsJson = captureWrangler(["d1", "execute", environment.database, "--remote", "--json", "--command", OPS_SQL, ...environment.wranglerEnvArgs]);
  const plans = planMigration(rowsFromWranglerJson(opsJson), readManifest, onlyUserId);
  let hasProblems = false;
  let hasLoss = false;
  for (const entry of plans) {
    console.log(describePlan(entry));
    hasProblems = hasProblems || entry.plan.problems.length > 0;
    hasLoss = hasLoss || entry.itemsAfter < entry.itemsBefore;
  }
  if (hasLoss) {
    stop("a plan loses items; nothing written");
  }
  if (hasProblems) {
    stop("some upgraded records do not pass their schema; nothing written");
  }
  if (isDryRun) {
    console.log("dry run: nothing written");
    process.exit(0);
  }

  backupDatabase(environment);
  const now = new Date().toISOString();
  let written = 0;
  for (const entry of plans) {
    for (const statement of insertStatements(entry.userId, entry.sidekickId, entry.plan, now)) {
      runWrangler(["d1", "execute", environment.database, "--remote", "--command", statement, ...environment.wranglerEnvArgs]);
      written += 1;
    }
  }
  console.log(`migration written: ${written} statements on ${environment.name}`);
}
