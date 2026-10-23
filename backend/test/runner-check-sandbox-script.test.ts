// The founder's first `node runner/bin/check-sandbox.mjs --agent` on the Mac mini (2026-10-22)
// stopped at "MIDAS_BACKEND_URL is not set": the agent check read the full runner settings,
// though running claude needs no backend. It must run with only the Claude settings.
import { execFile } from "node:child_process";
import { chmodSync, realpathSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { agentSettingsFromEnv, settingsFromEnv } from "../../runner/lib/config.mjs";
import { REPO_ROOT, makeScratch } from "./helpers/runner-fixture";

function runScript(args: string[], environment: Record<string, string>): Promise<{ code: number; output: string }> {
  return new Promise((resolve) => {
    execFile(process.execPath, [join(REPO_ROOT, "runner", "bin", "check-sandbox.mjs"), ...args], { env: environment, encoding: "utf8", timeout: 120_000 }, function finish(error, stdout, stderr) {
      const code = error === null ? 0 : (typeof error.code === "number" ? error.code : 1);
      resolve({ code, output: `${stdout}\n${stderr}` });
    });
  });
}

describe("check-sandbox --agent needs no backend settings", () => {
  it("agent settings come without MIDAS_BACKEND_URL or MIDAS_RUNNER_TOKEN, matching the runner's", () => {
    const environment = { MIDAS_CLAUDE_COMMAND: "/opt/claude", CLAUDE_CONFIG_DIR: "/c", MIDAS_RUNNER_MODEL: "sonnet", MIDAS_RUNNER_CHECKOUT: "/checkout" };
    const agentSettings = agentSettingsFromEnv(environment);
    expect(agentSettings).toEqual({ claudeCommand: "/opt/claude", claudeConfigDir: "/c", model: "sonnet", checkoutRoot: "/checkout" });
    const full = settingsFromEnv({ ...environment, MIDAS_BACKEND_URL: "https://midas-api-staging.midas-backend.workers.dev", MIDAS_RUNNER_TOKEN: "t" });
    expect(full).toMatchObject(agentSettings);
  });

  it("runs the agent check on an env file with only the Claude login", async () => {
    const { scratch } = makeScratch();
    const home = realpathSync(scratch);
    // A stand-in for claude that does the allowed step only (it runs in the job folder).
    const fakeClaude = join(home, "fake-claude");
    writeFileSync(fakeClaude, "#!/bin/sh\ncp inside.txt copied.txt\nexit 0\n");
    chmodSync(fakeClaude, 0o755);
    const { code, output } = await runScript(["--agent"], { PATH: process.env.PATH ?? "/usr/bin:/bin", HOME: home, MIDAS_CLAUDE_COMMAND: fakeClaude, CLAUDE_CODE_OAUTH_TOKEN: "fake" });
    expect(output).not.toContain("is not set");
    expect(output).toContain("✓ claude ran (exit 0)");
    expect(output).toContain("✓ agent can still read and write inside the job folder");
    expect(output).toContain("✓ agent never saw ~/.midas-runner/agent-canary");
    expect(code).toBe(0);
  }, 120_000);
});
