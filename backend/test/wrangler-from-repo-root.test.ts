// Lead item 11 (first staging run, 2026-10-19): the runner calls the checkout's wrangler helper
// from its own cwd, the repo root, where wrangler is not installed; npx then waited 30 minutes on a
// hidden install prompt. Run from the repo root with an empty npx cache (the Mac mini's case), the
// helper must still find backend/'s wrangler and answer at once.
import { execFileSync } from "node:child_process";
import { mkdtempSync, realpathSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { describe, expect, it } from "vitest";
import { REPO_ROOT } from "./helpers/runner-fixture";

const WRANGLER_HELPER_URL = pathToFileURL(join(REPO_ROOT, "backend", "scripts", "wrangler.mjs")).href;

// Runs a small ES module with node from the repo root, with npx's cache pointed at an empty folder.
function runFromRepoRoot(source: string): string {
  const emptyCache = realpathSync(mkdtempSync(join(tmpdir(), "midas-empty-npx-cache-")));
  const environment = { PATH: process.env.PATH ?? "", HOME: process.env.HOME ?? "", npm_config_cache: emptyCache, npm_config_yes: "false" };
  return execFileSync(process.execPath, ["--input-type=module", "-e", source], {
    cwd: REPO_ROOT,
    env: environment,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
    timeout: 90_000,
  });
}

describe("the wrangler helper from the repo root", () => {
  it("runs wrangler in backend/ whatever the caller's cwd", () => {
    const printed = runFromRepoRoot(`import { wranglerInvocation } from ${JSON.stringify(WRANGLER_HELPER_URL)}; console.log(JSON.stringify(wranglerInvocation(["--version"])));`);
    const invocation = JSON.parse(printed);
    expect(resolve(invocation.cwd)).toBe(resolve(REPO_ROOT, "backend"));
    expect(invocation.args.slice(0, 2)).toEqual(["--no-install", "wrangler"]);
  });

  it("answers wrangler --version from the repo root with an empty npx cache, without waiting", () => {
    const started = Date.now();
    const printed = runFromRepoRoot(`import { captureWrangler } from ${JSON.stringify(WRANGLER_HELPER_URL)}; process.stdout.write(captureWrangler(["--version"], { timeoutMs: 60000 }));`);
    expect(printed).toMatch(/\d+\.\d+\.\d+/);
    expect(Date.now() - started).toBeLessThan(60_000);
  }, 120_000);
});
