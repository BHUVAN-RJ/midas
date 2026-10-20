// The agent's own check tool applies the runner's schema rules (founder, 2026-10-19;
// docs/briefs/repair-data-2026-10-19.md item 2), so the repair agent hears "not backward compatible"
// or "schema missing" while it can still fix it, instead of from a failed job. The runner gives the
// tool the copy's manifest as the job started through MIDAS_JOB_MANIFEST_BEFORE.
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { agentEnvironment } from "../../runner/lib/agent.mjs";
import { schemaRuleProblems } from "../../runner/lib/schema-change.mjs";

const repoRoot = new URL("../../", import.meta.url);
const checkToolPath = new URL("runner/tools/check.mjs", repoRoot).pathname;
const baseHtml = readFileSync(new URL("sidekicks/reminders/index.html", repoRoot), "utf8");
const baseManifestText = readFileSync(new URL("sidekicks/reminders/manifest.json", repoRoot), "utf8");

// A job folder with the given page and manifest, and the original manifest beside it.
function makeJob(manifestAfter: Record<string, unknown>, htmlAfter = baseHtml) {
  const scratch = mkdtempSync(join(tmpdir(), "midas-check-tool-"));
  const jobFolder = join(scratch, "job");
  mkdirSync(join(jobFolder, "sidekick"), { recursive: true });
  writeFileSync(join(jobFolder, "sidekick", "index.html"), htmlAfter);
  writeFileSync(join(jobFolder, "sidekick", "manifest.json"), JSON.stringify(manifestAfter));
  const manifestBeforePath = join(scratch, "manifest-before.json");
  writeFileSync(manifestBeforePath, baseManifestText);
  return { jobFolder, manifestBeforePath, scratch };
}

// Runs the tool; returns { code, output }.
function runCheckTool(jobFolder: string, manifestBeforePath: string, checkoutRoot: string) {
  const environment = { ...process.env, MIDAS_JOB_FOLDER: jobFolder, MIDAS_RUNNER_CHECKOUT: checkoutRoot, MIDAS_JOB_SIDEKICK_ID: "reminders", MIDAS_JOB_MANIFEST_BEFORE: manifestBeforePath };
  try {
    const output = execFileSync(process.execPath, [checkToolPath], { env: environment, encoding: "utf8" });
    return { code: 0, output };
  } catch (error) {
    const failure = error as { status: number; stdout: string };
    return { code: failure.status, output: failure.stdout };
  }
}

describe("the agent's check tool and the schema rules", () => {
  it("fails a removed field before running anything else, naming it", () => {
    const manifest = JSON.parse(baseManifestText);
    delete manifest.types["reminder:"].schema.properties.notes;
    const { jobFolder, manifestBeforePath, scratch } = makeJob(manifest);
    // The checkout is an empty folder: the tool must stop at the schema step, before the gate.
    const result = runCheckTool(jobFolder, manifestBeforePath, join(scratch, "no-checkout"));
    expect(result.code).toBe(1);
    expect(result.output).toContain("check failed: schema not backward compatible: reminders.item.notes was removed");
  });

  it("fails a page that writes an undeclared record type", () => {
    const html = baseHtml.replace("</script>", "\nfunction saveTag(id) { return store.set('tag:' + id, {}); }\n</script>");
    const { jobFolder, manifestBeforePath, scratch } = makeJob(JSON.parse(baseManifestText), html);
    const result = runCheckTool(jobFolder, manifestBeforePath, join(scratch, "no-checkout"));
    expect(result.code).toBe(1);
    expect(result.output).toContain("schema missing: the page writes tag:");
  });

  it("finds no schema problem for an added optional field", () => {
    const manifestAfter = JSON.parse(baseManifestText);
    manifestAfter.types["reminder:"].schema.properties.priority = { type: "string" };
    expect(schemaRuleProblems({ manifestBefore: JSON.parse(baseManifestText), manifestAfter, htmlAfter: baseHtml })).toEqual([]);
  });

  it("the runner gives the agent the original manifest's path, and only when it has one", () => {
    const withPath = agentEnvironment({ baseEnvironment: {}, claudeConfigDir: "/c", jobFolder: "/j", checkoutRoot: "/r", sidekickId: "reminders", manifestBeforePath: "/log/before/manifest.json" });
    expect(withPath.MIDAS_JOB_MANIFEST_BEFORE).toBe("/log/before/manifest.json");
    const withoutPath = agentEnvironment({ baseEnvironment: {}, claudeConfigDir: "/c", jobFolder: "/j", checkoutRoot: "/r", sidekickId: "reminders" });
    expect("MIDAS_JOB_MANIFEST_BEFORE" in withoutPath).toBe(false);
  });
});
