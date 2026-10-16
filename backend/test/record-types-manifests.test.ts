import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import MidasShellTypes from "../../shell/sdk/shell-types.js";
import { SHELL_TYPE_PREFIXES, sidekickNamespaces, typesBlockProblems, validateManifest } from "../scripts/bundle-tools.mjs";

// Schemas live inside each Sidekick's manifest.json (founder, 2026-10-15). Fixtures for every
// type in both manifests and for the shell's own types (plan section 10, "schema fixtures for
// every type and every old shape").

function readManifest(sidekickId: string) {
  const manifestURL = new URL(`../../sidekicks/${sidekickId}/manifest.json`, import.meta.url);
  return JSON.parse(readFileSync(manifestURL, "utf8"));
}

const remindersManifest = readManifest("reminders");
const careManifest = readManifest("care-reminders");

function check(manifest: { types: unknown }, key: string, value: unknown) {
  return MidasRecordSchema.checkRecord(manifest.types, key, value);
}

describe("the manifests declare their types", () => {
  it("both manifests pass the deploy gate with their types blocks", () => {
    expect(validateManifest(remindersManifest, "reminders")).toEqual([]);
    expect(validateManifest(careManifest, "care-reminders")).toEqual([]);
  });

  it("names the types of plan section 4", () => {
    const remindersTypeNames = Object.values(remindersManifest.types as Record<string, { $type: string }>).map(typeNameOf);
    expect(remindersTypeNames).toEqual(["reminders.item", "reminders.list", "reminders.history", "reminders.settings", "reminders.import"]);
    const careTypeNames = Object.values(careManifest.types as Record<string, { $type: string }>).map(typeNameOf);
    expect(careTypeNames).toEqual(["care.item", "care.list", "care.settings"]);
  });

  it("the shell prefixes bundle-tools knows are exactly the shell types", () => {
    expect(SHELL_TYPE_PREFIXES).toEqual(Object.keys(MidasShellTypes));
    expect(sidekickNamespaces("care-reminders")).toEqual(["care-reminders", "care"]);
    expect(sidekickNamespaces("reminders")).toEqual(["reminders"]);
  });
});

function typeNameOf(entry: { $type: string }) {
  return entry.$type;
}

describe("types block gate", () => {
  const goodSchema = { type: "object" };

  it("refuses a shell prefix, a foreign namespace, a repeated type name, a non-object schema and a bad prefix", () => {
    expect(typesBlockProblems({ "widget:": { $type: "reminders.widget", schema: goodSchema } }, "reminders")).toEqual([
      'types: "widget:" is a shell type and cannot be redeclared',
    ]);
    expect(typesBlockProblems({ "note:": { $type: "notes.note", schema: goodSchema } }, "reminders")).toEqual([
      'types["note:"].$type must start with "reminders."',
    ]);
    expect(typesBlockProblems({ "a:": { $type: "reminders.x", schema: goodSchema }, "b:": { $type: "reminders.x", schema: goodSchema } }, "reminders")).toEqual([
      'types["b:"].$type "reminders.x" is used by another prefix',
    ]);
    expect(typesBlockProblems({ "a:": { $type: "reminders.x", schema: { type: "string" } } }, "reminders")).toEqual([
      'types["a:"].schema must be a JSON Schema with "type": "object"',
    ]);
    expect(typesBlockProblems({ reminder: { $type: "reminders.x", schema: goodSchema } }, "reminders")).toEqual([
      'types: "reminder" must be a key prefix like "reminder:"',
    ]);
    expect(typesBlockProblems({ "a:": { $type: "Reminders.X", schema: goodSchema } }, "reminders")).toEqual([
      'types["a:"].$type must be <sidekick>.<name>, like "reminders.item"',
    ]);
    expect(typesBlockProblems([], "reminders")).toEqual(["types must be an object of key prefixes"]);
  });

  it("a manifest with a bad types block fails validateManifest", () => {
    const manifest = { ...remindersManifest, types: { "task:": { $type: "reminders.task", schema: "no" } } };
    expect(validateManifest(manifest, "reminders")).toEqual(['types["task:"].schema must be a JSON Schema with "type": "object"']);
  });
});

