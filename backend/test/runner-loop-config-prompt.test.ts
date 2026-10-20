// The runner loop (one job at a time), its settings, the claim-reply shapes it accepts, the
// outcome file, and the system prompt it assembles.
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { normalizeJob } from "../../runner/lib/backend.mjs";
import { parseEnvFile, settingsFromEnv } from "../../runner/lib/config.mjs";
import { foreignFiles, isAllowedJobFile } from "../../runner/lib/job-folder.mjs";
import { runLoop } from "../../runner/lib/loop.mjs";
import { readOutcome } from "../../runner/lib/outcome.mjs";
import { buildSystemPrompt, templateNameForSidekick } from "../../runner/lib/prompt.mjs";
import { makeScratch } from "./helpers/runner-fixture";

describe("runLoop", () => {
  it("claims the next job only after the running one has finished, and sleeps when none waits", async () => {
    const events: string[] = [];
    const jobs: Array<{ id: string } | null> = [{ id: "a" }, null, { id: "b" }];
    let running = 0;
    let stopAfter = 3;
    await runLoop({
      claimJob: async () => {
        expect(running).toBe(0);
        events.push("claim");
        return jobs.shift() ?? null;
      },
      runJob: async (job: { id: string }) => {
        running += 1;
        events.push(`start ${job.id}`);
        await new Promise((resolve) => setTimeout(resolve, 20));
        events.push(`end ${job.id}`);
        running -= 1;
      },
      pollIntervalMs: 5,
      sleep: async (milliseconds: number) => {
        events.push(`sleep ${milliseconds}`);
      },
      shouldStop: () => {
        stopAfter -= 1;
        return stopAfter < 0;
      },
    });
    expect(events).toEqual(["claim", "start a", "end a", "claim", "sleep 5", "claim", "start b", "end b"]);
  });

  it("a claim error or a job error does not stop the loop", async () => {
    const errors: string[] = [];
    let calls = 0;
    await runLoop({
      claimJob: async () => {
        calls += 1;
        if (calls === 1) {
          throw new Error("backend down");
        }
        return { id: "x" };
      },
      runJob: async () => {
        throw new Error("job blew up");
      },
      pollIntervalMs: 1,
      sleep: async () => {},
      shouldStop: () => calls >= 2,
      onError: (error: Error) => {
        errors.push(error.message);
      },
    });
    expect(errors).toEqual(["backend down", "job blew up"]);
  });
});

describe("settings", () => {
  it("reads the env file format and applies defaults", () => {
    const parsed = parseEnvFile('# comment\nMIDAS_BACKEND_URL="https://api.example/"\nMIDAS_RUNNER_TOKEN=tok\n\nBAD LINE\n');
    expect(parsed).toEqual({ MIDAS_BACKEND_URL: "https://api.example/", MIDAS_RUNNER_TOKEN: "tok" });
    const settings = settingsFromEnv({ ...parsed, MIDAS_RUNNER_HOME: "/r" });
    expect(settings.backendUrl).toBe("https://api.example");
    expect(settings.model).toBe("opus");
    expect(settings.maxTurns).toBe(50);
    expect(settings.jobTimeoutMs).toBe(30 * 60_000);
    expect(settings.pollIntervalMs).toBe(30_000);
    expect(settings.heartbeatIntervalMs).toBe(5 * 60_000);
    expect(settings.jobsRoot).toBe("/r/jobs");
    expect(settings.logsRoot).toBe("/r/log");
  });

  it("refuses to start without the backend URL or the runner token, or with a bad number", () => {
    expect(() => settingsFromEnv({ MIDAS_RUNNER_TOKEN: "t" })).toThrow("MIDAS_BACKEND_URL");
    expect(() => settingsFromEnv({ MIDAS_BACKEND_URL: "u" })).toThrow("MIDAS_RUNNER_TOKEN");
    expect(() => settingsFromEnv({ MIDAS_BACKEND_URL: "u", MIDAS_RUNNER_TOKEN: "t", MIDAS_RUNNER_MAX_TURNS: "zero" })).toThrow("MIDAS_RUNNER_MAX_TURNS");
  });
});

describe("normalizeJob", () => {
  it("accepts the D1 row shape, a camelCase shape, and a wrapped report", () => {
    const fromRow = normalizeJob({ id: "1", user_id: "u", sidekick_id: "reminders", bundle_version: "v", transcript: "t", kind: "bug" });
    expect(fromRow).toMatchObject({ id: "1", userId: "u", sidekickId: "reminders", bundleVersion: "v", transcript: "t", kind: "bug" });
    const fromCamel = normalizeJob({ reportId: 7, userId: "u", sidekickId: "reminders" });
    expect(fromCamel).toMatchObject({ id: "7", kind: "unknown", transcript: "" });
    const wrapped = normalizeJob({ report: { id: "2", user_id: "u", sidekick_id: "reminders" }, leaseExpiresAt: "2026-10-13T10:00:00Z" });
    expect(wrapped).toMatchObject({ id: "2", leaseExpiresAt: "2026-10-13T10:00:00Z" });
  });

  it("rejects a reply without the three required fields", () => {
    expect(() => normalizeJob({ id: "1", user_id: "u" })).toThrow("lacks id, userId or sidekickId");
  });
});

