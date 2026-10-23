// Lead items 13 and 14 (reviewer A, second pass, 2026-10-20).
//   13 the repair agent's environment is an allow-list (never MIDAS_RUNNER_TOKEN, nothing else from
//      ~/.midas-runner/env), and the vitest that runs the agent's tests, from the runner or from
//      the check tool, sees no token at all.
//   14 a "not" widened by deleting a properties / patternProperties entry inside it is refused.
import { execFileSync } from "node:child_process";
import { cpSync, mkdirSync, mkdtempSync, realpathSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { agentEnvironment } from "../../runner/lib/agent.mjs";
import { checkSidekick } from "../../runner/lib/check.mjs";
import { compareSchema } from "../../runner/lib/schema-change.mjs";
import { REPO_ROOT } from "./helpers/runner-fixture";

const SECRET_NAMES = ["MIDAS_RUNNER_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_API_KEY", "MIDAS_ENV_FILE_SECRET"];

const savedValues: Record<string, string | undefined> = {};
for (const name of SECRET_NAMES) {
  savedValues[name] = process.env[name];
}

afterEach(() => {
  for (const name of SECRET_NAMES) {
    if (savedValues[name] === undefined) {
      delete process.env[name];
    } else {
      process.env[name] = savedValues[name];
    }
  }
});

function setFakeSecrets() {
  process.env.MIDAS_RUNNER_TOKEN = "runner-token-must-not-leak";
  process.env.CLAUDE_CODE_OAUTH_TOKEN = "claude-token-must-not-leak";
  process.env.ANTHROPIC_API_KEY = "api-key-must-not-leak";
  process.env.MIDAS_ENV_FILE_SECRET = "env-file-secret-must-not-leak";
}

describe("13: the agent's environment is an allow-list", () => {
  const baseEnvironment = {
    PATH: "/usr/bin:/bin",
    HOME: "/Users/f",
    TMPDIR: "/tmp/",
    MIDAS_RUNNER_TOKEN: "runner-token",
    MIDAS_BACKEND_URL: "https://midas-api-staging.midas-backend.workers.dev",
    MIDAS_RUNNER_ENV: "staging",
    CLAUDE_CODE_OAUTH_TOKEN: "claude-token",
    ANTHROPIC_API_KEY: "api-key",
    MIDAS_ENV_FILE_SECRET: "other",
    AWS_SECRET_ACCESS_KEY: "aws",
  };

  it("holds the plain settings, the job's, the Claude config dir and Claude's own login, nothing else", () => {
    const environment = agentEnvironment({ baseEnvironment, claudeConfigDir: "/c", jobFolder: "/j", checkoutRoot: "/k", sidekickId: "reminders", manifestBeforePath: "/m" });
    expect(Object.keys(environment).sort()).toEqual([
      "CLAUDE_CODE_OAUTH_TOKEN",
      "CLAUDE_CONFIG_DIR",
      "HOME",
      "MIDAS_JOB_FOLDER",
      "MIDAS_JOB_MANIFEST_BEFORE",
      "MIDAS_JOB_SIDEKICK_ID",
      "MIDAS_RUNNER_CHECKOUT",
      "PATH",
      "TMPDIR",
    ]);
    expect(environment.MIDAS_RUNNER_TOKEN).toBeUndefined();
    expect(environment.CLAUDE_CODE_OAUTH_TOKEN).toBe("claude-token");
  });

  it("passes an API key only when the founder opted in, and never the runner token", () => {
    const optedIn = agentEnvironment({ baseEnvironment: { ...baseEnvironment, MIDAS_RUNNER_USE_API_KEY: "1" }, claudeConfigDir: "/c", jobFolder: "/j", checkoutRoot: "/k", sidekickId: "reminders" });
    expect(optedIn.ANTHROPIC_API_KEY).toBe("api-key");
    expect(optedIn.MIDAS_RUNNER_TOKEN).toBeUndefined();
    expect(optedIn.MIDAS_RUNNER_USE_API_KEY).toBeUndefined();
  });
});

// A job folder with the base Reminders page and one copy test that fails when it sees any token.
function jobWithEnvironmentProbe(): string {
  const scratch = realpathSync(mkdtempSync(join(tmpdir(), "midas-secret-probe-")));
  const jobFolder = join(scratch, "job");
  mkdirSync(join(jobFolder, "sidekick"), { recursive: true });
  mkdirSync(join(jobFolder, "tests"), { recursive: true });
  for (const fileName of ["index.html", "manifest.json", "tools.js"]) {
    cpSync(join(REPO_ROOT, "sidekicks", "reminders", fileName), join(jobFolder, "sidekick", fileName));
  }
  const probe = [
    'import { expect, it } from "vitest";',
    `const secretNames = ${JSON.stringify(SECRET_NAMES)};`,
    'it("sees no secret in its environment", () => {',
    "  const seen = secretNames.filter(function isSet(name) { return process.env[name] !== undefined; });",
    "  expect(seen).toEqual([]);",
    "  expect(process.env.PATH).toBeTruthy();",
    "});",
  ].join("\n");
  writeFileSync(join(jobFolder, "tests", "environment-probe.test.ts"), probe);
  return jobFolder;
}

describe("13: the agent's tests run without any token", () => {
  it("the runner's own check runs them with no token, though the runner holds them", async () => {
    setFakeSecrets();
    const jobFolder = jobWithEnvironmentProbe();
    const result = await checkSidekick({ checkoutRoot: REPO_ROOT, sidekickId: "reminders", jobFolder });
    expect(result.testOutput).toContain("environment-probe");
    expect(result.ok).toBe(true);
  }, 120_000);

  it("the check tool the agent runs, started with both tokens, runs them with none", () => {
    const jobFolder = jobWithEnvironmentProbe();
    const toolEnvironment = {
      PATH: process.env.PATH ?? "",
      HOME: process.env.HOME ?? "",
      MIDAS_JOB_FOLDER: jobFolder,
      MIDAS_RUNNER_CHECKOUT: REPO_ROOT,
      MIDAS_JOB_SIDEKICK_ID: "reminders",
      MIDAS_RUNNER_TOKEN: "runner-token-must-not-leak",
      CLAUDE_CODE_OAUTH_TOKEN: "claude-token-must-not-leak",
    };
    const printed = execFileSync(process.execPath, [join(REPO_ROOT, "runner", "tools", "check.mjs")], { env: toolEnvironment, encoding: "utf8", timeout: 120_000 });
    expect(printed).toContain("check passed");
  }, 150_000);
});

describe("14: a not widened by losing an entry is refused", () => {
  function problemsBetween(oldSchema: unknown, newSchema: unknown): string[] {
    const problems: string[] = [];
    compareSchema(oldSchema, newSchema, "t", problems);
    return problems;
  }

  it("refuses deleting a properties or patternProperties entry inside a not, at any depth", () => {
    const fromProperties = problemsBetween({ not: { properties: { a: { type: "string" } } } }, { not: {} });
    expect(fromProperties).toEqual(["t.not now matches more values, so the field accepts fewer (t.not.a was removed)"]);
    const fromPatterns = problemsBetween({ not: { patternProperties: { "^x-": { type: "string" } } } }, { not: { patternProperties: {} } });
    expect(fromPatterns).toHaveLength(1);
    expect(fromPatterns[0]).toContain('t.not.patternProperties.^x- was removed');
    const nested = problemsBetween(
      { not: { properties: { a: { properties: { b: { type: "string" } } } } } },
      { not: { properties: { a: { properties: {} } } } },
    );
    expect(nested).toHaveLength(1);
    expect(nested[0]).toContain("t.not.a.b was removed");
  });

  it("allows a not that gained an entry (it matches less, so the field accepts more)", () => {
    expect(problemsBetween({ not: { properties: { a: { type: "string" } } } }, { not: { properties: { a: { type: "string" }, b: { type: "string" } } } })).toEqual([]);
  });
});
