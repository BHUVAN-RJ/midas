// How a timed reminder reaches the person: the record field reminderType (founder, 2026-10-24,
// docs/briefs/notification-levels.md §2). Values "normal", "timeSensitive", "alarm"; absent means
// Time Sensitive, so records saved before this change need no migration. Only a reminder with a
// time carries it; the page offers it as Normal / Time Sensitive / Alarm in the Details sheet, and
// jess's reminders.add and reminders.edit take it as an optional argument.
process.env.TZ = "America/Los_Angeles";

import { readFileSync } from "node:fs";
import vm from "node:vm";
import { describe, expect, it } from "vitest";
import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import { inputSchemaProblems, loadToolsScript, sidekickToolsProblems } from "../scripts/sidekick-tools.mjs";

const folder = new URL("../../sidekicks/reminders/", import.meta.url);
const toolsText = readFileSync(new URL("tools.js", folder), "utf8");
const html = readFileSync(new URL("index.html", folder), "utf8");
const manifest = JSON.parse(readFileSync(new URL("manifest.json", folder), "utf8"));
const careManifest = JSON.parse(readFileSync(new URL("../../sidekicks/care-reminders/manifest.json", import.meta.url), "utf8"));

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
  result: { text: string };
};

function loadPageLogic() {
  const scriptMatch = html.match(/<script>([\s\S]*?)<\/script>/);
  if (!scriptMatch) {
    throw new Error("index.html has no inline script");
  }
  const sandbox = { window: { location: { origin: "sidekick://reminders" } }, console, Intl, Date, Math, JSON };
  vm.createContext(sandbox);
  vm.runInContext(scriptMatch[1], sandbox);
  return (sandbox as Record<string, any>).RemindersLogic;
}

const logic = loadPageLogic();

function baseRecords(): Records {
  return [
    // Saved before 2026-10-24: no reminderType
    { key: "reminder:callmom00001", value: { $type: "reminders.item", title: "Call Mom", done: false, timeZone: LA, at: "2026-10-21T01:00:00.000Z", allDay: false, createdAt: "2026-10-10T00:00:00.000Z" } },
    { key: "reminder:flight000001", value: { $type: "reminders.item", title: "Leave for the airport", done: false, timeZone: LA, at: "2026-10-22T12:00:00.000Z", allDay: false, reminderType: "alarm", createdAt: "2026-10-10T00:00:00.000Z" } },
    { key: "reminder:rent00000001", value: { $type: "reminders.item", title: "Pay rent", done: false, timeZone: LA, at: "2026-11-01T16:00:00.000Z", allDay: false, repeat: { every: "month" }, reminderType: "normal", createdAt: "2026-10-01T00:00:00.000Z" } },
    { key: "reminder:allday000001", value: { $type: "reminders.item", title: "Bins out", done: false, timeZone: LA, at: "2026-10-21T16:00:00.000Z", allDay: true, createdAt: "2026-10-10T00:00:00.000Z" } },
    { key: "reminder:undated00001", value: { $type: "reminders.item", title: "Buy stamps", done: false, timeZone: LA, createdAt: "2026-10-10T00:00:00.000Z" } },
  ];
}

function call(verb: string, input: Record<string, unknown>, records: Records = baseRecords()): Outcome {
  const outcome = tools.handlers[verb](input, records, NOW);
  return JSON.parse(JSON.stringify(outcome));
}

function onlySetValue(outcome: Outcome) {
  expect(outcome.refused).toBeUndefined();
  expect(outcome.ops).toHaveLength(1);
  const op = outcome.ops![0];
  expect(op.op).toBe("set");
  const stamped = MidasRecordSchema.stampType(manifest.types, op.key, op.value);
  expect(MidasRecordSchema.checkRecord(manifest.types, op.key, stamped), op.key).toBeNull();
  return op.value!;
}

function expectRefused(outcome: Outcome, reason: string) {
  expect(outcome.refused).toBe(reason);
  expect(outcome.ops).toBeUndefined();
}

function timedWhen() {
  return { date: "2026-10-21", time: "05:00", allDay: false, at: "2026-10-21T12:00:00.000Z", repeat: null, timeZone: LA };
}

function allDayWhen() {
  return { date: "2026-10-21", time: null, allDay: true, at: "2026-10-21T16:00:00.000Z", repeat: null, timeZone: LA };
}