describe("job folder rules and outcome.json", () => {
  it("allows exactly the Sidekick files, report files and outcome.json", () => {
    expect(isAllowedJobFile("sidekick/index.html")).toBe(true);
    expect(isAllowedJobFile("sidekick/manifest.json")).toBe(true);
    expect(isAllowedJobFile("report/screenshot.png")).toBe(true);
    expect(isAllowedJobFile("outcome.json")).toBe(true);
    expect(isAllowedJobFile("sidekick/extra.js")).toBe(false);
    expect(isAllowedJobFile("CLAUDE.md")).toBe(false);
    expect(isAllowedJobFile(".git/HEAD")).toBe(false);
    expect(isAllowedJobFile("node_modules/x/index.js")).toBe(false);
    expect(isAllowedJobFile("report/sub/file.txt")).toBe(false);
  });

  it("foreignFiles finds what should not be there", () => {
    const folder = mkdtempSync(join(tmpdir(), "jobfolder-"));
    mkdirSync(join(folder, "sidekick"));
    mkdirSync(join(folder, "report"));
    mkdirSync(join(folder, ".git"));
    writeFileSync(join(folder, "sidekick", "index.html"), "<p>x</p>");
    writeFileSync(join(folder, "report", "transcript.txt"), "t");
    writeFileSync(join(folder, ".git", "HEAD"), "ref");
    writeFileSync(join(folder, "CLAUDE.md"), "rules");
    expect(foreignFiles(folder)).toEqual([".git/HEAD", "CLAUDE.md"]);
  });

  it("readOutcome validates the agent's file", () => {
    const folder = mkdtempSync(join(tmpdir(), "outcome-"));
    expect(readOutcome(folder).problem).toBe("agent wrote no outcome.json");
    writeFileSync(join(folder, "outcome.json"), "not json");
    expect(readOutcome(folder).problem).toBe("outcome.json is not JSON");
    writeFileSync(join(folder, "outcome.json"), JSON.stringify({ result: "maybe", summary: "s" }));
    expect(readOutcome(folder).problem).toContain("result must be one of");
    writeFileSync(join(folder, "outcome.json"), JSON.stringify({ result: "unsupported", summary: "s" }));
    expect(readOutcome(folder).problem).toContain("needs unsupportedAction");
    writeFileSync(join(folder, "outcome.json"), JSON.stringify({ result: "fixed", summary: "  Moved the tag.  " }));
    expect(readOutcome(folder).outcome).toEqual({ result: "fixed", summary: "Moved the tag.", unsupportedAction: null });
  });
});

describe("system prompt", () => {
  it("has a Reminders agent and a care-reminders agent, and none for other Sidekicks", () => {
    expect(templateNameForSidekick("reminders")).toBe("reminders");
    expect(templateNameForSidekick("care-reminders")).toBe("care-reminders");
    expect(templateNameForSidekick("split")).toBeNull();
    expect(() => buildSystemPrompt({ job: { sidekickId: "split", transcript: "x" }, reportFiles: [] })).toThrow('no repair agent for Sidekick "split"');
  });

  it("embeds the report, the writing rules, the record contract, the limits and the two tools", () => {
    const { checkout } = makeScratch();
    const job = { sidekickId: "reminders", kind: "bug", device: "iPhone 16 Pro", appVersion: "0.1.0 (2)", bundleVersion: "v9", transcript: "reminders fire when I haven't set them" };
    const prompt = buildSystemPrompt({ job, reportFiles: ["transcript.txt", "screenshot.png"], checkoutRoot: checkout, intelToolPath: "/r/intel.mjs", checkToolPath: "/r/check.mjs" });
    expect(prompt).toContain("reminders fire when I haven't set them");
    expect(prompt).toContain("Kind hint from the phone: bug");
    expect(prompt).toContain("Report files present: transcript.txt, screenshot.png");
    expect(prompt).toContain("Say the action. Stop.");
    expect(prompt).toContain("### 4.2 The `reminder:` record");
    expect(prompt).toContain("## 7. Limits and known issues");
    expect(prompt).toContain("node /r/intel.mjs list");
    expect(prompt).toContain("node /r/check.mjs");
    expect(prompt).toContain("is the request supported?");
    expect(prompt).toContain('"result": "unsupported"');
    expect(prompt).not.toContain("{{");
  });
});
