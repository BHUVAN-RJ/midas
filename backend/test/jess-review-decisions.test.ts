// Founder decisions 2026-10-21 on the jess router review: only actions a person can take on the
// page are tools, so snooze (a notification's action) is no tool of either Sidekick; every tool
// names its page controls in _meta["midas/page-actions"], and the deploy gate checks they are on
// the page; a repair may remove a tool (option A, docs/CONCERNS.md section 15) with its handler
// and test, and the runner refuses it while the page still offers the action.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { agentBlockProblems, loadToolsScript, pageActionsOf as gatePageActionsOf, pageOffersAction as gatePageOffersAction, sidekickToolsProblems } from "../scripts/bundle-tools.mjs";
import { loadGolden } from "../scripts/eval-jess.mjs";
import { buildSystemPrompt } from "../../runner/lib/prompt.mjs";
import { checkSchemaChange } from "../../runner/lib/run-job.mjs";
import { TOOLS_REFUSAL_REASON, agentToolRemovalProblems, pageActionsOf, pageOffersAction, schemaRuleProblems } from "../../runner/lib/schema-change.mjs";

const REPO_ROOT = join(__dirname, "..", "..");
const SIDEKICK_IDS = ["reminders", "care-reminders"];

type Tool = { name: string; description: string; inputSchema: unknown; _meta?: Record<string, unknown> };
type Manifest = { agent: { tools: Tool[]; rules: string[]; examples: string[] } } & Record<string, unknown>;

function fileOf(sidekickId: string, fileName: string): string {
  return readFileSync(join(REPO_ROOT, "sidekicks", sidekickId, fileName), "utf8");
}

function manifestOf(sidekickId: string): Manifest {
  return JSON.parse(fileOf(sidekickId, "manifest.json"));
}

function toolNamesOf(manifest: Manifest): string[] {
  const names: string[] = [];
  for (const tool of manifest.agent.tools) {
    names.push(tool.name);
  }
  return names;
}

function withoutTool(manifest: Manifest, toolName: string): Manifest {
  const tools: Tool[] = [];
  for (const tool of manifest.agent.tools) {
    if (tool.name !== toolName) {
      tools.push(tool);
    }
  }
  return { ...manifest, agent: { ...manifest.agent, tools } };
}

function withoutAgent(manifest: Manifest): Record<string, unknown> {
  const copy: Record<string, unknown> = { ...manifest };
  delete copy.agent;
  return copy;
}

