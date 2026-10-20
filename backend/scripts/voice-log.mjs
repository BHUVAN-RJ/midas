// Usage, from backend/: node scripts/voice-log.mjs --env staging|live [--failed] [--since 24h|7d|2026-10-19] [--limit 50]
// Founder only (2026-10-19): reads the voice reminder log, newest first, to see what worked and
// what did not. Read only; nothing in voice_logs is changed.
import { rowsFromWranglerJson } from "./db-tools.mjs";
import { environmentFromArgs } from "./environments.mjs";
import { formatVoiceLogRows, parseVoiceLogArgs, voiceLogSql } from "./voice-log-tools.mjs";
import { captureWrangler } from "./wrangler.mjs";

function stop(message) {
  console.error(message);
  process.exit(1);
}

const commandArgs = process.argv.slice(2);
const environment = environmentFromArgs(commandArgs);
if (environment === null) {
  stop("usage: node scripts/voice-log.mjs --env staging|live [--failed] [--since 24h|7d|2026-10-19] [--limit 50]");
}
const parsedArgs = parseVoiceLogArgs(commandArgs, new Date());
if (parsedArgs.problem) {
  stop(parsedArgs.problem);
}

const sql = voiceLogSql(parsedArgs.options);
const wranglerArgs = ["d1", "execute", environment.database, "--remote", "--json", "--command", sql, ...environment.wranglerEnvArgs];
const outputText = captureWrangler(wranglerArgs);
const rows = rowsFromWranglerJson(outputText);
console.log(formatVoiceLogRows(rows));