function editInput(fields: Record<string, unknown>) {
  return { title: null, notes: null, when: null, clearDate: false, reminderType: null, ...fields };
}

describe("reminderType in both manifests (record schema)", () => {
  const item = { $type: "reminders.item", title: "Call Mom", done: false, timeZone: LA, at: "2026-10-21T01:00:00.000Z", allDay: false };
  const careItem = { $type: "care.item", title: "Pills", done: false, timeZone: LA, at: "2026-10-21T01:00:00.000Z" };

  it("accepts the three values and no value on a Reminders reminder", () => {
    for (const reminderType of ["normal", "timeSensitive", "alarm"]) {
      expect(MidasRecordSchema.checkRecord(manifest.types, "reminder:a", { ...item, reminderType })).toBeNull();
    }
    expect(MidasRecordSchema.checkRecord(manifest.types, "reminder:a", item)).toBeNull();
  });

  it("refuses any other value on a Reminders reminder", () => {
    expect(MidasRecordSchema.checkRecord(manifest.types, "reminder:a", { ...item, reminderType: "urgent" })).toMatch(/reminderType/);
    expect(MidasRecordSchema.checkRecord(manifest.types, "reminder:a", { ...item, reminderType: true })).toMatch(/reminderType/);
  });

  it("gives Care the same field, values and default (no picker yet)", () => {
    expect(careManifest.types["reminder:"].schema.properties.reminderType).toEqual({ type: "string", enum: ["normal", "timeSensitive", "alarm"] });
    expect(MidasRecordSchema.checkRecord(careManifest.types, "reminder:a", { ...careItem, reminderType: "alarm" })).toBeNull();
    expect(MidasRecordSchema.checkRecord(careManifest.types, "reminder:a", { ...careItem, reminderType: "loud" })).toMatch(/reminderType/);
    expect(MidasRecordSchema.checkRecord(careManifest.types, "reminder:a", careItem)).toBeNull();
  });

  it("is not the record's $type", () => {
    expect(manifest.types["reminder:"].$type).toBe("reminders.item");
    expect(careManifest.types["reminder:"].$type).toBe("care.item");
  });
});

describe("the page's RemindersLogic keeps reminderType only on a reminder with a time", () => {
  it("reads the three values, and none for a record saved before 2026-10-24", () => {
    const records = baseRecords();
    expect(logic.itemFromRecord(records[0].key, records[0].value).reminderType).toBeNull();
    expect(logic.itemFromRecord(records[1].key, records[1].value).reminderType).toBe("alarm");
    expect(logic.itemFromRecord(records[2].key, records[2].value).reminderType).toBe("normal");
    const sensitive = { ...records[0].value, reminderType: "timeSensitive" };
    expect(logic.itemFromRecord(records[0].key, sensitive).reminderType).toBe("timeSensitive");
  });

  it("reads an unknown value as none, and writes it back out", () => {
    const value = { ...baseRecords()[0].value, reminderType: "critical" };
    const item = logic.itemFromRecord("reminder:callmom00001", value);
    expect(item.reminderType).toBeNull();
    expect("reminderType" in logic.recordFromItem(item, value)).toBe(false);
  });

  it("writes the field back unchanged when something else changes", () => {
    const value = baseRecords()[1].value;
    const item = logic.itemFromRecord("reminder:flight000001", value);
    item.title = "Leave for SFO";
    expect(logic.recordFromItem(item, value).reminderType).toBe("alarm");
  });

  it("leaves the field out of a timed reminder without a choice", () => {
    const value = baseRecords()[0].value;
    const item = logic.itemFromRecord("reminder:callmom00001", value);
    expect("reminderType" in logic.recordFromItem(item, value)).toBe(false);
  });

  it("drops it when the time goes (all day) or the date goes", () => {
    const value = baseRecords()[1].value;
    const allDay = logic.itemFromRecord("reminder:flight000001", value);
    allDay.time = null;
    const allDayValue = logic.recordFromItem(allDay, value);
    expect(allDayValue.allDay).toBe(true);
    expect("reminderType" in allDayValue).toBe(false);
    const undated = logic.itemFromRecord("reminder:flight000001", value);
    undated.date = null;
    undated.time = null;
    expect("reminderType" in logic.recordFromItem(undated, value)).toBe(false);
  });

  it("does not read a stored type on an all-day reminder", () => {
    const value = { ...baseRecords()[3].value, reminderType: "alarm" };
    expect(logic.itemFromRecord("reminder:allday000001", value).reminderType).toBeNull();
  });

  it("lists the values in the order the page shows them", () => {
    expect(Array.from(logic.REMINDER_TYPES)).toEqual(["normal", "timeSensitive", "alarm"]);
  });
});

