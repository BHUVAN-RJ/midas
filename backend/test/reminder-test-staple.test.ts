// Staples (user report d84d2d44, 2026-10-27): on a grocery list, a staple checked off stays on its
// list and shows the day it was last bought; anything else checked off leaves the list as before.
// The page's logic is run from the bundle (Node's vm), the voice tools from tools.js, and every
// record written is checked against manifest.json.
process.env.TZ = "America/Los_Angeles";

import { readFileSync } from "node:fs";
import vm from "node:vm";
import { describe, expect, it } from "vitest";
import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import { loadToolsScript } from "../scripts/sidekick-tools.mjs";

const folder = new URL("../../sidekicks/reminder-test/", import.meta.url);
const html = readFileSync(new URL("index.html", folder), "utf8");
const toolsText = readFileSync(new URL("tools.js", folder), "utf8");
const manifest = JSON.parse(readFileSync(new URL("manifest.json", folder), "utf8"));

function loadRemindersLogic() {
  const scriptMatch = html.match(/<script>([\s\S]*?)<\/script>/);
  if (!scriptMatch) {
    throw new Error("index.html has no inline script");
  }
  const sandbox = { window: { location: { origin: "sidekick://reminders" } }, console, Intl, Date, Math, JSON };
  vm.createContext(sandbox);
  vm.runInContext(scriptMatch[1], sandbox);
  return (sandbox as Record<string, any>).RemindersLogic;
}

const logic = loadRemindersLogic();
const loaded = loadToolsScript(toolsText);
if (!("tools" in loaded)) {
  throw new Error(loaded.problem);
}
const tools = loaded.tools;

const LA = "America/Los_Angeles";
const NOW = "2026-10-27T01:30:00.000Z";

function records() {
  return [
    { key: "list:groceries", value: { $type: "reminder-test.list", name: "Groceries", color: "#34C759", icon: "cart", createdAt: "2026-10-02T00:00:00.000Z" } },
    { key: "reminder:milk00000001", value: { $type: "reminder-test.item", title: "Milk", done: false, timeZone: LA, list: "groceries", staple: true, createdAt: "2026-10-10T00:00:00.000Z" } },
    { key: "reminder:basil0000001", value: { $type: "reminder-test.item", title: "Basil", done: false, timeZone: LA, list: "groceries", createdAt: "2026-10-10T00:00:00.000Z" } },
  ];
}

function expectSchemaValid(key: string, value: Record<string, unknown>) {
  const stamped = MidasRecordSchema.stampType(manifest.types, key, value);
  expect(MidasRecordSchema.checkRecord(manifest.types, key, stamped), key).toBeNull();
}

describe("staples", () => {
  it("declares staple and boughtAt on reminder-test.item, both optional", () => {
    const schema = manifest.types["reminder:"].schema;
    expect(schema.properties.staple).toEqual({ type: "boolean" });
    expect(schema.properties.boughtAt).toEqual({ $ref: "#/$defs/instant" });
    expect(schema.required).toEqual(["title"]);
  });

  it("checking off a staple keeps it open and records the day it was bought", () => {
    const item = logic.itemFromRecord("reminder:milk00000001", records()[1].value);
    expect(item.staple).toBe(true);
    logic.markDoneChange("", NOW)(item);
    expect(item.done).toBe(false);
    expect(item.boughtAt).toBe(NOW);
    const value = logic.recordFromItem(item, records()[1].value);
    expect(value.done).toBe(false);
    expect(value.staple).toBe(true);
    expect(value.boughtAt).toBe(NOW);
    expect(value.completedAt).toBeUndefined();
    expectSchemaValid("reminder:milk00000001", value);
    const listed = logic.itemsInList([logic.itemFromRecord("reminder:milk00000001", value)], "groceries", NOW, LA);
    expect(listed).toHaveLength(1);
  });

  it("checking off anything else still completes it and takes it off the list", () => {
    const item = logic.itemFromRecord("reminder:basil0000001", records()[2].value);
    logic.markDoneChange("", NOW)(item);
    expect(item.done).toBe(true);
    const value = logic.recordFromItem(item, records()[2].value);
    expect("staple" in value).toBe(false);
    expect("boughtAt" in value).toBe(false);
    expect(logic.itemsInList([logic.itemFromRecord("reminder:basil0000001", value)], "groceries", NOW, LA)).toHaveLength(0);
  });

  it("offers a Staple switch in Details and shows the day bought", () => {
    expect(html).toContain("'Staple'");
    expect(html).toContain("det-toggle-staple");
    expect(html).toContain("'<span data-role=\"bought\">Bought '");
  });

  it("by voice, completing a staple writes the bought day and keeps it open", () => {
    const outcome = JSON.parse(JSON.stringify(tools.handlers.complete({ item: "Milk" }, records(), NOW)));
    expect(outcome.refused).toBeUndefined();
    expect(outcome.result.text).toBe("Bought Milk");
    const value = outcome.ops[0].value;
    expect(value.done).toBe(false);
    expect(value.boughtAt).toBe(NOW);
    expectSchemaValid(outcome.ops[0].key, value);
    const other = JSON.parse(JSON.stringify(tools.handlers.complete({ item: "Basil" }, records(), NOW)));
    expect(other.result.text).toBe("Marked done: Basil");
    expect(other.ops[0].value.done).toBe(true);
  });

  it("by voice, edit makes a reminder a staple or not", () => {
    const base = { title: null, notes: null, when: null, clearDate: false };
    const made = JSON.parse(JSON.stringify(tools.handlers.edit({ ...base, item: "Basil", staple: true }, records(), NOW)));
    expect(made.refused).toBeUndefined();
    expect(made.ops[0].value.staple).toBe(true);
    expectSchemaValid(made.ops[0].key, made.ops[0].value);
    const unmade = JSON.parse(JSON.stringify(tools.handlers.edit({ ...base, item: "Milk", staple: false }, records(), NOW)));
    expect("staple" in unmade.ops[0].value).toBe(false);
    const same = tools.handlers.edit({ ...base, item: "Milk", staple: true }, records(), NOW);
    expect(same.refused).toBe("nothing-to-change");
    const editTool = manifest.agent.tools.find((tool: { name: string }) => tool.name === "reminder-test.edit");
    expect(editTool.inputSchema.required).toContain("staple");
  });
});
