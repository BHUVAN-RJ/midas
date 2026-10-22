// Usage, from backend/: node scripts/assign-jess-to-everyone.mjs --env staging|live
// jess for everyone (founder, 2026-10-22): gives every existing user the jess Sidekick. New users
// get it at sign-up (auth.ts). Insert only, so running it twice changes nothing. The founder runs
// it on live.
import { assignToEveryoneSql, rowsFromWranglerJson } from "./db-tools.mjs";
import { environmentFromArgs } from "./environments.mjs";
import { captureWrangler } from "./wrangler.mjs";

const JESS_SIDEKICK_ID = "jess";

const commandArgs = process.argv.slice(2);
const environment = environmentFromArgs(commandArgs);
if (environment === null) {
  console.error("usage: node scripts/assign-jess-to-everyone.mjs --env staging|live");
  process.exit(1);
}

function executeRemote(sql) {
  const wranglerArgs = ["d1", "execute", environment.database, "--remote", "--json", "--command", sql, ...environment.wranglerEnvArgs];
  const outputText = captureWrangler(wranglerArgs);
  return rowsFromWranglerJson(outputText);
}

executeRemote(assignToEveryoneSql(JESS_SIDEKICK_ID, new Date()));
const countSql = `SELECT COUNT(*) AS users, (SELECT COUNT(*) FROM assignments WHERE sidekick_id = '${JESS_SIDEKICK_ID}') AS with_jess FROM users`;
const counts = executeRemote(countSql)[0] ?? {};
console.log(`${counts.with_jess} of ${counts.users} users have jess on ${environment.name}`);