describe("reminders.add takes an optional reminderType", () => {
  it("writes an alarm on a reminder with a time", () => {
    const value = onlySetValue(call("add", { title: "Leave for the airport", notes: null, list: null, when: timedWhen(), reminderType: "alarm" }));
    expect(value.reminderType).toBe("alarm");
    expect(value.at).toBe("2026-10-21T12:00:00.000Z");
  });

  it("writes normal and timeSensitive as said", () => {
    const normal = onlySetValue(call("add", { title: "Call Mom", notes: null, list: null, when: timedWhen(), reminderType: "normal" }));
    expect(normal.reminderType).toBe("normal");
    const sensitive = onlySetValue(call("add", { title: "Call Mom", notes: null, list: null, when: timedWhen(), reminderType: "timeSensitive" }));
    expect(sensitive.reminderType).toBe("timeSensitive");
  });

  it("leaves the field out when not said (null or missing): Time Sensitive by default", () => {
    const saidNull = onlySetValue(call("add", { title: "Call Mom", notes: null, list: null, when: timedWhen(), reminderType: null }));
    expect("reminderType" in saidNull).toBe(false);
    const missing = onlySetValue(call("add", { title: "Call Mom", notes: null, list: null, when: timedWhen() }));
    expect("reminderType" in missing).toBe(false);
  });

  it("refuses a type on a reminder without a time, and writes nothing", () => {
    expectRefused(call("add", { title: "Buy stamps", notes: null, list: null, when: null, reminderType: "alarm" }), "needs-time");
    expectRefused(call("add", { title: "Bins out", notes: null, list: null, when: allDayWhen(), reminderType: "normal" }), "needs-time");
  });

  it("refuses a value the page does not offer", () => {
    expectRefused(call("add", { title: "Call Mom", notes: null, list: null, when: timedWhen(), reminderType: "critical" }), "unknown-reminder-type");
  });
});

describe("reminders.edit takes an optional reminderType", () => {
  it("changes only the type of a timed reminder saved before 2026-10-24", () => {
    const outcome = call("edit", editInput({ item: "Call Mom", reminderType: "alarm" }));
    const value = onlySetValue(outcome);
    expect(value.reminderType).toBe("alarm");
    expect(value.at).toBe("2026-10-21T01:00:00.000Z");
    expect(value.title).toBe("Call Mom");
  });

  it("makes an alarm not time sensitive", () => {
    const value = onlySetValue(call("edit", editInput({ item: "Leave for the airport", reminderType: "normal" })));
    expect(value.reminderType).toBe("normal");
  });

  it("keeps the stored type when another field changes and no type is said", () => {
    const value = onlySetValue(call("edit", editInput({ item: "Pay rent", title: "Pay the rent" })));
    expect(value.reminderType).toBe("normal");
    const moved = onlySetValue(call("edit", editInput({ item: "Leave for the airport", when: { ...timedWhen(), date: "2026-10-23", at: "2026-10-23T12:00:00.000Z" } })));
    expect(moved.reminderType).toBe("alarm");
    expect(moved.at).toBe("2026-10-23T12:00:00.000Z");
  });

  it("drops the type when the date is taken off or the reminder becomes all day", () => {
    const cleared = onlySetValue(call("edit", editInput({ item: "Leave for the airport", clearDate: true })));
    expect("reminderType" in cleared).toBe(false);
    expect("at" in cleared).toBe(false);
    const allDay = onlySetValue(call("edit", editInput({ item: "Leave for the airport", when: allDayWhen() })));
    expect("reminderType" in allDay).toBe(false);
    expect(allDay.allDay).toBe(true);
  });

  it("refuses a type on a reminder without a time", () => {
    expectRefused(call("edit", editInput({ item: "Buy stamps", reminderType: "alarm" })), "needs-time");
    expectRefused(call("edit", editInput({ item: "Bins out", reminderType: "normal" })), "needs-time");
  });

  it("refuses the type it already has as nothing to change", () => {
    expectRefused(call("edit", editInput({ item: "Leave for the airport", reminderType: "alarm" })), "nothing-to-change");
  });

  it("refuses a value the page does not offer", () => {
    expectRefused(call("edit", editInput({ item: "Call Mom", reminderType: "loud" })), "unknown-reminder-type");
  });
});

