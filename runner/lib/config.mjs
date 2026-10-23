// Runner settings. Everything comes from environment variables so the launchd job, a shell and
// the tests all configure the runner the same way. `loadEnvFile` reads ~/.midas-runner/env
// (KEY=VALUE lines) into process.env before the settings are read.
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

// The repo this runner file belongs to: runner/lib/config.mjs -> repo root.
export const REPO_ROOT = resolve(fileURLToPath(new URL("../../", import.meta.url)));

export const DEFAULT_ENV_FILE = join(homedir(), ".midas-runner", "env");

// A path the repair agent can type bare in a Bash command, matching its allow rule exactly: no
// spaces, quotes or shell characters.
const PLAIN_PATH_PATTERN = /^\/[A-Za-z0-9._\/-]+$/;

export function isPlainPath(path) {
  return PLAIN_PATH_PATTERN.test(path);
}

const DEFAULTS = {
  pollIntervalMs: 30_000,
  heartbeatIntervalMs: 5 * 60_000,
  jobTimeoutMs: 30 * 60_000,
  maxTurns: 50,
  model: "opus",
};

// Parses KEY=VALUE lines; blank lines and # comments are skipped. Values are not unquoted
// beyond stripping one pair of matching quotes.
export function parseEnvFile(text) {
  const variables = {};
  const lines = text.split("\n");
  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (line.length === 0 || line.startsWith("#")) {
      continue;
    }
    const equalsIndex = line.indexOf("=");
    if (equalsIndex === -1) {
      continue;
    }
    const key = line.slice(0, equalsIndex).trim();
    let value = line.slice(equalsIndex + 1).trim();
    const isQuoted = value.length >= 2 && ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'")));
    if (isQuoted) {
      value = value.slice(1, -1);
    }
    variables[key] = value;
  }
  return variables;
}

// Loads the env file into process.env without overriding variables already set.
export function loadEnvFile(filePath = DEFAULT_ENV_FILE) {
  let text;
  try {
    text = readFileSync(filePath, "utf8");
  } catch {
    return {};
  }
  const variables = parseEnvFile(text);
  for (const [key, value] of Object.entries(variables)) {
    if (process.env[key] === undefined) {
      process.env[key] = value;
    }
  }
  return variables;
}

function integerFromEnv(environment, name, fallback) {
  const rawValue = environment[name];
  if (rawValue === undefined || rawValue === "") {
    return fallback;
  }
  const parsed = Number.parseInt(rawValue, 10);
  if (Number.isNaN(parsed) || parsed <= 0) {
    throw new Error(`${name} must be a positive integer, got "${rawValue}"`);
  }
  return parsed;
}

// Builds the settings object from an environment (process.env by default). Required:
// MIDAS_BACKEND_URL and MIDAS_RUNNER_TOKEN. Everything else has a default.
// Which server's Sidekick copies the runner reads and publishes: "live" (default, the everyday
// Midas) or "staging" (the "Midas Test" app, founder 2026-10-14). Set MIDAS_RUNNER_ENV; it must
// match MIDAS_BACKEND_URL's server. Anything else stops the runner.
export function runnerEnvironment(environment = process.env) {
  const value = environment.MIDAS_RUNNER_ENV || "live";
  if (value !== "live" && value !== "staging") {
    throw new Error(`MIDAS_RUNNER_ENV must be live or staging, not ${value}`);
  }
  return value;
}

// The settings that only running the agent needs (claude, its config dir, model, checkout), with
// no backend: runner/bin/check-sandbox.mjs --agent uses these on a Mac without a runner token.
export function agentSettingsFromEnv(environment = process.env) {
  return {
    // The repo checkout whose Sidekick tests are run against a fixed page: this runner's own.
    checkoutRoot: environment.MIDAS_RUNNER_CHECKOUT || REPO_ROOT,
    claudeCommand: environment.MIDAS_CLAUDE_COMMAND || "claude",
    claudeConfigDir: environment.CLAUDE_CONFIG_DIR || join(homedir(), ".midas-runner", "claude"),
    model: environment.MIDAS_RUNNER_MODEL || DEFAULTS.model,
  };
}

