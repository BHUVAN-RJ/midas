// Runs Claude Code headless on a job folder. The agent gets a fixed, small set of tools: file
// tools inside the job folder, Bash for exactly two commands of ours (intel, check), and one
// subagent, test-guardian (the only way an existing test changes; founder, 2026-10-13). No web,
// no other subagents, no MCP servers, no slash commands, no settings from the founder's own
// ~/.claude (the runner has its own CLAUDE_CONFIG_DIR); project settings come from the job
// folder's .claude/, which the runner writes (the test guard hook and the guardian).
import { spawn } from "node:child_process";
import { createWriteStream, lstatSync, mkdirSync, readlinkSync, rmSync, symlinkSync } from "node:fs";
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
// returns the two tool paths through it. Throws when linkRoot is not a plain path.
export function linkAgentTools({ linkRoot, toolsFolder = TOOLS_FOLDER }) {
  if (typeof linkRoot !== "string" || !isPlainPath(linkRoot)) {
    throw new Error(`the tool link folder "${linkRoot}" must be a path without spaces or shell characters; set MIDAS_RUNNER_TOOL_LINKS`);
  }
  mkdirSync(linkRoot, { recursive: true });
  const linkPath = join(linkRoot, TOOL_LINK_NAME);
  let existingTarget = null;
  try {
    existingTarget = lstatSync(linkPath).isSymbolicLink() ? readlinkSync(linkPath) : "";
  } catch {
    existingTarget = null;
  }
  if (existingTarget !== toolsFolder) {
    rmSync(linkPath, { recursive: true, force: true });
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
// Every built-in subagent by name; the Agent tool itself stays available for the guardian only.
export const AGENT_DENIED_TOOLS = ["WebFetch", "WebSearch", "Agent(Explore)", "Agent(Plan)", "Agent(general-purpose)", "Task", "NotebookEdit", "TodoWrite"];

// Permission rules: file tools without restriction (the agent's cwd is the job folder and it has
// no --add-dir), Bash only for our two scripts, Agent only for test-guardian. Each Bash rule is
// the prompt's command followed by ":*", so the command as the prompt gives it matches.
export function agentAllowedTools({ intelToolPath = INTEL_TOOL_PATH, checkToolPath = CHECK_TOOL_PATH } = {}) {
  return [
    "Read",
    "Edit",
    "Write",
    "Grep",
    "Glob",
    `Bash(node ${intelToolPath}:*)`,
    `Bash(node ${checkToolPath}:*)`,
    `Agent(${GUARDIAN_AGENT})`,
  ];
}

// The claude command line for one job. The prompt file is the assembled system prompt; the
// user message is short and points at the report.
export function buildClaudeArgs({ systemPromptPath, model, maxTurns, intelToolPath, checkToolPath }) {
  const allowed = agentAllowedTools({ intelToolPath, checkToolPath });
  const userMessage = [
    "Repair this Sidekick from the report in report/. Follow the system prompt exactly.",
    "Start by deciding whether the request is something the shell supports. End by writing outcome.json.",
  ].join(" ");
  return [
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
    ...AGENT_DENIED_TOOLS,
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

// Spawns the agent in the job folder and streams its stdout (stream-json, one event per line)
// to a log file. Resolves with { exitCode, timedOut, signal }. Kills the agent at timeoutMs.
export function runAgent({ command, args, jobFolder, logPath, environment, timeoutMs, spawnImplementation = spawn }) {
  return new Promise((resolve, reject) => {
    const logStream = createWriteStream(logPath, { flags: "a" });
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
    child.on("close", function finish(exitCode, signal) {
      clearTimeout(timer);
      settled = true;
      logStream.end();
      resolve({ exitCode, timedOut, signal });
    });
  });
}

// The environment the agent runs with, from an allow-list (safe-env.mjs claudeEnvironment): the
// founder's PATH (claude, node), the runner's own Claude config dir and Claude login, and the job
// folder for our two tools. Nothing else from ~/.midas-runner/env, never MIDAS_RUNNER_TOKEN; an
// API key only when the founder opted in with MIDAS_RUNNER_USE_API_KEY=1.
export function agentEnvironment({ baseEnvironment, claudeConfigDir, jobFolder, checkoutRoot, sidekickId, manifestBeforePath = null }) {
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
  return environment;
}
