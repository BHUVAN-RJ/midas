// Repairs keep the voice tools (jess router, founder 2026-10-21, phase 5): the repair agent is told
// that tools.js and the manifest's agent block move with every page change, and the runner and
// the agent's own check refuse a copy that drops the agent block or any tool it had. A copy whose
// tools.js no longer matches its page is refused by the gate (sidekick-tools-gate.test.ts).
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { buildSystemPrompt } from "../../runner/lib/prompt.mjs";
import { checkSchemaChange } from "../../runner/lib/run-job.mjs";
import { TOOLS_REFUSAL_REASON, agentToolsKeptProblems, schemaRuleProblems } from "../../runner/lib/schema-change.mjs";

const REPO_ROOT = join(__dirname, "..", "..");

function manifestOf(sidekickId: string) {
  return JSON.parse(readFileSync(join(REPO_ROOT, "sidekicks", sidekickId, "manifest.json"), "utf8"));
}

function htmlOf(sidekickId: string) {
  return readFileSync(join(REPO_ROOT, "sidekicks", sidekickId, "index.html"), "utf8");
}

function withoutTool(manifest: { agent: { tools: Array<{ name: string }> } }, toolName: string) {
  const tools = [];
  for (const tool of manifest.agent.tools) {
    if (tool.name !== toolName) {
      tools.push(tool);
    }
  }
  return { ...manifest, agent: { ...manifest.agent, tools } };
}

function withoutAgent(manifest: Record<string, unknown>) {
  const copy = { ...manifest };
  delete copy.agent;
  return copy;
}

function failureOf(run: () => unknown) {
  try {
    run();
  } catch (error) {
    const failure = error as { reason?: string; detail?: string };
    return { reason: failure.reason, detail: failure.detail };
  }
  return null;
}

describe("a repair keeps every voice tool", () => {
  it("allows a copy that keeps its tools or adds one", () => {
    const before = manifestOf("reminders");
    expect(agentToolsKeptProblems(before, before)).toEqual([]);
    const added = { ...before, agent: { ...before.agent, tools: [...before.agent.tools, { name: "reminders.pin", description: "Pin an item.", inputSchema: { type: "object" } }] } };
    expect(agentToolsKeptProblems(before, added)).toEqual([]);
    expect(agentToolsKeptProblems(withoutAgent(before), withoutAgent(before))).toEqual([]);
  });

  it("names each tool removed, and a removed agent block", () => {
    const before = manifestOf("care-reminders");
    expect(agentToolsKeptProblems(before, withoutTool(before, "care-reminders.complete"))).toEqual(["tool care-reminders.complete was removed"]);
    expect(agentToolsKeptProblems(before, withoutAgent(before))).toEqual(["the agent block was removed"]);
  });

  it("fails the job in the runner and in the agent's check", () => {
    const before = manifestOf("reminders");
    const after = withoutTool(before, "reminders.delete");
    const html = htmlOf("reminders");
    expect(failureOf(() => checkSchemaChange({ manifestBeforeText: JSON.stringify(before), manifestAfterText: JSON.stringify(after), htmlAfter: html }))).toEqual({ reason: TOOLS_REFUSAL_REASON, detail: "tool reminders.delete was removed" });
    expect(failureOf(() => checkSchemaChange({ manifestBeforeText: JSON.stringify(before), manifestAfterText: JSON.stringify(withoutAgent(before)), htmlAfter: html }))).toEqual({ reason: TOOLS_REFUSAL_REASON, detail: "the agent block was removed" });
    expect(checkSchemaChange({ manifestBeforeText: JSON.stringify(before), manifestAfterText: JSON.stringify(before), htmlAfter: html })).toEqual(before);
    expect(schemaRuleProblems({ manifestBefore: before, manifestAfter: after, htmlAfter: html })).toEqual([`${TOOLS_REFUSAL_REASON}: tool reminders.delete was removed`]);
    expect(schemaRuleProblems({ manifestBefore: before, manifestAfter: before, htmlAfter: html })).toEqual([]);
  });
});

describe("the repair agent's prompt", () => {
  for (const sidekickId of ["reminders", "care-reminders"]) {
    it(`tells the ${sidekickId} agent that tools.js and the agent block move with the page`, () => {
      const manifestText = readFileSync(join(REPO_ROOT, "sidekicks", sidekickId, "manifest.json"), "utf8");
      const job = { id: "r1", sidekickId, kind: "change", transcript: "make it bigger", createdAt: "2026-10-21T00:00:00Z" };
      const prompt = buildSystemPrompt({ job, reportFiles: ["transcript.txt"], manifestText });
      expect(prompt).toContain("`sidekick/index.html`, `sidekick/tools.js` and");
      expect(prompt).toContain("## Voice tools (`sidekick/tools.js` and the `agent` block)");
      expect(prompt).toContain(`named\n  \`${sidekickId}.<verb>\``);
      expect(prompt).toContain("/* copied from index.html: begin */");
      expect(prompt).toContain("Never remove or rename a tool");
      expect(prompt).toContain(`\`${sidekickId}-tools*.test.ts\``);
    });
  }
});
