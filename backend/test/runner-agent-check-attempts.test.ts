// The founder's `check-sandbox.mjs --agent` run (2026-10-22): the API's safety filter flagged the
// attack-worded steps, the model was swapped and it declined every step, yet the file checks
// showed ✓. A check now passes only when the agent tried the call and it was refused.
import { execFile } from "node:child_process";
import { realpathSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { REPAIR_USER_MESSAGE, buildClaudeArgs } from "../../runner/lib/agent.mjs";
import { modelWasSwapped, probeVerdict, toolCallsFromLog } from "../../runner/lib/agent-check.mjs";
import { writeFakeClaude, type FakeClaudeMode } from "./helpers/fake-claude";
import { REPO_ROOT, makeScratch } from "./helpers/runner-fixture";

function streamLine(event: unknown): string {
  return JSON.stringify(event);
}

function toolUse(id: string, name: string, input: Record<string, unknown>): string {
  return streamLine({ type: "assistant", message: { content: [{ type: "tool_use", id, name, input }] } });
}

function toolResult(id: string, isError: boolean, content: string): string {
  return streamLine({ type: "user", message: { content: [{ type: "tool_result", tool_use_id: id, is_error: isError, content }] } });
}

function runAgentCheck(mode: FakeClaudeMode): Promise<{ code: number; output: string }> {
  const { scratch } = makeScratch();
  const home = realpathSync(scratch);
  const fakeClaude = writeFakeClaude(home, mode);
  const environment = { PATH: process.env.PATH ?? "/usr/bin:/bin", HOME: home, MIDAS_CLAUDE_COMMAND: fakeClaude, CLAUDE_CODE_OAUTH_TOKEN: "fake" };
  return new Promise((resolve) => {
    execFile(process.execPath, [join(REPO_ROOT, "runner", "bin", "check-sandbox.mjs"), "--agent"], { env: environment, encoding: "utf8", timeout: 120_000 }, function finish(error, stdout, stderr) {
      const code = error === null ? 0 : (typeof error.code === "number" ? error.code : 1);
      resolve({ code, output: `${stdout}\n${stderr}` });
    });
  });
}

describe("reading the agent's tool calls from its log", () => {
  it("pairs each call with its result, skipping lines that are not JSON", () => {
    const log = [
      "not json",
      toolUse("a", "Read", { file_path: "/h/.midas-runner/note.txt" }),
      toolResult("a", true, "Permission denied"),
      toolUse("b", "Write", { file_path: "/job/copied.txt" }),
      toolResult("b", false, "File created"),
      toolUse("c", "Bash", { command: "cat /h/.midas-runner/note.txt" }),
    ].join("\n");
    const calls = toolCallsFromLog(log);
    expect(calls).toEqual([
      { name: "Read", input: { file_path: "/h/.midas-runner/note.txt" }, isError: true, resultText: "Permission denied" },
      { name: "Write", input: { file_path: "/job/copied.txt" }, isError: false, resultText: "File created" },
      { name: "Bash", input: { command: "cat /h/.midas-runner/note.txt" }, isError: null, resultText: "" },
    ]);
  });

  it("a probe is refused only when tried and every try failed; untried proves nothing", () => {
    const target = "/h/.midas-runner/note.txt";
    const refusedTwice = toolCallsFromLog([toolUse("a", "Read", { file_path: target }), toolResult("a", true, "denied"), toolUse("b", "Read", { file_path: target }), toolResult("b", true, "denied")].join("\n"));
    expect(probeVerdict({ calls: refusedTwice, toolNames: ["Read"], targetPath: target })).toBe("refused");
    const secondWentThrough = toolCallsFromLog([toolUse("a", "Read", { file_path: target }), toolResult("a", true, "denied"), toolUse("b", "Read", { file_path: target }), toolResult("b", false, "note-1")].join("\n"));
    expect(probeVerdict({ calls: secondWentThrough, toolNames: ["Read"], targetPath: target })).toBe("allowed");
    const noResult = toolCallsFromLog(toolUse("a", "Read", { file_path: target }));
    expect(probeVerdict({ calls: noResult, toolNames: ["Read"], targetPath: target })).toBe("allowed");
    expect(probeVerdict({ calls: refusedTwice, toolNames: ["Grep"], targetPath: target })).toBe("not tried");
    expect(probeVerdict({ calls: refusedTwice, toolNames: ["Read"], targetPath: "/elsewhere" })).toBe("not tried");
  });

  it("sees the API swapping the model after its safety filter", () => {
    const swapped = streamLine({ type: "system", subtype: "model_refusal_fallback", original_model: "claude-opus-5-5" });
    expect(modelWasSwapped(`${swapped}\n`)).toBe(true);
    expect(modelWasSwapped(toolUse("a", "Read", { file_path: "/x" }))).toBe(false);
  });
});

describe("the check's own message", () => {
  it("a job keeps the repair message; check-sandbox passes its own", () => {
    const jobArgs = buildClaudeArgs({ systemPromptPath: "/p.md", model: "opus", maxTurns: 5 });
    expect(jobArgs[jobArgs.indexOf("-p") + 1]).toBe(REPAIR_USER_MESSAGE);
    const checkArgs = buildClaudeArgs({ systemPromptPath: "/p.md", model: "opus", maxTurns: 5, userMessage: "check" });
    expect(checkArgs[checkArgs.indexOf("-p") + 1]).toBe("check");
  });
});

describe("check-sandbox --agent end to end with a stand-in claude", () => {
  it("every probe tried and refused: all ✓, exit 0", async () => {
    const { code, output } = await runAgentCheck("refused");
    expect(output).toContain("✓ Read of ~/.midas-runner refused");
    expect(output).toContain("✓ Grep in ~/.midas-runner refused");
    expect(output).toContain("✓ Bash cat of ~/.midas-runner refused");
    expect(output).toContain("✓ Write in ~/.midas-runner refused");
    expect(output).toContain("✓ Edit of the runner's code (sandbox.mjs stand-in) refused");
    expect(output).toContain("✓ Write of the sandbox profile refused");
    expect(output).not.toContain("✕");
    expect(code).toBe(0);
  }, 120_000);

  it("the agent declines the steps: each probe ✕ as proving nothing, exit 1", async () => {
    const { code, output } = await runAgentCheck("declined");
    expect(output).toContain("✓ agent can still read and write inside the job folder");
    expect(output).toContain("✕ Read of ~/.midas-runner refused: the agent did not try, so this proves nothing");
    expect(output).toContain("✕ Write of the sandbox profile refused: the agent did not try, so this proves nothing");
    expect(code).toBe(1);
  }, 120_000);

  it("the calls go through: ✕, exit 1", async () => {
    const { code, output } = await runAgentCheck("allowed");
    expect(output).toContain("✕ Read of ~/.midas-runner refused: the call went through");
    expect(output).toContain("✕ Bash cat of ~/.midas-runner refused: the call went through");
    expect(code).toBe(1);
  }, 120_000);
});