describe("reminders fixtures", () => {
  const dated = {
    $type: "reminders.item",
    title: "Dentist",
    notes: "Bring the card",
    list: "l1",
    done: false,
    timeZone: "America/New_York",
    at: "2026-10-14T16:30:00.000Z",
    allDay: false,
    repeat: { every: "week", interval: 2, weekdays: [1, 3] },
    snoozedUntil: "2026-10-14T16:40:00.000Z",
    doneThrough: "2026-10-07T16:30:00.000Z",
    lastDoneAt: "2026-10-07T16:31:00.000Z",
    createdAt: "2026-10-01T09:00:00.000Z",
    source: { kind: "apple-reminders", externalId: "x-apple-123" },
    image: "file:abc123",
    somethingNew: { kept: true },
  };

  it("accepts a dated item, an undated item (same type, no at) and a done item", () => {
    expect(check(remindersManifest, "reminder:a1", dated)).toBeNull();
    expect(check(remindersManifest, "reminder:a2", { $type: "reminders.item", title: "Buy milk", done: false, timeZone: "UTC" })).toBeNull();
    expect(check(remindersManifest, "reminder:a3", { $type: "reminders.item", title: "Paid", done: true, completedAt: "2026-10-14T16:30:00.000Z" })).toBeNull();
  });

  it("refuses the old shapes: task: keys, epoch milliseconds, null list, bad repeat", () => {
    expect(check(remindersManifest, "task:a2", { $type: "reminders.item", title: "Buy milk" })).toBe("no record type is declared for task:a2");
    expect(check(remindersManifest, "reminder:a1", { ...dated, at: 1760459400000 })).toBe("reminders.item.at must be a string, not a number");
    expect(check(remindersManifest, "reminder:a1", { ...dated, list: null })).toBe("reminders.item.list must be a string, not null");
    expect(check(remindersManifest, "reminder:a1", { ...dated, snoozedUntil: null })).toBe("reminders.item.snoozedUntil must be a string, not null");
    expect(check(remindersManifest, "reminder:a1", { ...dated, repeat: { every: "hour" } })).toBe('reminders.item.repeat.every must be one of ["day","week","month","year"]');
    expect(check(remindersManifest, "reminder:a1", { ...dated, repeat: { every: "week", weekdays: [7] } })).toBe("reminders.item.repeat.weekdays.0 must be at most 6");
    expect(check(remindersManifest, "reminder:a1", { ...dated, title: "" })).toBe("reminders.item.title must not be empty");
    expect(check(remindersManifest, "reminder:a1", { ...dated, timeZone: "Nowhere/Land" })).toBe("reminders.item.timeZone is not a known time zone");
    expect(check(remindersManifest, "reminder:a1", { ...dated, image: "data:image/png;base64,AAAA" })).toBe("reminders.item.image must match ^file:[A-Za-z0-9_-]{1,64}$");
  });

  it("lists, history, settings and import parts", () => {
    expect(check(remindersManifest, "list:l1", { $type: "reminders.list", name: "Home", color: "#007AFF", icon: "list", createdAt: "2026-10-01T09:00:00.000Z" })).toBeNull();
    expect(check(remindersManifest, "list:l1", { $type: "reminders.list", color: "#007AFF" })).toBe("reminders.list.name is required");
    expect(check(remindersManifest, "history:0000", { $type: "reminders.history", items: [{ id: "x", title: "Done" }] })).toBeNull();
    expect(check(remindersManifest, "history:0000", { $type: "reminders.history", items: "none" })).toBe("reminders.history.items must be a list, not a string");
    expect(check(remindersManifest, "settings:self", { $type: "reminders.settings", order: ["today", "l1"] })).toBeNull();
    expect(check(remindersManifest, "settings:self", { $type: "reminders.settings", order: [1] })).toBe("reminders.settings.order.0 must be a string, not a number");
    const part = { $type: "reminders.import", source: "apple-reminders", origin: "iphone", exportedAt: "2026-10-10T21:30:00-07:00", timeZone: "America/Los_Angeles", part: 0, parts: 2, lists: [{ id: "a" }], reminders: [] };
    expect(check(remindersManifest, "import:req1:0000", part)).toBeNull();
    expect(check(remindersManifest, "import:req1:0000", { ...part, parts: 0 })).toBe("reminders.import.parts must be at least 1");
  });
});

