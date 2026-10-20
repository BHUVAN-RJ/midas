// What the repair agent and the code it can start may see of the runner's environment (security
// review, 2026-10-20). After loadEnvFile the runner's process.env holds MIDAS_RUNNER_TOKEN,
// CLAUDE_CODE_OAUTH_TOKEN and whatever else ~/.midas-runner/env sets; none of that may reach a
// test the agent wrote. Both environments are built from allow-lists, never by copying and
// removing.

// Plain process settings: where programs are, the user, temp folder, language, time zone.
export const PLAIN_VARIABLE_NAMES = ["PATH", "HOME", "USER", "LOGNAME", "SHELL", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE", "TERM", "TZ"];

// The job's own settings, read by the check tool (agent.mjs agentEnvironment).
export const JOB_VARIABLE_NAMES = ["MIDAS_JOB_FOLDER", "MIDAS_RUNNER_CHECKOUT", "MIDAS_JOB_SIDEKICK_ID", "MIDAS_JOB_MANIFEST_BEFORE"];

function pickVariables(baseEnvironment, names) {
  const picked = {};
  for (const name of names) {
    if (baseEnvironment[name] !== undefined) {
      picked[name] = baseEnvironment[name];
    }
  }
  return picked;
}

// For anything that runs code the agent wrote (the sandbox's vitest, from the runner or from the
// check tool): the plain settings and nothing else. No token of any kind.
export function codeEnvironment(baseEnvironment = process.env) {
  return pickVariables(baseEnvironment, PLAIN_VARIABLE_NAMES);
}

// For claude itself: the plain settings, the job's settings, its config dir, and its own login:
// CLAUDE_CODE_OAUTH_TOKEN, or ANTHROPIC_API_KEY only when the founder opted in with
// MIDAS_RUNNER_USE_API_KEY=1. Never MIDAS_RUNNER_TOKEN.
export function claudeEnvironment(baseEnvironment = process.env) {
  const environment = pickVariables(baseEnvironment, [...PLAIN_VARIABLE_NAMES, ...JOB_VARIABLE_NAMES, "CLAUDE_CONFIG_DIR", "CLAUDE_CODE_OAUTH_TOKEN"]);
  if (baseEnvironment.MIDAS_RUNNER_USE_API_KEY === "1" && baseEnvironment.ANTHROPIC_API_KEY !== undefined) {
    environment.ANTHROPIC_API_KEY = baseEnvironment.ANTHROPIC_API_KEY;
  }
  return environment;
}
