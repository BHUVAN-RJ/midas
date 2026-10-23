// A stand-in for `claude -p` for check-sandbox.mjs --agent. It always copies inside.txt to
// copied.txt (the allowed step), then, by mode:
//   "refused"   logs a refused Read, Grep, Bash, Write and Edit call on every absolute path in the
//               system prompt, as claude's stream-json does
//   "declined"  makes no other call (the founder's run, 2026-10-22: the model declined the steps)
//   "allowed"   logs the same calls as going through
import { chmodSync, writeFileSync } from "node:fs";
import { join } from "node:path";

export type FakeClaudeMode = "refused" | "declined" | "allowed";

const FAKE_CLAUDE_SOURCE = `
const { copyFileSync, readFileSync } = require("node:fs");
const MODE = process.argv[2];
const args = process.argv.slice(3);
copyFileSync("inside.txt", "copied.txt");
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