describe("other tools keep the type", () => {
  it("marking an alarm done and moving it keep reminderType", () => {
    const completed = onlySetValue(call("complete", { item: "Leave for the airport" }));
    expect(completed.reminderType).toBe("alarm");
    expect(completed.done).toBe(true);
    const repeatDone = onlySetValue(call("complete", { item: "Pay rent" }));
    expect(repeatDone.reminderType).toBe("normal");
  });
});

describe("the agent block offers reminderType on add and edit", () => {
  function toolNamed(name: string) {
    for (const tool of manifest.agent.tools) {
      if (tool.name === name) {
        return tool;
      }
    }
    throw new Error("no tool " + name);
  }

  it("passes the deploy gate's tools check", () => {
    expect(sidekickToolsProblems(manifest, toolsText, html, "reminders")).toEqual([]);
  });

  for (const name of ["reminders.add", "reminders.edit"]) {
    it(name + " has a nullable reminderType with the three values, required as strict schemas need", () => {
      const schema = toolNamed(name).inputSchema;
      expect(inputSchemaProblems(schema)).toEqual([]);
      expect(schema.required).toContain("reminderType");
      expect(schema.properties.reminderType.type).toEqual(["string", "null"]);
      expect(schema.properties.reminderType.enum).toEqual(["normal", "timeSensitive", "alarm", null]);
      expect(schema.properties.reminderType.description).toMatch(/alarm/);
      expect(schema.properties.reminderType.description).toMatch(/not time sensitive/);
    });
  }

  it("says the alarm and not time sensitive phrasings in examples and descriptions", () => {
    const examples = manifest.agent.examples.join("\n");
    expect(examples).toMatch(/alarm/i);
    expect(examples).toMatch(/not time sensitive/i);
    expect(toolNamed("reminders.add").description).toMatch(/Normal, Time Sensitive or Alarm/);
    expect(toolNamed("reminders.edit").description).toMatch(/Normal, Time Sensitive or Alarm/);
  });

  it("no other tool takes reminderType", () => {
    for (const tool of manifest.agent.tools) {
      if (tool.name === "reminders.add" || tool.name === "reminders.edit") {
        continue;
      }
      expect(tool.inputSchema.properties.reminderType, tool.name).toBeUndefined();
    }
  });
});

describe("the page's Details sheet offers Normal / Time Sensitive / Alarm on a reminder with a time", () => {
  function functionText(name: string) {
    const start = html.indexOf("  function " + name + "(");
    expect(start, name).toBeGreaterThan(-1);
    const end = html.indexOf("\n  }\n", start);
    return html.slice(start, end);
  }

  it("names the three choices in the brief's words, Time Sensitive shown when none is stored", () => {
    expect(html).toContain("const REMINDER_TYPE_LABELS = { normal: 'Normal', timeSensitive: 'Time Sensitive', alarm: 'Alarm' };");
    expect(functionText("reminderTypeSelectHtml")).toContain("const current = reminderType || 'timeSensitive';");
  });

  it("draws the menu only inside the time row's branch", () => {
    const sheet = functionText("sheetMainHtml");
    const timeBranch = sheet.indexOf("if (draft.time) {");
    const menu = sheet.indexOf("reminderTypeSelectHtml(draft.reminderType)");
    const branchEnd = sheet.indexOf("\n    }\n", timeBranch);
    expect(timeBranch).toBeGreaterThan(-1);
    expect(menu).toBeGreaterThan(timeBranch);
    expect(menu).toBeLessThan(branchEnd);
  });

  it("saves the choice only with a time, and keeps it in what the page compares", () => {
    expect(functionText("closeDetails")).toContain("reminderType: draft.date && draft.time ? draft.reminderType : null,");
    expect(functionText("snapshotFields")).toContain("reminderType: item.reminderType || null");
    expect(functionText("makeUserFieldsChange")).toContain("target.reminderType = target.time ? fields.reminderType || null : null;");
    expect(functionText("applyDetailsChange")).toContain("draft.reminderType = Logic.reminderTypeOf(value);");
  });
});
