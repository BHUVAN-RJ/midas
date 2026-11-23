// Runs Claude Code headless on a job folder. The agent gets a fixed, small set of tools: file
// tools inside the job folder, Bash for exactly two commands of ours (intel, check), and one
// subagent, test-guardian (the only way an existing test changes; founder, 2026-10-13). No web,
// no other subagents, no MCP servers, no slash commands, no settings from the founder's own
// ~/.claude (the runner has its own CLAUDE_CONFIG_DIR); project settings come from the job
// folder's .claude/, which the runner writes (the test guard hook and the guardian).
import { spawn } from "node:child_process";
import { createWriteStream, lstatSync, mkdirSync, readlinkSync, symlinkSync, unlinkSync } from "node:fs";
import { join } from "node:path";
import { REPO_ROOT, isPlainPath } from "./config.mjs";
import { claudeEnvironment } from "./safe-env.mjs";

export const TOOLS_FOLDER = join(REPO_ROOT, "runner", "tools");
export const INTEL_TOOL_PATH = join(TOOLS_FOLDER, "intel.mjs");
export const CHECK_TOOL_PATH = join(TOOLS_FOLDER, "check.mjs");

// The runner's clone sits under "~/Library/Application Support", so the agent reaches the tools
// through a link at a plain path (config.mjs isPlainPath; first staging run, 2026-10-19: a quoted
// path did not match the allow rule and the check tool was denied).
// The folder the tool link lives in: settings.toolLinkRoot (~/.midas-runner by default).
export const TOOL_LINK_NAME = "runner-tools";

// Points <linkRoot>/runner-tools at the tools folder (replacing a link to anywhere else) and
// returns the two tool paths through it. Only ever removes a symbolic link there: a real file or
// folder at that path is someone's, so it throws instead. Throws when linkRoot is not a plain path.
export function linkAgentTools({ linkRoot, toolsFolder = TOOLS_FOLDER }) {
  if (typeof linkRoot !== "string" || !isPlainPath(linkRoot)) {
    throw new Error(`the tool link folder "${linkRoot}" must be a path without spaces or shell characters; set MIDAS_RUNNER_TOOL_LINKS`);
  }
  mkdirSync(linkRoot, { recursive: true });
  const linkPath = join(linkRoot, TOOL_LINK_NAME);
  let existing = null;
  try {
    existing = lstatSync(linkPath);
  } catch {
    existing = null;
  }
  if (existing !== null && !existing.isSymbolicLink()) {
    throw new Error(`${linkPath} is a real ${existing.isDirectory() ? "folder" : "file"}, not the runner's tool link; move it away or set MIDAS_RUNNER_TOOL_LINKS`);
  }
  const existingTarget = existing === null ? null : readlinkSync(linkPath);
  if (existingTarget !== toolsFolder) {
    if (existing !== null) {
      unlinkSync(linkPath);
    }
    symlinkSync(toolsFolder, linkPath, "dir");
  }
  return { intelToolPath: join(linkPath, "intel.mjs"), checkToolPath: join(linkPath, "check.mjs") };
}

// The exact commands the prompt tells the agent to run, as typed.
export function checkToolCommand(checkToolPath) {
  return `node ${checkToolPath}`;
}

export const GUARDIAN_AGENT = "test-guardian";
export const AGENT_TOOLS = ["Read", "Edit", "Write", "Grep", "Glob", "Bash", "Agent"];
// Folders in the founder's home that hold secrets or private work (security review, 2026-10-22):
// the runner's env file and Claude login, Claude's own config, SSH keys, the wrangler (Cloudflare)
// login, the keychain, other config, and the founder's code and documents. Denied to the agent's
// file tools even if an allow rule would match; deny rules win in Claude Code.
export const AGENT_SECRET_PATHS = [
  "~/.midas-runner/**",
  "~/.claude/**",
  "~/.ssh/**",
  "~/.config/**",
  "~/.aws/**",
  "~/.npmrc",
  "~/.netrc",
  "~/.gitconfig",
  "~/Library/Preferences/.wrangler/**",
  "~/Library/Keychains/**",
  "~/code/**",
  "~/Desktop/**",
  "~/Documents/**",
];

