// A stand-in for `claude -p` for check-sandbox.mjs --agent. Like real claude, it first prints the
// stream's init event: the tools from --tools, with Agent listed as "Task" and left out when
// --disallowedTools denies "Task" or "Agent" (repairs 50ca5522 and 9c699df4, 2026-10-24), and the
// subagents claude, Explore, general-purpose, Plan, statusline-setup and test-guardian. It always
// copies inside.txt to copied.txt (the allowed step), then, by mode:
//   "refused"   logs a refused Read, Grep, Bash, Write and Edit call on every absolute path in the
//               system prompt, as claude's stream-json does; and, when the Agent tool is listed,
//               Agent calls to test-guardian, Explore and claude, each refused when
//               --disallowedTools has Agent(<name>) (founder, 2026-10-25: only the guardian goes through)
//   "declined"  makes no other call (the founder's run, 2026-10-22: the model declined the steps)
//   "allowed"   logs the same calls, Agent calls included, as going through
import { chmodSync, writeFileSync } from "node:fs";
import { join } from "node:path";

export type FakeClaudeMode = "refused" | "declined" | "allowed";

const FAKE_CLAUDE_SOURCE = `
const { copyFileSync, readFileSync } = require("node:fs");
const MODE = process.argv[2];
const args = process.argv.slice(3);

// The values after a flag, up to the next flag.
function flagValues(flagName) {
  const start = args.indexOf(flagName);
  if (start === -1) {
    return [];
  }
  const values = [];
  for (const value of args.slice(start + 1)) {
    if (value.startsWith("--")) {
      break;
    }
    values.push(value);
  }
  return values;
}

const deniedTools = flagValues("--disallowedTools");
const requestedTools = (flagValues("--tools")[0] || "").split(",");
const agentToolDenied = deniedTools.includes("Task") || deniedTools.includes("Agent");
const initTools = [];
for (const toolName of requestedTools) {
  // Claude Code lists the Agent tool as "Task"; a "Task" or "Agent" denial removes it.
  if (toolName === "Agent") {
    if (!agentToolDenied) {
      initTools.push("Task");
    }
    continue;
  }
  initTools.push(toolName);
}
const initAgents = ["claude", "Explore", "general-purpose", "Plan", "statusline-setup", "test-guardian"];
console.log(JSON.stringify({ type: "system", subtype: "init", tools: initTools, agents: initAgents }));

copyFileSync("inside.txt", "copied.txt");
let agentCallNumber = 0;
if (MODE !== "declined" && initTools.includes("Task")) {
  for (const subagentType of ["test-guardian", "Explore", "claude"]) {
    agentCallNumber += 1;
    const id = "toolu_agent_" + agentCallNumber;
    const input = { subagent_type: subagentType, description: "check", prompt: "Reply ok." };
    const use = { type: "assistant", message: { content: [{ type: "tool_use", id, name: "Task", input }] } };
    const refused = MODE === "refused" && deniedTools.includes("Agent(" + subagentType + ")");
    const result = { type: "tool_result", tool_use_id: id, is_error: refused, content: refused ? "Permission to use Agent has been denied." : "ok" };
    console.log(JSON.stringify(use));
    console.log(JSON.stringify({ type: "user", message: { content: [result] } }));
  }
}
if (MODE !== "declined") {
  const promptPath = args[args.indexOf("--append-system-prompt-file") + 1];
  const prompt = readFileSync(promptPath, "utf8");
  const paths = prompt.match(/\\/[\\w.\\-\\/]*\\w/g) || [];
  let callNumber = 0;
  for (const targetPath of paths) {
    for (const name of ["Read", "Grep", "Bash", "Write", "Edit"]) {
      callNumber += 1;
      const id = "toolu_" + callNumber;
      const input = { file_path: targetPath, path: targetPath, command: "cat " + targetPath };
      const use = { type: "assistant", message: { content: [{ type: "tool_use", id, name, input }] } };
      const refused = MODE === "refused";
      const result = { type: "tool_result", tool_use_id: id, is_error: refused, content: refused ? "Permission to use " + name + " has been denied." : "ok" };
      console.log(JSON.stringify(use));
      console.log(JSON.stringify({ type: "user", message: { content: [result] } }));
    }
  }
}
process.exit(0);
`;

// Writes the fake to <folder>/fake-claude-<mode> and returns its path. It is a shell script that
// runs the node in use now, so it works whatever PATH the agent gets.
export function writeFakeClaude(folder: string, mode: FakeClaudeMode): string {
  const sourcePath = join(folder, `fake-claude-${mode}.cjs`);
  writeFileSync(sourcePath, FAKE_CLAUDE_SOURCE);
  const scriptPath = join(folder, `fake-claude-${mode}`);
  writeFileSync(scriptPath, `#!/bin/sh\nexec "${process.execPath}" "${sourcePath}" ${mode} "$@"\n`);
  chmodSync(scriptPath, 0o755);
  return scriptPath;
}
