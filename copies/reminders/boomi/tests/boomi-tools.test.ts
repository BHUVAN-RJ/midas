// Boomi's copy of Reminders (founder, 2026-10-25): no lists, so no move, create_list or move_list
// tool, and add takes no list. Travels with the copy and runs where the repair runner runs it: the
// copy's page at sidekicks/reminders/ (copies/reminders/boomi/ in the repo, staged by
// backend/scripts/stage-user-copy.mjs). Replaces the base reminders-tools.test.ts for this copy.
process.env.TZ = "America/Los_Angeles";

import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import { loadToolsScript, sidekickToolsProblems } from "../scripts/sidekick-tools.mjs";

const folder = new URL("../../sidekicks/reminders/", import.meta.url);
const toolsText = readFileSync(new URL("tools.js", folder), "utf8");
const html = readFileSync(new URL("index.html", folder), "utf8");
const manifest = JSON.parse(readFileSync(new URL("manifest.json", folder), "utf8"));

const loaded = loadToolsScript(toolsText);
if (!("tools" in loaded)) {
  throw new Error(loaded.problem);
}
const tools = loaded.tools;

const LA = "America/Los_Angeles";
// Tuesday Oct 20, 2026, 10:00 in Los Angeles
const NOW = "2026-10-20T17:00:00.000Z";

type Records = Array<{ key: string; value: Record<string, unknown> }>;
type Outcome = {
  ops?: Array<{ op: string; key: string; value?: Record<string, unknown> }>;
  refused?: string;
  result: { text: string; at?: string | null; allDay?: boolean };
};

function boomiRecords(): Records {
  return [
    { key: "reminder:callmom00001", value: { $type: "reminders.item", title: "Call Mom", done: false, timeZone: LA, at: "2026-10-21T01:00:00.000Z", allDay: false, createdAt: "2026-10-10T00:00:00.000Z" } },
    { key: "reminder:gym000000001", value: { $type: "reminders.item", title: "Gym", done: false, timeZone: LA, at: "2026-10-01T00:00:00.000Z", allDay: false, repeat: { every: "day" }, createdAt: "2026-10-01T00:00:00.000Z" } },
  ];
}

function callTool(verb: string, input: Record<string, unknown>, records: Records = boomiRecords()): Outcome {
  const outcome = tools.handlers[verb](input, records, NOW);
  return JSON.parse(JSON.stringify(outcome));
}

// The shell's write gate: each set must fit its key's type in manifest.json
function expectSchemaValid(outcome: Outcome) {
  expect(outcome.refused).toBeUndefined();
  for (const op of outcome.ops || []) {
    if (op.op === "set") {
      const stamped = MidasRecordSchema.stampType(manifest.types, op.key, op.value);
      expect(MidasRecordSchema.checkRecord(manifest.types, op.key, stamped), op.key).toBeNull();
    }
  }
}

function toolNamed(name: string) {
  for (const tool of manifest.agent.tools) {
    if (tool.name === name) {
      return tool;
    }
  }
  return null;
}

describe("Boomi's Reminders tools: the files agree", () => {
  it("passes the deploy gate's tools check (agent block, handlers, copied page code)", () => {
    expect(sidekickToolsProblems(manifest, toolsText, html, "reminders")).toEqual([]);
  });

  it("has only the reminder tools: no move, create_list or move_list", () => {
    const verbs: string[] = [];
    for (const tool of manifest.agent.tools) {
      verbs.push(tool.name.slice("reminders.".length));
    }
    expect(verbs.sort()).toEqual(["add", "complete", "delete", "edit", "uncomplete"]);
    expect(Object.keys(tools.handlers).sort()).toEqual(verbs.sort());
  });

  it("never tells jess about lists in its rules or examples", () => {
    const told = [manifest.agent.description].concat(manifest.agent.examples).join("\n");
    expect(told).not.toMatch(/\bto groceries\b|\blist called\b|\bmy \w+ list\b/i);
    expect(manifest.agent.rules.join("\n")).toContain("There are no lists");
  });

  it("carries the page's RemindersLogic character for character", () => {
    const start = html.indexOf("var RemindersLogic = (function createRemindersLogic() {");
    const end = html.indexOf("\n})();\n", start);
    const pageLogic = html.slice(start, end + "\n})();\n".length);
    expect(pageLogic).toContain("function todayWithMissed(");
    expect(toolsText.includes(pageLogic)).toBe(true);
  });
});

describe("Boomi's reminders.add", () => {
  it("takes no list field", () => {
    const add = toolNamed("reminders.add");
    expect(add.inputSchema.properties.list).toBeUndefined();
    expect(add.inputSchema.required).not.toContain("list");
  });

  it("adds a reminder outside any list, even when given a list name", () => {
    const outcome = callTool("add", { title: "Bananas", notes: null, list: "groceries", when: null });
    expectSchemaValid(outcome);
    expect(outcome.ops).toHaveLength(1);
    const written = outcome.ops![0].value!;
    expect(written.list).toBeUndefined();
    expect(written.title).toBe("Bananas");
    expect(outcome.result.text).toBe("Added Bananas");
  });

  it("dates it from the worked-out when", () => {
    const at = "2026-10-21T19:00:00.000Z";
    const when = { date: "2026-10-21", time: "12:00", allDay: false, at: at, repeat: null, timeZone: LA };
    const outcome = callTool("add", { title: "Dentist", notes: null, when: when, reminderType: null });
    expectSchemaValid(outcome);
    expect(outcome.ops![0].value!.at).toBe(at);
  });
});

describe("Boomi's other tools still work", () => {
  it("completes, changes and deletes a reminder", () => {
    const completed = callTool("complete", { item: "Call Mom" });
    expectSchemaValid(completed);
    expect(completed.ops![0].value!.done).toBe(true);

    const deleted = callTool("delete", { item: "Call Mom" });
    expect(deleted.ops).toEqual([{ op: "delete", key: "reminder:callmom00001" }]);
  });
});