// The page with every data-action="<action>" and action === '<action>' renamed away
function pageWithout(html: string, action: string): string {
  return html.split(`"${action}"`).join(`"gone-${action}"`).split(`'${action}'`).join(`'gone-${action}'`);
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

function strictObject(properties: Record<string, unknown>) {
  return { type: "object", properties, required: Object.keys(properties), additionalProperties: false };
}

function demoTool(meta: unknown) {
  const tool: Record<string, unknown> = { name: "demo.add", description: "Add a thing.", inputSchema: strictObject({ title: { type: "string" } }) };
  if (meta !== undefined) {
    tool._meta = meta;
  }
  return tool;
}

function demoAgent(tool: unknown) {
  return { description: "Demo.", rules: [], notFor: [], examples: [], tools: [tool] };
}

const DEMO_TOOLS = "var MidasSidekickTools = { context: function () { return {}; }, handlers: { add: function () { return { ops: [], result: { text: 'Added' } }; } } };";

describe("snooze is not a voice action", () => {
  for (const sidekickId of SIDEKICK_IDS) {
    it(`${sidekickId} has no snooze tool, handler or example, and says why`, () => {
      const manifest = manifestOf(sidekickId);
      expect(toolNamesOf(manifest)).not.toContain(`${sidekickId}.snooze`);
      for (const example of manifest.agent.examples) {
        expect(example.toLowerCase()).not.toContain("snooze");
      }
      expect(manifest.agent.rules).toContain("Snooze is only on a notification, not a voice action.");
      const loaded = loadToolsScript(fileOf(sidekickId, "tools.js")) as { tools: { handlers: Record<string, unknown> } };
      expect(Object.keys(loaded.tools.handlers)).not.toContain("snooze");
      expect(fileOf(sidekickId, "tools.js")).not.toContain("function snoozeReminder");
    });
  }

  it("the golden set sends snooze sentences to Not Done, and no case calls a snooze tool", () => {
    const golden = loadGolden() as { cases: Array<{ id: string; say: string; call: { tool: string }; expect: Record<string, unknown> }> };
    let snoozeSentences = 0;
    for (const goldenCase of golden.cases) {
      expect(goldenCase.call.tool.endsWith(".snooze"), goldenCase.id).toBe(false);
      if (goldenCase.say.startsWith("snooze")) {
        snoozeSentences += 1;
        expect(goldenCase.expect, goldenCase.id).toEqual({ status: "not-done", reason: "no-tool-fits" });
      }
    }
    expect(snoozeSentences).toBe(6);
  });
});

describe("every tool is an action the page offers", () => {
  for (const sidekickId of SIDEKICK_IDS) {
    it(`${sidekickId}: every tool names its page controls, and each is in index.html`, () => {
      const html = fileOf(sidekickId, "index.html");
      for (const tool of manifestOf(sidekickId).agent.tools) {
        const actions = gatePageActionsOf(tool);
        expect(actions.length, tool.name).toBeGreaterThan(0);
        for (const action of actions) {
          expect(gatePageOffersAction(html, action), `${tool.name}: ${action}`).toBe(true);
        }
      }
      expect(sidekickToolsProblems(manifestOf(sidekickId), fileOf(sidekickId, "tools.js"), html, sidekickId)).toEqual([]);
    });
  }

  it("names the agreed controls for the actions most likely to change", () => {
    const reminders = manifestOf("reminders");
    const care = manifestOf("care-reminders");
    const byName: Record<string, unknown> = {};
    for (const tool of [...reminders.agent.tools, ...care.agent.tools]) {
      byName[tool.name] = tool._meta?.["midas/page-actions"];
    }
    expect(byName["reminders.delete"]).toEqual(["swipe-delete"]);
    expect(byName["reminders.complete"]).toEqual(["toggle-done"]);
    expect(byName["reminders.move_list"]).toEqual(["saveSidebarOrderTask"]);
    expect(byName["care-reminders.complete"]).toEqual(["done"]);
    expect(byName["care-reminders.delete_list"]).toEqual(["deleteListFromSheet"]);
  });

  it("the gate refuses a tool without page controls, with a malformed list, or naming one the page lacks", () => {
    expect(agentBlockProblems(demoAgent(demoTool({ "midas/page-actions": ["add-thing"] })), "demo")).toEqual([]);
    expect(agentBlockProblems(demoAgent(demoTool(undefined)), "demo").join(" ")).toContain("_meta must be an object");
    expect(agentBlockProblems(demoAgent(demoTool({})), "demo").join(" ")).toContain('"midas/page-actions"] must name 1 to 10');
    expect(agentBlockProblems(demoAgent(demoTool({ "midas/page-actions": [] })), "demo").join(" ")).toContain("must name 1 to 10");
    expect(agentBlockProblems(demoAgent(demoTool({ "midas/page-actions": ["has space"] })), "demo").join(" ")).toContain("data-action values or page function names");

    const manifest = { id: "demo", agent: demoAgent(demoTool({ "midas/page-actions": ["add-thing"] })) };
    expect(sidekickToolsProblems(manifest, DEMO_TOOLS, '<button data-action="add-thing">Add</button>', "demo")).toEqual([]);
    expect(sidekickToolsProblems(manifest, DEMO_TOOLS, "<p>no button</p>", "demo")).toEqual([
      'manifest.json: demo.add names the page control "add-thing", which index.html does not have; a tool is only an action the page offers',
    ]);
  });

  it("finds a control by data-action, by a handler's action check, or by a page function, and nothing else", () => {
    const samples: Array<[string, string, boolean]> = [
      ['<li data-action="swipe-delete">', "swipe-delete", true],
      ["<li data-action='swipe-delete'>", "swipe-delete", true],
      ["if (action === 'swipe-delete') {", "swipe-delete", true],
      ["function saveSidebarOrderTask() {", "saveSidebarOrderTask", true],
      ["async function deleteListFromSheet () {", "deleteListFromSheet", true],
      ["// swipe-delete was here", "swipe-delete", false],
      ['<li data-action="swipe-delete-all">', "swipe-delete", false],
      ["saveSidebarOrderTask();", "saveSidebarOrderTask", false],
    ];
    for (const [html, action, offered] of samples) {
      expect(gatePageOffersAction(html, action), html).toBe(offered);
      expect(pageOffersAction(html, action), html).toBe(offered);
    }
    const tool = demoTool({ "midas/page-actions": ["a", "b"] });
    expect(pageActionsOf(tool)).toEqual(gatePageActionsOf(tool));
    expect(pageActionsOf(demoTool(undefined))).toEqual([]);
    expect(pageActionsOf(null)).toEqual([]);
  });
});

describe("a repair may remove a tool once its action is gone from the page", () => {
  it("allows a removal when none of the tool's controls is left, and an added tool", () => {
    const before = manifestOf("reminders");
    const after = withoutTool(before, "reminders.delete");
    const html = fileOf("reminders", "index.html");
    expect(agentToolRemovalProblems(before, after, pageWithout(html, "swipe-delete"))).toEqual([]);
    const added = { ...before, agent: { ...before.agent, tools: [...before.agent.tools, { name: "reminders.pin", description: "Pin.", inputSchema: strictObject({}), _meta: { "midas/page-actions": ["pin"] } }] } };
    expect(agentToolRemovalProblems(before, added, html)).toEqual([]);
    expect(agentToolRemovalProblems(before, before, html)).toEqual([]);
    expect(agentToolRemovalProblems(withoutAgent(before), withoutAgent(before), html)).toEqual([]);
  });

  it("refuses a removal while the page still offers it, one it cannot check, and a removed agent block", () => {
    const before = manifestOf("care-reminders");
    const html = fileOf("care-reminders", "index.html");
    expect(agentToolRemovalProblems(before, withoutTool(before, "care-reminders.complete"), html)).toEqual(["tool care-reminders.complete was removed, but the page still offers done"]);
    expect(agentToolRemovalProblems(before, withoutTool(before, "care-reminders.delete_list"), html)).toEqual(["tool care-reminders.delete_list was removed, but the page still offers deleteListFromSheet"]);
    const unmarked = { ...before, agent: { ...before.agent, tools: [{ name: "care-reminders.old", description: "Old.", inputSchema: strictObject({}) }, ...before.agent.tools] } };
    expect(agentToolRemovalProblems(unmarked, before, html)).toEqual(["tool care-reminders.old was removed, but it names no page controls to check the page by"]);
    expect(agentToolRemovalProblems(before, withoutAgent(before), html)).toEqual(["the agent block was removed"]);
  });

  it("fails the job in the runner and in the agent's check with the new reason, and passes a clean removal", () => {
    const before = manifestOf("reminders");
    const after = withoutTool(before, "reminders.delete");
    const html = fileOf("reminders", "index.html");
    const pageAfter = pageWithout(html, "swipe-delete");
    expect(TOOLS_REFUSAL_REASON).toBe("voice tool removed but its action stays");
    const refused = failureOf(() => checkSchemaChange({ manifestBeforeText: JSON.stringify(before), manifestAfterText: JSON.stringify(after), htmlAfter: html }));
    expect(refused).toEqual({ reason: TOOLS_REFUSAL_REASON, detail: "tool reminders.delete was removed, but the page still offers swipe-delete" });
    expect(checkSchemaChange({ manifestBeforeText: JSON.stringify(before), manifestAfterText: JSON.stringify(after), htmlAfter: pageAfter })).toEqual(after);
    expect(schemaRuleProblems({ manifestBefore: before, manifestAfter: after, htmlAfter: html })).toEqual([`${TOOLS_REFUSAL_REASON}: tool reminders.delete was removed, but the page still offers swipe-delete`]);
    expect(schemaRuleProblems({ manifestBefore: before, manifestAfter: after, htmlAfter: pageAfter })).toEqual([]);
  });

  for (const sidekickId of SIDEKICK_IDS) {
    it(`tells the ${sidekickId} repair agent the new rules`, () => {
      const job = { id: "r1", sidekickId, kind: "change", transcript: "remove the delete button", createdAt: "2026-10-21T00:00:00Z" };
      const prompt = buildSystemPrompt({ job, reportFiles: ["transcript.txt"], manifestText: fileOf(sidekickId, "manifest.json") });
      expect(prompt).toContain("## Voice tools (`sidekick/tools.js` and the `agent` block)");
      expect(prompt).toContain('"_meta": { "midas/page-actions": [...] }');
      expect(prompt).toContain("**Only actions a person can take on the page are tools**");
      expect(prompt).toContain("Snooze, for one");
      expect(prompt).toContain("**A feature removed from the page removes its tool, in the same change**");
      expect(prompt).toContain(`"${TOOLS_REFUSAL_REASON}"`);
      expect(prompt).toContain("**Never remove the `agent` block or `tools.js`**");
      expect(prompt).not.toContain("Never remove or rename a tool");
      expect(prompt).not.toContain('refused: "cannot-change"');
      expect(prompt).toContain(`\`${sidekickId}-tools*.test.ts\``);
    });
  }
});
