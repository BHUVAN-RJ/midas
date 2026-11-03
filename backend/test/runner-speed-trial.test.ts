// Runner speed trial (founder, 2026-11-02): only Reminder Test gets the page map, lower effort and
// parallel fetch and deploy; every other Sidekick runs exactly as before. Repair b8dea1a6 took
// about 6 minutes (agent 4m43s, fetch 29 s, deploy 39 s).
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { buildClaudeArgs } from "../../runner/lib/agent.mjs";
import { fetchArgs } from "../../runner/lib/copy-tests.mjs";
import { deployArgs } from "../../runner/lib/deploy.mjs";
import { effortFor, fileMapLines, isSpeedTrial, parallelArgsFor, speedTrialPromptText } from "../../runner/lib/speed-trial.mjs";
import { runWithLimit } from "../scripts/wrangler.mjs";

const reminderTestHtml = readFileSync(new URL("../../sidekicks/reminder-test/index.html", import.meta.url), "utf8");

describe("which Sidekicks are in the trial", () => {
  it("Reminder Test only", () => {
    expect(isSpeedTrial("reminder-test")).toBe(true);
    expect(isSpeedTrial("reminders")).toBe(false);
    expect(isSpeedTrial("todo")).toBe(false);
    expect(effortFor("reminder-test")).toBe("medium");
    expect(effortFor("reminders")).toBeNull();
  });

  it("fetch and deploy get --parallel for Reminder Test and nothing new for the rest", () => {
    const trialFetch = fetchArgs({ sidekickId: "reminder-test", userId: "u1", outFolder: "/tmp/o", environmentName: "staging" });
    const otherFetch = fetchArgs({ sidekickId: "reminders", userId: "u1", outFolder: "/tmp/o", environmentName: "staging" });
    expect(trialFetch.at(-1)).toBe("--parallel");
    expect(otherFetch).not.toContain("--parallel");
    expect(parallelArgsFor("reminders")).toEqual([]);
    const trialDeploy = deployArgs({ sidekickId: "reminder-test", userId: "u1", deployFolder: "/tmp/d", environmentName: "staging" });
    const otherDeploy = deployArgs({ sidekickId: "reminders", userId: "u1", deployFolder: "/tmp/d", environmentName: "staging" });
    expect(trialDeploy.at(-1)).toBe("--parallel");
    expect(otherDeploy).not.toContain("--parallel");
  });

  it("the agent gets --effort only when one is given", () => {
    const base = { systemPromptPath: "/tmp/p.md", model: "opus", maxTurns: 50 };
    const withEffort = buildClaudeArgs({ ...base, effort: "medium" });
    const withoutEffort = buildClaudeArgs(base);
    const effortIndex = withEffort.indexOf("--effort");
    expect(effortIndex).not.toBe(-1);
    expect(withEffort[effortIndex + 1]).toBe("medium");
    expect(withoutEffort).not.toContain("--effort");
  });
});

describe("page map", () => {
  it("lists functions, sections and data-actions with the line the Read tool shows", () => {
    const text = ["/* ---------- Rows ---------- */", "function drawRow() {", "}", "<button data-action=\"add\">", "async function save() {}", "<a data-action=\"add\">"].join("\n");
    expect(fileMapLines(text)).toEqual(["L1 == Rows ==", "L2 drawRow()", "L5 save()", "data-action: add (L4)"]);
  });

  it("maps the real Reminder Test page: viewExists is listed at its real line", () => {
    const lines = reminderTestHtml.split("\n");
    const realLine = lines.findIndex((line) => line.includes("function viewExists(")) + 1;
    expect(realLine).toBeGreaterThan(0);
    expect(fileMapLines(reminderTestHtml)).toContain(`L${realLine} viewExists()`);
  });

  it("the prompt section says Bash is only for the check and intel tools", () => {
    const text = speedTrialPromptText({ html: reminderTestHtml, toolsText: "function handleAdd() {}" });
    expect(text).toContain("## Map of this copy");
    expect(text).toContain("Bash runs only the check tool and the intel tool");
    expect(text).toContain("### sidekick/tools.js");
    expect(text).toContain("L1 handleAdd()");
  });
});

describe("runWithLimit (parallel wrangler calls)", () => {
  it("keeps results in order and never runs more than the limit at once", async () => {
    let running = 0;
    let mostAtOnce = 0;
    async function slowDouble(value: number) {
      running += 1;
      mostAtOnce = Math.max(mostAtOnce, running);
      await new Promise((resolveWait) => setTimeout(resolveWait, 5));
      running -= 1;
      return value * 2;
    }
    const results = await runWithLimit([1, 2, 3, 4, 5, 6, 7], 3, slowDouble);
    expect(results).toEqual([2, 4, 6, 8, 10, 12, 14]);
    expect(mostAtOnce).toBe(3);
  });

  it("rejects when one call fails", async () => {
    async function failOnThree(value: number) {
      if (value === 3) {
        throw new Error("upload failed");
      }
      return value;
    }
    await expect(runWithLimit([1, 2, 3, 4], 2, failOnThree)).rejects.toThrow("upload failed");
  });
});

describe("parallel deploy keeps the pointer last", () => {
  const deployScript = readFileSync(new URL("../scripts/deploy-sidekick.mjs", import.meta.url), "utf8");

  it("uploads every version file before the pointer, and refuses a plan whose last put is not the pointer", () => {
    const body = deployScript.match(/async function executePlanInParallel\(plan\) \{([\s\S]*?)\n\}/);
    expect(body).not.toBeNull();
    const versionUpload = body![1].indexOf("await runWithLimit(versionPuts");
    const pointerUpload = body![1].indexOf("await uploadPut(pointerPut)");
    expect(versionUpload).toBeGreaterThan(-1);
    expect(pointerUpload).toBeGreaterThan(versionUpload);
    expect(body![1]).toMatch(/endsWith\("\/current\.json"\)[\s\S]*stop\(/);
  });
});