// The environments the runner serves, in polling order (founder, 2026-10-21: one runner serves
// live and staging). Two forms, which may be combined:
//   per environment: MIDAS_LIVE_BACKEND_URL + MIDAS_LIVE_RUNNER_TOKEN, and/or
//                    MIDAS_STAGING_BACKEND_URL + MIDAS_STAGING_RUNNER_TOKEN
//   single (the old form): MIDAS_BACKEND_URL + MIDAS_RUNNER_TOKEN, for MIDAS_RUNNER_ENV (default live)
// An environment named by both forms must get the same URL and token from both.
export const ENVIRONMENT_NAMES = ["live", "staging"];

export function environmentVariableNames(environmentName) {
  const prefix = `MIDAS_${environmentName.toUpperCase()}`;
  return { urlName: `${prefix}_BACKEND_URL`, tokenName: `${prefix}_RUNNER_TOKEN` };
}

function trimTrailingSlashes(url) {
  return url.replace(/\/+$/, "");
}

function perEnvironmentEntries(environment) {
  const entries = [];
  for (const environmentName of ENVIRONMENT_NAMES) {
    const { urlName, tokenName } = environmentVariableNames(environmentName);
    const backendUrl = environment[urlName];
    const runnerToken = environment[tokenName];
    if (!backendUrl && !runnerToken) {
      continue;
    }
    if (!backendUrl) {
      throw new Error(`${tokenName} is set but ${urlName} is not`);
    }
    if (!runnerToken) {
      throw new Error(`${urlName} is set but ${tokenName} is not`);
    }
    entries.push({ name: environmentName, backendUrl: trimTrailingSlashes(backendUrl), runnerToken, urlVariable: urlName });
  }
  return entries;
}

function singleEnvironmentEntry(environment) {
  const backendUrl = environment.MIDAS_BACKEND_URL;
  const runnerToken = environment.MIDAS_RUNNER_TOKEN;
  if (!backendUrl && !runnerToken) {
    return null;
  }
  if (!backendUrl) {
    throw new Error("MIDAS_BACKEND_URL is not set");
  }
  if (!runnerToken) {
    throw new Error("MIDAS_RUNNER_TOKEN is not set");
  }
  return { name: runnerEnvironment(environment), backendUrl: trimTrailingSlashes(backendUrl), runnerToken, urlVariable: "MIDAS_BACKEND_URL" };
}

function entryNamed(entries, environmentName) {
  for (const entry of entries) {
    if (entry.name === environmentName) {
      return entry;
    }
  }
  return undefined;
}

// Live before staging, whichever form named them.
function byEnvironmentOrder(first, second) {
  return ENVIRONMENT_NAMES.indexOf(first.name) - ENVIRONMENT_NAMES.indexOf(second.name);
}

export function environmentsFromEnv(environment = process.env) {
  const entries = perEnvironmentEntries(environment);
  const single = singleEnvironmentEntry(environment);
  if (single === null) {
    return entries;
  }
  const sameName = entryNamed(entries, single.name);
  if (sameName === undefined) {
    entries.push(single);
    entries.sort(byEnvironmentOrder);
    return entries;
  }
  if (sameName.backendUrl !== single.backendUrl || sameName.runnerToken !== single.runnerToken) {
    throw new Error(`${single.name} is set twice with different values: MIDAS_BACKEND_URL/MIDAS_RUNNER_TOKEN and ${sameName.urlVariable}/${environmentVariableNames(single.name).tokenName}; keep one`);
  }
  return entries;
}

// Builds the settings object from an environment (process.env by default). Required: at least
// one environment (see environmentsFromEnv). Everything else has a default. backendUrl,
// runnerToken and deployEnvironment are the first environment's; a job runs with
// settingsForEnvironment(settings, job.environment).
export function settingsFromEnv(environment = process.env) {
  const environments = environmentsFromEnv(environment);
  if (environments.length === 0) {
    throw new Error("MIDAS_BACKEND_URL is not set (nor MIDAS_LIVE_BACKEND_URL or MIDAS_STAGING_BACKEND_URL)");
  }
  const first = environments[0];
  const runnerHome = environment.MIDAS_RUNNER_HOME || join(homedir(), "Library", "Application Support", "midas-runner");
  return {
    ...agentSettingsFromEnv(environment),
    environments,
    backendUrl: first.backendUrl,
    runnerToken: first.runnerToken,
    deployEnvironment: first.name,
    runnerHome,
    jobsRoot: join(runnerHome, "jobs"),
    logsRoot: join(runnerHome, "log"),
    // Where the agent's tools are linked at a path without spaces (runner/lib/agent.mjs).
    toolLinkRoot: environment.MIDAS_RUNNER_TOOL_LINKS || join(homedir(), ".midas-runner"),
    maxTurns: integerFromEnv(environment, "MIDAS_RUNNER_MAX_TURNS", DEFAULTS.maxTurns),
    jobTimeoutMs: integerFromEnv(environment, "MIDAS_RUNNER_JOB_TIMEOUT_MS", DEFAULTS.jobTimeoutMs),
    pollIntervalMs: integerFromEnv(environment, "MIDAS_RUNNER_POLL_MS", DEFAULTS.pollIntervalMs),
    heartbeatIntervalMs: integerFromEnv(environment, "MIDAS_RUNNER_HEARTBEAT_MS", DEFAULTS.heartbeatIntervalMs),
  };
}

