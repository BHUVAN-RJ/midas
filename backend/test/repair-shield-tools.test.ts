// The shield's tools check (docs/briefs/repair-lanes.md W1, "Tools before/after"; founder D1 and D3,
// 2026-11-13): every jess tool, run on a copy of the person's records with the old and the new
// tools.js, answers the same unless the request names it; no tool is removed; every tool's page
// control is still on the page. Each case below breaks exactly one of those and must be caught.
import { describe, expect, it } from "vitest";
import { pageOffersAction } from "../scripts/bundle-tools.mjs";
import { sampleInputs } from "../../runner/core-checks/tool-inputs.mjs";
import { answerText, compareTools, loadDeterministicTools } from "../../runner/core-checks/tools-compare.mjs";
import { NOW_ISO, sidekickCopy, todoRecords, withManifest, withToolsAppended, type Copy } from "./repair-shield-fixtures";

const todo = sidekickCopy("todo");
const records = todoRecords();

function prepared(copy: Copy) {
  return { html: copy.html, toolsText: copy.toolsText, manifest: JSON.parse(copy.manifestText) };
}

function compare(after: Copy, requestedTools: string[] = []) {
  return compareTools({ sidekickId: "todo", before: prepared(todo), after: prepared(after), records, requestedTools, nowIso: NOW_ISO, pageOffersAction });
}

describe("shield: tools before and after", () => {
  it("passes an unchanged copy, and the sample calls do real work on the person's records", () => {
    const result = compare(todo);
    expect(result.problems).toEqual([]);
    expect(result.changed).toEqual([]);
    // The check must exercise the handlers, not only collect refusals: ticking "Buy milk" (a real
    // to-do in the records) writes it
    const loaded = loadDeterministicTools(todo.toolsText, NOW_ISO);
    const tool = JSON.parse(todo.manifestText).agent.tools.find((candidate: { name: string }) => candidate.name === "todo.complete");
    const firstCase = sampleInputs({ tool, records, nowIso: NOW_ISO })[0];
    const answer = answerText({ loaded, verb: "complete", input: firstCase.input, records, nowIso: NOW_ISO });
    expect(firstCase.input).toEqual({ item: "Buy milk" });
    expect(answer).toContain('"op":"set"');
    expect(answer).toContain("completedAt");
  });

  it("gives the old and the new code the same clock and the same random ids", () => {
    // todo.add makes its id from the time and Math.random: two loads must agree exactly
    const first = loadDeterministicTools(todo.toolsText, NOW_ISO);
    const second = loadDeterministicTools(todo.toolsText, NOW_ISO);
    const input = { title: "Water plants", notes: null, list: null, someday: null, when: null };
    const firstAnswer = answerText({ loaded: first, verb: "add", input, records, nowIso: NOW_ISO });
    const secondAnswer = answerText({ loaded: second, verb: "add", input, records, nowIso: NOW_ISO });
    expect(firstAnswer).toContain("reminder:");
    expect(secondAnswer).toBe(firstAnswer);
  });

  it("fails a tool whose answer changed when the request does not name it", () => {
    const after = withToolsAppended(todo, "MidasSidekickTools.handlers.complete = function brokenComplete() { return { ops: [], result: { text: 'Done' } }; };");
    const result = compare(after);
    expect(result.problems.length).toBe(1);
    expect(result.problems[0]).toContain("todo.complete answers differently");
    expect(result.problems[0]).toContain("the request does not name it");
    expect(result.changed).toEqual(["todo.complete"]);
  });

  it("lets the named tool change and notes it", () => {
    const after = withToolsAppended(todo, "MidasSidekickTools.handlers.complete = function newComplete() { return { ops: [], result: { text: 'Done' } }; };");
    const result = compare(after, ["todo.complete"]);
    expect(result.problems).toEqual([]);
    expect(result.notes.join(" ")).toContain("todo.complete answers differently");
  });

  it("fails a removed tool (D1: remove means hide)", () => {
    const after = withManifest(todo, (manifest) => {
      manifest.agent.tools = manifest.agent.tools.filter((tool: { name: string }) => tool.name !== "todo.search");
    });
    const result = compare(after);
    expect(result.problems).toContain('todo.search was removed; a feature is hidden by a setting, its tool stays and answers "turned off" (D1)');
  });

  it("fails a tool whose handler is gone from tools.js", () => {
    const after = withToolsAppended(todo, "delete MidasSidekickTools.handlers.restore;");
    const result = compare(after);
    expect(result.problems).toContain('todo.restore: the new tools.js has no handler "restore"');
  });

  it("fails when a tool's page control is gone from the page, even if the manifest drops it too", () => {
    // The button and its handler both renamed: the page no longer offers "go-search" at all
    const pageWithoutSearch = todo.html.split("go-search").join("gone-search");
    const after = withManifest({ ...todo, html: pageWithoutSearch }, (manifest) => {
      const searchTool = manifest.agent.tools.find((tool: { name: string }) => tool.name === "todo.search");
      searchTool._meta["midas/page-actions"] = ["tab"];
    });
    expect(pageOffersAction(todo.html, "go-search")).toBe(true);
    const result = compare(after);
    expect(result.problems).toContain('todo.search: its page control "go-search" was on the page and is gone');
  });

  it("fails a new tools.js that does not run", () => {
    const after = { ...todo, toolsText: "var MidasSidekickTools = ;" };
    const result = compare(after);
    expect(result.problems[0]).toContain("new tools.js does not run");
  });
});
