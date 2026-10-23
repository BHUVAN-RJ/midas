// Usage, from backend/: node scripts/jess-grow-log.mjs --env staging|live [--since 24h|7d|2026-10-21] [--limit 50]
// Founder only (jess grows the Sidekick, 2026-10-21): every pending request, newest first, with
// what was said, what jess found missing, the repair it filed, the re-run and every step. Read
// only; nothing is changed.
import { rowsFromWranglerJson } from "./db-tools.mjs";
import { environmentFromArgs } from "./environments.mjs";
import { formatGrowLogRows, growLogSql, parseGrowLogArgs } from "./jess-grow-log-tools.mjs";
import { captureWrangler } from "./wrangler.mjs";

function stop(message) {
  console.error(message);
  process.exit(1);
}

const commandArgs = process.argv.slice(2);
const environment = environmentFromArgs(commandArgs);
if (environment === null) {
  stop("usage: node scripts/jess-grow-log.mjs --env staging|live [--since 24h|7d|2026-10-21] [--limit 50]");
}
const parsedArgs = parseGrowLogArgs(commandArgs, new Date());
if (parsedArgs.problem) {
  stop(parsedArgs.problem);
}

const sql = growLogSql(parsedArgs.options);
const wranglerArgs = ["d1", "execute", environment.database, "--remote", "--json", "--command", sql, ...environment.wranglerEnvArgs];
const outputText = captureWrangler(wranglerArgs);
const rows = rowsFromWranglerJson(outputText);
console.log(formatGrowLogRows(rows));
