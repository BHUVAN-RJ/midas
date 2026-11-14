// The shield's checks that need no page (docs/briefs/repair-lanes.md W1; founder D1 and D3,
// 2026-11-13): the settings engine stays (repair 42396937 deleted todo.set_setting), every record
// the person has fits the new schema, and a primitive's block checks run where it defines any.
// Each check is shown passing on a good copy and failing for the reason it exists.
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { blockCheckFiles, checkPrimitiveBlocks } from "../../runner/core-checks/primitive-blocks.mjs";
import { checkRecordsFit } from "../../runner/core-checks/records-fit.mjs";
import { checkSettingsEngine } from "../../runner/core-checks/settings-engine.mjs";
import { loadDeterministicTools } from "../../runner/core-checks/tools-compare.mjs";
import { NOW_ISO, repoRoot, sidekickCopy, todoRecords, withManifest, withToolsAppended, type Copy } from "./repair-shield-fixtures";

function prepared(copy: Copy) {
  return { html: copy.html, manifest: JSON.parse(copy.manifestText), loadedTools: loadDeterministicTools(copy.toolsText, NOW_ISO) };
}

describe("shield: the settings engine stays (D1)", () => {
  const todo = sidekickCopy("todo");

  it("passes To-Do, which has the whole engine", () => {
    const result = checkSettingsEngine({ sidekickId: "todo", before: prepared(todo), after: prepared(todo), everyEngine: true });
    expect(result).toEqual({ problems: [], notes: [] });
  });

  it("fails repair 42396937's change: set_setting deleted from the manifest and tools.js", () => {
    const withoutTool = withManifest(todo, (manifest) => {
      manifest.agent.tools = manifest.agent.tools.filter((tool: { name: string }) => tool.name !== "todo.set_setting");
    });
    const after = withToolsAppended(withoutTool, "delete MidasSidekickTools.handlers.set_setting;");
    const result = checkSettingsEngine({ sidekickId: "todo", before: prepared(todo), after: prepared(after), everyEngine: false });
    expect(result.problems.length).toBe(1);
    expect(result.problems[0]).toContain("the settings engine was removed");
    expect(result.problems[0]).toContain("tool todo.set_setting");
    expect(result.problems[0]).toContain("tools.js handler set_setting");
  });

  it("fails a page that stops reading settings:self", () => {
    const after = { ...todo, html: todo.html.split("settings:self").join("settings:mine") };
    const result = checkSettingsEngine({ sidekickId: "todo", before: prepared(todo), after: prepared(after), everyEngine: false });
    expect(result.problems[0]).toContain("settings:self on the page");
  });

  it("notes a Sidekick that never had it until W5, and fails it once every Sidekick must have it", () => {
    const reminders = sidekickCopy("reminders");
    const beforeW5 = checkSettingsEngine({ sidekickId: "reminders", before: prepared(reminders), after: prepared(reminders), everyEngine: false });
    expect(beforeW5.problems).toEqual([]);
    expect(beforeW5.notes[0]).toContain("no settings engine yet");
    const afterW5 = checkSettingsEngine({ sidekickId: "reminders", before: prepared(reminders), after: prepared(reminders), everyEngine: true });
    expect(afterW5.problems[0]).toContain("the settings engine is missing: tool reminders.set_setting");
  });
});

describe("shield: every record the person has fits", () => {
  const todo = sidekickCopy("todo");
  const records = todoRecords();

  it("passes the person's records against the unchanged schema", async () => {
    const result = await checkRecordsFit({ checkoutRoot: repoRoot, records, manifestAfter: JSON.parse(todo.manifestText) });
    expect(result.problems).toEqual([]);
    expect(result.notes).toEqual([`${records.length} of the person's records fit`]);
  });

  it("fails a schema the stored to-dos no longer fit", () => {
    const after = withManifest(todo, (manifest) => {
      const itemSchema = manifest.types["reminder:"].schema;
      itemSchema.properties.priority = { type: "string" };
      itemSchema.required = [...(itemSchema.required ?? []), "priority"];
    });
    return checkRecordsFit({ checkoutRoot: repoRoot, records, manifestAfter: JSON.parse(after.manifestText) }).then((result) => {
      expect(result.problems.length).toBe(1);
      expect(result.problems[0]).toContain("of the user's records do not fit the new schema");
      expect(result.problems[0]).toContain("priority");
    });
  });
});

// A checkout holding only docs/primitives/<name>/checks/<file>.mjs files
function checkoutWithBlockChecks(files: Record<string, string>) {
  const checkoutRoot = mkdtempSync(join(tmpdir(), "midas-shield-blocks-"));
  for (const [relativePath, text] of Object.entries(files)) {
    const filePath = join(checkoutRoot, "docs", "primitives", relativePath);
    mkdirSync(join(filePath, ".."), { recursive: true });
    writeFileSync(filePath, text);
  }
  return checkoutRoot;
}

const passingCheck = `export const sidekicks = ["todo"];
export const checks = [{ id: "TD-SET-01", run(copy) { return copy.html.includes("Make It Yours") ? [] : ["no Make It Yours panel"]; } }];`;
const otherSidekickCheck = `export const sidekicks = ["planner"];
export const checks = [{ id: "DP-DAY-01", run() { return ["must not run for todo"]; } }];`;

describe("shield: primitive block checks", () => {
  const todo = sidekickCopy("todo");
  const copy = { sidekickId: "todo", html: todo.html, manifest: JSON.parse(todo.manifestText), toolsText: todo.toolsText, records: [] };

  it("runs the checks of the primitive the Sidekick is built from, and only those", async () => {
    const checkoutRoot = checkoutWithBlockChecks({ "todo/checks/settings.mjs": passingCheck, "daily-planner/checks/day.mjs": otherSidekickCheck });
    expect(blockCheckFiles(checkoutRoot).length).toBe(2);
    const result = await checkPrimitiveBlocks({ checkoutRoot, copy });
    expect(result.problems).toEqual([]);
    expect(result.notes).toEqual(["1 primitive block checks ran"]);
  });

  it("fails a copy a block check refuses, naming the block", async () => {
    const checkoutRoot = checkoutWithBlockChecks({ "todo/checks/settings.mjs": passingCheck });
    const after = { ...copy, html: copy.html.split("Make It Yours").join("Settings") };
    const result = await checkPrimitiveBlocks({ checkoutRoot, copy: after });
    expect(result.problems).toEqual(["todo TD-SET-01: no Make It Yours panel"]);
  });

  it("fails a block check that throws or does not load: a broken check never reads as a pass", async () => {
    const throwing = `export const sidekicks = ["todo"];
export const checks = [{ id: "TD-ROW-01", run() { throw new Error("row check broke"); } }];`;
    const checkoutRoot = checkoutWithBlockChecks({ "todo/checks/rows.mjs": throwing, "todo/checks/broken.mjs": "export const = ;" });
    const result = await checkPrimitiveBlocks({ checkoutRoot, copy });
    expect(result.problems.some((problem: string) => problem.startsWith("todo: ") && problem.includes("does not load"))).toBe(true);
    expect(result.problems).toContain("todo TD-ROW-01: threw row check broke");
  });

  it("says so when the checkout defines no block checks for the Sidekick (today's state)", async () => {
    const result = await checkPrimitiveBlocks({ checkoutRoot: repoRoot, copy });
    expect(result.problems).toEqual([]);
    expect(result.notes).toEqual(["no primitive block checks apply to todo"]);
  });
});
