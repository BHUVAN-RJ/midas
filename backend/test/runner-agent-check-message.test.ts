// check-sandbox.mjs --agent must send its own plain message, not the repair one: on the
// founder's run (2026-10-22) the repair message with attack-worded steps was flagged by the
// API's safety filter and the model declined every step.
import { execFile } from "node:child_process";
import { chmodSync, realpathSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { REPAIR_USER_MESSAGE } from "../../runner/lib/agent.mjs";
import { REPO_ROOT, makeScratch } from "./helpers/runner-fixture";

// A stand-in claude that writes the message it was given (-p) to report.txt, which the script
// prints back.
const MESSAGE_RECORDER = `
const { writeFileSync } = require("node:fs");
const args = process.argv.slice(2);
writeFileSync("report.txt", "message: " + args[args.indexOf("-p") + 1] + "\\n");
`;

describe("check-sandbox --agent message", () => {
  it("sends the plain check message, never the repair message", async () => {
    const { scratch } = makeScratch();
    const home = realpathSync(scratch);
    const sourcePath = join(home, "record-message.cjs");
    writeFileSync(sourcePath, MESSAGE_RECORDER);
    const fakeClaude = join(home, "fake-claude");
    writeFileSync(fakeClaude, `#!/bin/sh\nexec "${process.execPath}" "${sourcePath}" "$@"\n`);
    chmodSync(fakeClaude, 0o755);
    const environment = { PATH: process.env.PATH ?? "/usr/bin:/bin", HOME: home, MIDAS_CLAUDE_COMMAND: fakeClaude, CLAUDE_CODE_OAUTH_TOKEN: "fake" };
    const output: string = await new Promise((resolve) => {
      execFile(process.execPath, [join(REPO_ROOT, "runner", "bin", "check-sandbox.mjs"), "--agent"], { env: environment, encoding: "utf8", timeout: 120_000 }, function finish(_error, stdout, stderr) {
        resolve(`${stdout}\n${stderr}`);
      });
    });
    expect(output).toContain("message: The owner of this Mac is checking which files your tools may open.");
    expect(output).not.toContain(REPAIR_USER_MESSAGE);
  }, 120_000);
});
