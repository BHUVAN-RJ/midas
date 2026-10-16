// The two places a script can act on. Every script that touches Cloudflare takes
// --env staging|live and refuses to run without it, so no command reaches live by default.
// The staging names must match the "staging" environment in wrangler.jsonc.

// filesBucket holds user files (unified data, founder 2026-10-15: midas-files-staging now,
// midas-files on live, created by the founder); records hold "file:<id>" references.
export const ENVIRONMENTS = {
  staging: { name: "staging", wranglerEnvArgs: ["--env", "staging"], bucket: "midas-bundles-staging", database: "midas-staging", filesBucket: "midas-files-staging" },
  live: { name: "live", wranglerEnvArgs: [], bucket: "midas-bundles", database: "midas", filesBucket: "midas-files" },
};

// Database exports go here, never into a bundles bucket, so no Worker can read them.
export const BACKUP_BUCKET = "midas-backups";

// Returns the environment named by "--env <name>" in argv, or null if it is missing or unknown.
export function environmentFromArgs(argv) {
  const flagIndex = argv.indexOf("--env");
  if (flagIndex === -1) {
    return null;
  }
  const environmentName = argv[flagIndex + 1];
  if (!Object.hasOwn(ENVIRONMENTS, environmentName)) {
    return null;
  }
  return ENVIRONMENTS[environmentName];
}

// The arguments left after removing "--env <name>".
export function positionalArgs(argv) {
  const remaining = [];
  for (let index = 0; index < argv.length; index += 1) {
    if (argv[index] === "--env") {
      index += 1;
      continue;
    }
    remaining.push(argv[index]);
  }
  return remaining;
}