function secretPathRules() {
  const rules = [];
  for (const secretPath of AGENT_SECRET_PATHS) {
    rules.push(`Read(${secretPath})`);
    rules.push(`Edit(${secretPath})`);
  }
  return rules;
}

// Every subagent the agent's session lists, by name, except the guardian; the Agent tool itself
// stays available for the guardian only. Never deny "Task": it is the Agent tool's own name in
// Claude Code, and denying it removes the tool, guardian included (repairs 50ca5522 and
// 9c699df4, 2026-10-24: no run since 2026-10-19 could reach the guardian).
// The job's own .claude/ (the test guard and the guardian) is never the agent's to change.
export const AGENT_DENIED_SUBAGENTS = ["Explore", "Plan", "general-purpose", "claude", "statusline-setup"];

function deniedSubagentRules() {
  const rules = [];
  for (const subagentName of AGENT_DENIED_SUBAGENTS) {
    rules.push(`Agent(${subagentName})`);
  }
  return rules;
}

export const AGENT_DENIED_TOOLS = [
  "WebFetch",
  "WebSearch",
  ...deniedSubagentRules(),
  "NotebookEdit",
  "TodoWrite",
  "Edit(./.claude/**)",
  ...secretPathRules(),
];

// Permission rules: reading and writing inside the job folder only (the agent's cwd; "./" keeps
// the rule free of the space in "Application Support"), Bash only for our two scripts, Agent only
// for test-guardian. Grep and Glob follow the Read rules. Each Bash rule is the prompt's command
// followed by ":*", so the command as the prompt gives it matches.
export function agentAllowedTools({ intelToolPath = INTEL_TOOL_PATH, checkToolPath = CHECK_TOOL_PATH } = {}) {
  return [
    "Read(./**)",
    "Edit(./**)",
    "Grep",
    "Glob",
    `Bash(node ${intelToolPath}:*)`,
    `Bash(node ${checkToolPath}:*)`,
    `Agent(${GUARDIAN_AGENT})`,
  ];
}

// A permission rule for an absolute path pattern: Claude Code writes those with a leading "//".
function absolutePathRule(toolName, absolutePattern) {
  return `${toolName}(/${absolutePattern})`;
}

// The job's own deny rules (founder, 2026-10-22: the agents must not touch the sandbox), from
// run-job.mjs: noEditPaths (the checkout with the runner's code, the tool link) can be read but
// never edited; noReadPaths (the logs, other jobs' and this one's baseline and prompt; the
// sandbox checkout and its profile) can be neither read nor edited.
export function jobPathRules({ noEditPaths = [], noReadPaths = [] }) {
  const rules = [];
  for (const pattern of noEditPaths) {
    rules.push(absolutePathRule("Edit", pattern));
  }
  for (const pattern of noReadPaths) {
    rules.push(absolutePathRule("Read", pattern));
    rules.push(absolutePathRule("Edit", pattern));
  }
  return rules;
}

export const REPAIR_USER_MESSAGE = [
  "Repair this Sidekick from the report in report/. Follow the system prompt exactly.",
  "Start by deciding whether the request is something the shell supports. End by writing outcome.json.",
].join(" ");

// The claude command line for one job. The prompt file is the assembled system prompt; the
// user message is short and points at the report. check-sandbox.mjs passes its own message.
// effort, when given, is passed as --effort (speed trial, runner/lib/speed-trial.mjs); null keeps
// the CLI's default.
export function buildClaudeArgs({ systemPromptPath, model, maxTurns, effort = null, intelToolPath, checkToolPath, noEditPaths = [], noReadPaths = [], userMessage = REPAIR_USER_MESSAGE }) {
  const allowed = agentAllowedTools({ intelToolPath, checkToolPath });
  const denied = [...AGENT_DENIED_TOOLS, ...jobPathRules({ noEditPaths, noReadPaths })];
  const effortArgs = effort === null ? [] : ["--effort", effort];
  return [
    ...effortArgs,
    "-p",
    userMessage,
    "--model",
    model,
    "--max-turns",
    String(maxTurns),
    "--permission-mode",
    "dontAsk",
    "--permission-prompts",
    "none",
    "--tools",
    AGENT_TOOLS.join(","),
    "--allowedTools",
    ...allowed,
    "--disallowedTools",
    ...denied,
    "--strict-mcp-config",
    "--disable-slash-commands",
    "--no-session-persistence",
    "--setting-sources",
    "project",
    "--append-system-prompt-file",
    systemPromptPath,
    "--output-format",
    "stream-json",
    "--verbose",
  ];
}

