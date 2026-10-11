// Usage, from backend/: node scripts/assign-sidekick.mjs "<user name>" <sidekick-id> --env staging|live
// Gives a user a Sidekick. Insert only: assigning one they already have changes nothing.
// Unassigning is not a script; it is the founder's to run by hand (2026-10-10).
import { assignmentSql, checkAssignArgs, findUserSql, rowsFromWranglerJson } from "./db-tools.mjs";
import { environmentFromArgs, positionalArgs } from "./environments.mjs";
import { captureWrangler } from "./wrangler.mjs";

function stop(message) {
  console.error(message);
  process.exit(1);
}

const commandArgs = process.argv.slice(2);
const environment = environmentFromArgs(commandArgs);
const [userName, sidekickId] = positionalArgs(commandArgs);
if (environment === null) {
  stop('usage: node scripts/assign-sidekick.mjs "<user name>" <sidekick-id> --env staging|live');
}
const problems = checkAssignArgs(userName, sidekickId);
if (problems.length > 0) {
  stop(problems.join("; "));
}

function executeRemote(sql) {
  const wranglerArgs = ["d1", "execute", environment.database, "--remote", "--json", "--command", sql, ...environment.wranglerEnvArgs];
  const outputText = captureWrangler(wranglerArgs);
  return rowsFromWranglerJson(outputText);
}

const matchingUsers = executeRemote(findUserSql(userName));
if (matchingUsers.length === 0) {
  stop(`no user named "${userName.trim()}" on ${environment.name}`);
}
const user = matchingUsers[0];

executeRemote(assignmentSql(user.id, sidekickId, new Date()));
console.log(`${user.name} has ${sidekickId} on ${environment.name}`);
