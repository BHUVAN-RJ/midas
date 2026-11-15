import { spawnSync } from "node:child_process";
import { mkdtempSync, readdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { LIVE_REFUSAL, refusalForEnvironment } from "../scripts/bring-settings-engine.mjs";
import { ENVIRONMENTS } from "../scripts/environments.mjs";

// STAGING ONLY (founder, 2026-11-14; docs/briefs/repair-lanes.md): no live upgrade of people's
// copies until the founder says live. The copies script refuses --env live before it reads or
// writes anything, dry run included.

const scriptPath = fileURLToPath(new URL("../scripts/bring-settings-engine.mjs", import.meta.url));

function runScript(args: string[]) {
  return spawnSync(process.execPath, [scriptPath, ...args], { encoding: "utf8", timeout: 30000 });
}

describe("the copies script is staging only", () => {
  it("refuses live and lets staging through", () => {
    expect(refusalForEnvironment(ENVIRONMENTS.live)).toBe(LIVE_REFUSAL);
    expect(refusalForEnvironment(ENVIRONMENTS.staging)).toBeNull();
    expect(refusalForEnvironment(null)).toBeNull();
  });

  it("stops on --env live, dry run or --publish, and writes nothing", () => {
    for (const extra of [[], ["--publish"]]) {
      const outFolder = mkdtempSync(join(tmpdir(), "w5-live-refused-"));
      const run = runScript(["--env", "live", "--out", outFolder, ...extra]);
      expect(run.status).toBe(1);
      expect(run.stderr).toContain(LIVE_REFUSAL);
      expect(run.stdout).not.toContain("settings engine for repaired copies");
      expect(readdirSync(outFolder)).toEqual([]);
    }
  });
});