// The Worker host of each environment (shell/Midas/PlatformConfig.swift, wrangler.jsonc). The
// runner reads the reporter's records from MIDAS_BACKEND_URL's database and publishes to
// MIDAS_RUNNER_ENV's bucket, so the two must name the same environment.
export const BACKEND_HOSTS = {
  live: "midas-api.midas-backend.workers.dev",
  staging: "midas-api-staging.midas-backend.workers.dev",
};

// The environment a backend URL belongs to, or null for any other host.
export function environmentOfBackendUrl(backendUrl) {
  let host;
  try {
    host = new URL(backendUrl).host;
  } catch {
    return null;
  }
  for (const [environmentName, environmentHost] of Object.entries(BACKEND_HOSTS)) {
    if (host === environmentHost) {
      return environmentName;
    }
  }
  return null;
}

// Throws unless the backend URL is the Worker of the environment the runner publishes to.
export function checkBackendMatchesEnvironment({ backendUrl, deployEnvironment }) {
  const urlEnvironment = environmentOfBackendUrl(backendUrl);
  if (urlEnvironment === null) {
    throw new Error(`MIDAS_BACKEND_URL ${backendUrl} is neither the live nor the staging Worker (${BACKEND_HOSTS.live}, ${BACKEND_HOSTS.staging})`);
  }
  if (urlEnvironment !== deployEnvironment) {
    throw new Error(`MIDAS_BACKEND_URL is the ${urlEnvironment} Worker but MIDAS_RUNNER_ENV is ${deployEnvironment}: records would come from ${urlEnvironment} and the fix would go to ${deployEnvironment}; set both to the same environment`);
  }
}

// The settings one job runs with: the job's environment's backend, token and publish
// environment, nothing of the other's. Throws for an environment the runner does not serve.
export function settingsForEnvironment(settings, environmentName) {
  const entry = entryNamed(settings.environments ?? [], environmentName);
  if (entry === undefined) {
    throw new Error(`the runner does not serve ${environmentName}`);
  }
  return { ...settings, backendUrl: entry.backendUrl, runnerToken: entry.runnerToken, deployEnvironment: entry.name };
}

// Each per-environment URL must be that environment's Worker (same rule as the single form).
function checkEnvironmentEntry(entry) {
  if (entry.urlVariable === "MIDAS_BACKEND_URL") {
    checkBackendMatchesEnvironment({ backendUrl: entry.backendUrl, deployEnvironment: entry.name });
    return;
  }
  const urlEnvironment = environmentOfBackendUrl(entry.backendUrl);
  if (urlEnvironment !== entry.name) {
    const found = urlEnvironment === null ? "neither the live nor the staging Worker" : `the ${urlEnvironment} Worker`;
    throw new Error(`${entry.urlVariable} ${entry.backendUrl} is ${found}, not the ${entry.name} Worker (${BACKEND_HOSTS[entry.name]})`);
  }
}

// The settings the runner starts with (runner.mjs, run-once.mjs): refuses to start when any
// environment's backend is not that environment's Worker, or the agent's tools cannot get a
// plain path.
export function startupSettings(environment = process.env) {
  const settings = settingsFromEnv(environment);
  for (const entry of settings.environments) {
    checkEnvironmentEntry(entry);
  }
  if (!isPlainPath(settings.toolLinkRoot)) {
    throw new Error(`the agent's tool link folder ${settings.toolLinkRoot} has spaces or shell characters; set MIDAS_RUNNER_TOOL_LINKS to a plain path`);
  }
  return settings;
}
