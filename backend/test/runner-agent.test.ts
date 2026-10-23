// How the runner starts Claude Code: fixed tool allowlist, no web, no prompts, turn cap, its own
// config dir, and a kill at the time cap (docs/briefs/repair-runner.md, step 2).
import { mkdtempSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { AGENT_DENIED_TOOLS, agentAllowedTools, agentEnvironment, buildClaudeArgs, runAgent } from "../../runner/lib/agent.mjs";

function flagValue(args: string[], flag: string): string {
  const index = args.indexOf(flag);
  expect(index).toBeGreaterThan(-1);
  return args[index + 1];
}

// Everything after a list flag until the next "--" flag.
function flagList(args: string[], flag: string): string[] {
  const index = args.indexOf(flag);
  expect(index).toBeGreaterThan(-1);
  const values: string[] = [];
  for (let position = index + 1; position < args.length && !args[position].startsWith("--"); position += 1) {
    values.push(args[position]);
  }
  return values;
}

describe("buildClaudeArgs", () => {
  const args = buildClaudeArgs({ systemPromptPath: "/tmp/prompt.md", model: "opus", maxTurns: 50, intelToolPath: "/r/tools/intel.mjs", checkToolPath: "/r/tools/check.mjs" });

  it("runs headless with no permission prompts and the turn cap", () => {
    expect(args[0]).toBe("-p");
    expect(flagValue(args, "--permission-mode")).toBe("dontAsk");
    expect(flagValue(args, "--permission-prompts")).toBe("none");
    expect(flagValue(args, "--max-turns")).toBe("50");
    expect(flagValue(args, "--model")).toBe("opus");
    expect(flagValue(args, "--output-format")).toBe("stream-json");
    expect(flagValue(args, "--append-system-prompt-file")).toBe("/tmp/prompt.md");
  });

  it("allows file tools and Bash for exactly the intel and check scripts", () => {
    const allowed = flagList(args, "--allowedTools");
    // File tools only inside the job folder (founder, 2026-10-22, docs/briefs/repair-data-2026-10-19.md).
    expect(allowed).toEqual(["Read(./**)", "Edit(./**)", "Grep", "Glob", "Bash(node /r/tools/intel.mjs:*)", "Bash(node /r/tools/check.mjs:*)", "Agent(test-guardian)"]);
    expect(allowed).not.toContain("Read");
    expect(allowed).not.toContain("Edit");
    expect(allowed).not.toContain("Write");
    const bashRules = allowed.filter((rule) => rule.startsWith("Bash"));
    expect(bashRules).toHaveLength(2);
    expect(allowed.some((rule) => rule === "Bash" || rule === "Bash(*)")).toBe(false);
    // Only the test-guardian subagent (contract, 2026-10-13, "Tests move every copy forward").
    expect(allowed).toContain("Agent(test-guardian)");
    expect(allowed.some((rule) => rule === "Agent" || rule === "Agent(*)")).toBe(false);
  });

  it("denies web and every built-in subagent, and loads no MCP servers, skills or user settings", () => {
    const denied = flagList(args, "--disallowedTools");
    expect(denied).toContain("WebFetch");
    expect(denied).toContain("WebSearch");
    expect(denied).toContain("Agent(Explore)");
    expect(denied).toContain("Agent(Plan)");
    expect(denied).toContain("Agent(general-purpose)");
    expect(denied).not.toContain("Agent(test-guardian)");
    expect(denied).toEqual(AGENT_DENIED_TOOLS);
    expect(args).toContain("--strict-mcp-config");
    expect(args).toContain("--disable-slash-commands");
    expect(flagValue(args, "--setting-sources")).toBe("project");
    expect(args).not.toContain("--bare");
    expect(args).not.toContain("--add-dir");
  });

  it("the default allowlist points at the runner's own tool scripts", () => {
    const allowed = agentAllowedTools();
    expect(allowed.some((rule) => rule.includes("/runner/tools/intel.mjs:*"))).toBe(true);
    expect(allowed.some((rule) => rule.includes("/runner/tools/check.mjs:*"))).toBe(true);
  });
});

describe("agentEnvironment", () => {
  it("gives the agent its own Claude config dir, the job folder, and strips a stray API key", () => {
    const environment = agentEnvironment({
      baseEnvironment: { PATH: "/usr/bin", ANTHROPIC_API_KEY: "sk-leak", HOME: "/Users/f" },
      claudeConfigDir: "/Users/f/.midas-runner/claude",
      jobFolder: "/jobs/r1",
      checkoutRoot: "/checkout",
      sidekickId: "reminders",
    });
    expect(environment.CLAUDE_CONFIG_DIR).toBe("/Users/f/.midas-runner/claude");
    expect(environment.MIDAS_JOB_FOLDER).toBe("/jobs/r1");
    expect(environment.MIDAS_RUNNER_CHECKOUT).toBe("/checkout");
    expect(environment.MIDAS_JOB_SIDEKICK_ID).toBe("reminders");
    expect(environment.ANTHROPIC_API_KEY).toBeUndefined();
    expect(environment.PATH).toBe("/usr/bin");
  });

  it("keeps the API key only when the founder opted in", () => {
    const environment = agentEnvironment({
      baseEnvironment: { ANTHROPIC_API_KEY: "sk-chosen", MIDAS_RUNNER_USE_API_KEY: "1" },
      claudeConfigDir: "/c",
      jobFolder: "/j",
      checkoutRoot: "/k",
      sidekickId: "reminders",
    });
    expect(environment.ANTHROPIC_API_KEY).toBe("sk-chosen");
  });
});

describe("runAgent", () => {
  it("runs the command in the job folder and keeps its output in the log", async () => {
    const scratch = mkdtempSync(join(tmpdir(), "runner-agent-"));
    const script = join(scratch, "agent.mjs");
    writeFileSync(script, 'console.log(JSON.stringify({ type: "hello", cwd: process.cwd() }));');
    const logPath = join(scratch, "stream.jsonl");
    const result = await runAgent({ command: process.execPath, args: [script], jobFolder: scratch, logPath, environment: process.env, timeoutMs: 10_000 });
    expect(result.exitCode).toBe(0);
    expect(result.timedOut).toBe(false);
    const logged = JSON.parse(readFileSync(logPath, "utf8").trim());
    // Real paths: on macOS tmpdir() is /var/... while the child reports /private/var/...
    expect(realpathSync(logged.cwd)).toBe(realpathSync(scratch));
  });

  it("kills the agent at the time cap and reports timedOut", async () => {
    const scratch = mkdtempSync(join(tmpdir(), "runner-agent-"));
    const script = join(scratch, "slow.mjs");
    writeFileSync(script, "setTimeout(() => {}, 60000);");
    const logPath = join(scratch, "stream.jsonl");
    const started = Date.now();
    const result = await runAgent({ command: process.execPath, args: [script], jobFolder: scratch, logPath, environment: process.env, timeoutMs: 300 });
    expect(result.timedOut).toBe(true);
    expect(result.exitCode).not.toBe(0);
    expect(Date.now() - started).toBeLessThan(10_000);
  });
});