function openAppendStream(logPath) {
  return createWriteStream(logPath, { flags: "a" });
}

// Spawns the agent in the job folder and streams its stdout (stream-json, one event per line)
// to a log file. Resolves with { exitCode, timedOut, signal } once the log is written. Kills the
// agent at timeoutMs.
export function runAgent({ command, args, jobFolder, logPath, environment, timeoutMs, spawnImplementation = spawn, openLogStream = openAppendStream }) {
  return new Promise((resolve, reject) => {
    const logStream = openLogStream(logPath);
    const child = spawnImplementation(command, args, { cwd: jobFolder, env: environment, stdio: ["ignore", "pipe", "pipe"] });
    let timedOut = false;
    let settled = false;

    const timer = setTimeout(function stopAgentOnTimeout() {
      timedOut = true;
      child.kill("SIGTERM");
      // A second chance to die, then SIGKILL.
      setTimeout(function forceKill() {
        if (!settled) {
          child.kill("SIGKILL");
        }
      }, 10_000).unref();
    }, timeoutMs);

    child.stdout.on("data", function writeStdoutToLog(chunk) {
      logStream.write(chunk);
    });
    child.stderr.on("data", function writeStderrToLog(chunk) {
      logStream.write(chunk);
    });
    child.on("error", function failOnSpawnError(error) {
      clearTimeout(timer);
      settled = true;
      logStream.end();
      reject(error);
    });
    // Resolves once the log is flushed to disk, so a caller that reads it next sees all of it
    // (an unflushed log cut off a tool result in a check-sandbox test, 2026-10-22).
    child.on("close", function finish(exitCode, signal) {
      clearTimeout(timer);
      settled = true;
      logStream.end(function resolveAfterLogFlushed() {
        resolve({ exitCode, timedOut, signal });
      });
    });
  });
}

// The environment the agent runs with, from an allow-list (safe-env.mjs claudeEnvironment): the
// founder's PATH (claude, node), the runner's own Claude config dir and Claude login, and the job
// folder for our two tools. Nothing else from ~/.midas-runner/env, never MIDAS_RUNNER_TOKEN; an
// API key only when the founder opted in with MIDAS_RUNNER_USE_API_KEY=1.
// The shield's inputs for the agent's check tool (repair lanes W1): the copy as the job started and
// the person's records, both in the log folder, set only when given and removed otherwise.
function setOrDelete(environment, name, value) {
  if (value !== null && value !== undefined) {
    environment[name] = value;
  } else {
    delete environment[name];
  }
}

export function agentEnvironment({ baseEnvironment, claudeConfigDir, jobFolder, checkoutRoot, sidekickId, manifestBeforePath = null, beforeFolder = null, recordsPath = null }) {
  const environment = claudeEnvironment(baseEnvironment);
  environment.CLAUDE_CONFIG_DIR = claudeConfigDir;
  environment.MIDAS_JOB_FOLDER = jobFolder;
  environment.MIDAS_RUNNER_CHECKOUT = checkoutRoot;
  environment.MIDAS_JOB_SIDEKICK_ID = sidekickId;
  // The copy's manifest as the job started (outside the job folder), so the check tool can tell
  // the agent about a schema change the runner would refuse before it finishes.
  if (manifestBeforePath !== null) {
    environment.MIDAS_JOB_MANIFEST_BEFORE = manifestBeforePath;
  } else {
    delete environment.MIDAS_JOB_MANIFEST_BEFORE;
  }
  setOrDelete(environment, "MIDAS_JOB_BEFORE_FOLDER", beforeFolder);
  setOrDelete(environment, "MIDAS_JOB_RECORDS", recordsPath);
  return environment;
}
