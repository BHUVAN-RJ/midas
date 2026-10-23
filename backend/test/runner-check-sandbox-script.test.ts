// The founder's first `node runner/bin/check-sandbox.mjs --agent` on the Mac mini (2026-10-22)
// stopped at "MIDAS_BACKEND_URL is not set": the agent check read the full runner settings,
// though running claude needs no backend. It must run with only the Claude settings.
import { execFile } from "node:child_process";
import { realpathSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { agentSettingsFromEnv, settingsFromEnv } from "../../runner/lib/config.mjs";
import { writeFakeClaude } from "./helpers/fake-claude";
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
    // A stand-in for claude that copies inside.txt and logs every probe as tried and refused.
    const fakeClaude = writeFakeClaude(home, "refused");
    const { code, output } = await runScript(["--agent"], { PATH: process.env.PATH ?? "/usr/bin:/bin", HOME: home, MIDAS_CLAUDE_COMMAND: fakeClaude, CLAUDE_CODE_OAUTH_TOKEN: "fake" });
    expect(output).not.toContain("is not set");
    expect(output).toContain("✓ claude ran (exit 0)");
    expect(output).toContain("✓ agent can still read and write inside the job folder");
    expect(output).toContain("✓ agent never saw the note in ~/.midas-runner");
    expect(code).toBe(0);
  }, 120_000);
});
