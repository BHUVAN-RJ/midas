// Usage, from backend/: node scripts/assign-make-to-everyone.mjs --env staging|live
// Make for everyone (founder, 2026-10-24): gives every existing user the Make Sidekick. New users
// get it at sign-up (auth.ts). Insert only, so running it twice changes nothing. The founder runs
// it on live, and only after the app with Make is on TestFlight (an older app treats "make" as a
// web page and gets a 404).
import { assignToEveryoneSql, rowsFromWranglerJson } from "./db-tools.mjs";
import { environmentFromArgs } from "./environments.mjs";
import { captureWrangler } from "./wrangler.mjs";

const MAKE_SIDEKICK_ID = "make";

const commandArgs = process.argv.slice(2);
const environment = environmentFromArgs(commandArgs);
if (environment === null) {
  console.error("usage: node scripts/assign-make-to-everyone.mjs --env staging|live");
  process.exit(1);
}

function executeRemote(sql) {
  const wranglerArgs = ["d1", "execute", environment.database, "--remote", "--json", "--command", sql, ...environment.wranglerEnvArgs];
  const outputText = captureWrangler(wranglerArgs);
  return rowsFromWranglerJson(outputText);
}

executeRemote(assignToEveryoneSql(MAKE_SIDEKICK_ID, new Date()));
const countSql = `SELECT COUNT(*) AS users, (SELECT COUNT(*) FROM assignments WHERE sidekick_id = '${MAKE_SIDEKICK_ID}') AS with_make FROM users`;
const counts = executeRemote(countSql)[0] ?? {};
console.log(`${counts.with_make} of ${counts.users} users have Make on ${environment.name}`);
