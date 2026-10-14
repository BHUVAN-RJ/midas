// Runs Claude Code headless on a job folder. The agent gets a fixed, small set of tools: file
// tools inside the job folder, Bash for exactly two commands of ours (intel, check), and one
// subagent, test-guardian (the only way an existing test changes; founder, 2026-10-13). No web,
// no other subagents, no MCP servers, no slash commands, no settings from the founder's own
// ~/.claude (the runner has its own CLAUDE_CONFIG_DIR); project settings come from the job
// folder's .claude/, which the runner writes (the test guard hook and the guardian).
import { spawn } from "node:child_process";
import { createWriteStream } from "node:fs";
import { join } from "node:path";
import { REPO_ROOT } from "./config.mjs";

export const INTEL_TOOL_PATH = join(REPO_ROOT, "runner", "tools", "intel.mjs");
export const CHECK_TOOL_PATH = join(REPO_ROOT, "runner", "tools", "check.mjs");

export const GUARDIAN_AGENT = "test-guardian";
export const AGENT_TOOLS = ["Read", "Edit", "Write", "Grep", "Glob", "Bash", "Agent"];
// Every built-in subagent by name; the Agent tool itself stays available for the guardian only.
export const AGENT_DENIED_TOOLS = ["WebFetch", "WebSearch", "Agent(Explore)", "Agent(Plan)", "Agent(general-purpose)", "Task", "NotebookEdit", "TodoWrite"];

// Permission rules: file tools without restriction (the agent's cwd is the job folder and it has
// no --add-dir), Bash only for our two scripts, Agent only for test-guardian.
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

// The environment the agent runs with: the founder's PATH (claude, node), the runner's own
// Claude config dir (its token, no plugins), and the job folder for our two tools.
export function agentEnvironment({ baseEnvironment, claudeConfigDir, jobFolder, checkoutRoot, sidekickId }) {
  const environment = { ...baseEnvironment };
  environment.CLAUDE_CONFIG_DIR = claudeConfigDir;
  environment.MIDAS_JOB_FOLDER = jobFolder;
  environment.MIDAS_RUNNER_CHECKOUT = checkoutRoot;
  environment.MIDAS_JOB_SIDEKICK_ID = sidekickId;
  // Never let an API key in the founder's shell win over the subscription by accident. The
  // founder opts in to an API key with MIDAS_RUNNER_USE_API_KEY=1 (one line in the env file).
  if (environment.MIDAS_RUNNER_USE_API_KEY !== "1") {
    delete environment.ANTHROPIC_API_KEY;
  }
  return environment;
}
