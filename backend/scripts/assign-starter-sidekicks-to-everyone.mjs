// Usage, from backend/: node scripts/assign-starter-sidekicks-to-everyone.mjs --env staging|live
// Starter Sidekicks for everyone (founder, 2026-11-01: "every account gets a to do, reminders,
// hydration"): gives every existing user Reminders, Water and To-Do. New users get them at sign-up
// (src/auth.ts, list in src/starter-sidekicks.ts; a test checks this copy matches).
// Insert only, so running it twice changes nothing. A person who deleted one of them (build 22:
// the row stays with removed_at set) keeps it deleted: INSERT OR IGNORE leaves their row alone.
// A Sidekick whose page is not deployed on this environment is still assigned; accounts see it
// once its base is deployed (scripts/deploy-sidekick.mjs). The script says which ones those are.
// Needs migration 0013 (removed_at) on the environment first.
import { pointerKeyFor } from "./bundle-tools.mjs";
import { assignToEveryoneSql, assignmentCountsSql, rowsFromWranglerJson } from "./db-tools.mjs";
import { environmentFromArgs } from "./environments.mjs";
import { captureWrangler } from "./wrangler.mjs";

const STARTER_SIDEKICK_IDS = ["reminders", "hydration", "todo"];

const commandArgs = process.argv.slice(2);
const environment = environmentFromArgs(commandArgs);
if (environment === null) {
  console.error("usage: node scripts/assign-starter-sidekicks-to-everyone.mjs --env staging|live");
  process.exit(1);
}

function executeRemote(sql) {
  const wranglerArgs = ["d1", "execute", environment.database, "--remote", "--json", "--command", sql, ...environment.wranglerEnvArgs];
  const outputText = captureWrangler(wranglerArgs);
  return rowsFromWranglerJson(outputText);
}

// Read only: whether the Sidekick has a base pointer in this environment's bundles bucket.
function isBaseDeployed(sidekickId) {
  const pointerLocation = `${environment.bucket}/${pointerKeyFor(sidekickId)}`;
  try {
    captureWrangler(["r2", "object", "get", pointerLocation, "--pipe", "--remote"]);
    return true;
  } catch {
    return false;
  }
}

const assignedAt = new Date();
for (const sidekickId of STARTER_SIDEKICK_IDS) {
  executeRemote(assignToEveryoneSql(sidekickId, assignedAt));
  const countRows = executeRemote(assignmentCountsSql(sidekickId));
  const counts = countRows[0] ?? {};
  const deployNote = isBaseDeployed(sidekickId) ? "" : " (page not deployed yet: shows once deployed)";
  console.log(`${sidekickId}: ${counts.active} of ${counts.users} users have it, ${counts.removed} deleted it, on ${environment.name}${deployNote}`);
}