describe("care-reminders fixtures", () => {
  const item = {
    $type: "care.item",
    title: "Blood pressure pill",
    at: "2026-10-15T08:00:00.000Z",
    timeZone: "Asia/Kolkata",
    done: false,
    list: "medicine",
    repeat: { every: "day" },
    everyHours: 4,
    alerts: [{ id: "r1", kind: "daysBefore", days: 1, time: "18:00" }, { id: "r3", kind: "before", minutes: 60 }],
    alertsDone: ["r1"],
    slotsDone: { "12:00": "2026-10-15T12:01:00.000Z" },
    createdAt: "2026-10-01T09:00:00.000Z",
  };

  it("accepts an item with early alerts and an hourly repeat as fields", () => {
    expect(check(careManifest, "reminder:i1", item)).toBeNull();
    expect(check(careManifest, "reminder:i1", { $type: "care.item", title: "Dentist", at: "2026-10-20T10:00:00+05:30" })).toBeNull();
  });

  it("refuses the retired shapes and bad fields", () => {
    // ~ruleId and @HHMM records are retired: they would still match reminder:, but the
    // page no longer writes them; an item needs its own time.
    expect(check(careManifest, "reminder:i1", { $type: "care.item", title: "x" })).toBe("care.item.at is required");
    expect(check(careManifest, "reminder:i1", { ...item, everyHours: 5 })).toBe("care.item.everyHours must be one of [2,3,4]");
    expect(check(careManifest, "reminder:i1", { ...item, alerts: [{ id: "r1", kind: "before", time: "6pm" }] })).toBe("care.item.alerts.0.time must be a time like 09:30");
    expect(check(careManifest, "reminder:i1", { ...item, alerts: [{ kind: "before" }] })).toBe("care.item.alerts.0.id is required");
    expect(check(careManifest, "reminder:i1", { ...item, at: 1760515200000 })).toBe("care.item.at must be a string, not a number");
    expect(check(careManifest, "reminder:i1", { ...item, slotsDone: { "12:00": "noon" } })).toContain("care.item.slotsDone.12:00 must be an ISO 8601");
  });

  it("lists with alert rules and the seeded marker", () => {
    const list = { $type: "care.list", name: "Appointments", icon: "stethoscope", color: "charcoal", order: 1, createdAt: "2026-10-01T09:00:00.000Z", alerts: [{ id: "r1", kind: "daysBefore", days: 1, time: "18:00" }] };
    expect(check(careManifest, "list:appointments", list)).toBeNull();
    expect(check(careManifest, "list:appointments", { ...list, alerts: [{ id: "r1", kind: "daysBefore", days: 30 }] })).toBe("care.list.alerts.0.days must be at most 14");
    expect(check(careManifest, "settings:seeded", { $type: "care.settings", at: "2026-10-01T09:00:00.000Z" })).toBeNull();
    expect(check(careManifest, "settings:seeded", { $type: "care.settings", at: "yesterday" })).toContain("care.settings.at must be an ISO 8601");
  });
});

describe("shell types", () => {
  it("widget: and request: are checked the same way in every Sidekick", () => {
    expect(MidasRecordSchema.checkRecord(MidasShellTypes, "widget:meds", { $type: "midas.widget", version: 1, name: "Meds today", small: { vstack: [] } })).toBeNull();
    expect(MidasRecordSchema.checkRecord(MidasShellTypes, "widget:meds", { $type: "midas.widget", small: {} })).toBe("midas.widget.name is required");
    expect(MidasRecordSchema.checkRecord(MidasShellTypes, "widget:meds", { $type: "midas.widget", name: "x".repeat(41) })).toBe("midas.widget.name must be at most 40 characters");
    expect(MidasRecordSchema.checkRecord(MidasShellTypes, "request:r1", { $type: "midas.request", kind: "import.apple-reminders", status: "pending", createdAt: "2026-10-10T21:30:00.000Z" })).toBeNull();
    expect(MidasRecordSchema.checkRecord(MidasShellTypes, "request:r1", { $type: "midas.request", kind: "import.apple-reminders", status: "done", finishedAt: "2026-10-10T21:30:00-07:00", parts: 2, prefix: "import:r1:", lists: 3, reminders: 40 })).toBeNull();
    expect(MidasRecordSchema.checkRecord(MidasShellTypes, "request:r1", { $type: "midas.request", status: "pending" })).toBe("midas.request.kind is required");
    expect(MidasRecordSchema.checkRecord(MidasShellTypes, "request:r1", { kind: "x" })).toBe('midas.request.$type must be "midas.request"');
  });
});
