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
export function settingsFromEnv(environment = process.env) {
  const backendUrl = environment.MIDAS_BACKEND_URL;
  const runnerToken = environment.MIDAS_RUNNER_TOKEN;
  if (!backendUrl) {
    throw new Error("MIDAS_BACKEND_URL is not set");
  }
  if (!runnerToken) {
    throw new Error("MIDAS_RUNNER_TOKEN is not set");
  }
  const runnerHome = environment.MIDAS_RUNNER_HOME || join(homedir(), "Library", "Application Support", "midas-runner");
  return {
    backendUrl: backendUrl.replace(/\/+$/, ""),
    runnerToken,
    runnerHome,
    jobsRoot: join(runnerHome, "jobs"),
    logsRoot: join(runnerHome, "log"),
    // The repo checkout whose Sidekick tests are run against a fixed page: this runner's own.
    checkoutRoot: environment.MIDAS_RUNNER_CHECKOUT || REPO_ROOT,
    claudeCommand: environment.MIDAS_CLAUDE_COMMAND || "claude",
    claudeConfigDir: environment.CLAUDE_CONFIG_DIR || join(homedir(), ".midas-runner", "claude"),
    // The founder's own live user id, for the preview step in summary.md (optional).
    founderUserId: environment.MIDAS_FOUNDER_USER_ID || null,
    model: environment.MIDAS_RUNNER_MODEL || DEFAULTS.model,
    maxTurns: integerFromEnv(environment, "MIDAS_RUNNER_MAX_TURNS", DEFAULTS.maxTurns),
    jobTimeoutMs: integerFromEnv(environment, "MIDAS_RUNNER_JOB_TIMEOUT_MS", DEFAULTS.jobTimeoutMs),
    pollIntervalMs: integerFromEnv(environment, "MIDAS_RUNNER_POLL_MS", DEFAULTS.pollIntervalMs),
    heartbeatIntervalMs: integerFromEnv(environment, "MIDAS_RUNNER_HEARTBEAT_MS", DEFAULTS.heartbeatIntervalMs),
  };
}
