import { describe, expect, it } from "vitest";
import MidasRecordSchema from "../../shell/sdk/record-schema.js";

// The one record validator (shell/sdk/record-schema.js), unified data plan sections 2, 3 and 5:
// JSON Schema per record type, "$type" on every record, JSON Merge Patch for updates. The same
// file runs in the Worker and in the shell's JavaScriptCore, so these fixtures bind both.

const itemSchema = {
  type: "object",
  required: ["title"],
  $defs: {
    instant: { type: "string", format: "date-time" },
  },
  properties: {
    title: { type: "string", minLength: 1, maxLength: 10 },
    at: { $ref: "#/$defs/instant" },
    done: { type: "boolean" },
    count: { type: "integer", minimum: 1, maximum: 5 },
    tags: { type: "array", minItems: 1, uniqueItems: true, items: { type: "string" } },
    every: { type: "string", enum: ["day", "week"] },
    zone: { type: "string", format: "time-zone" },
    day: { type: "string", format: "date" },
    time: { type: "string", format: "wall-time" },
    code: { type: "string", pattern: "^[a-z]{3}$" },
    nested: { type: "object", properties: { deep: { type: "number", exclusiveMinimum: 0 } } },
  },
};

const types = {
  "reminder:": { $type: "reminders.item", schema: itemSchema },
  "reminder:special:": { $type: "reminders.special", schema: { type: "object" } },
  "list:": { $type: "reminders.list", schema: { type: "object", required: ["name"], properties: { name: { type: "string" } } } },
};

describe("validate", () => {
  it("accepts a record that fits and keeps unknown fields out of the question", () => {
    const record = { title: "Call", at: "2026-10-15T09:30:00.000Z", done: false, count: 3, tags: ["a"], extra: { anything: true } };
    expect(MidasRecordSchema.validate(itemSchema, record, "reminders.item")).toBeNull();
  });

  it("names the field and the problem", () => {
    expect(MidasRecordSchema.validate(itemSchema, {}, "reminders.item")).toBe("reminders.item.title is required");
    expect(MidasRecordSchema.validate(itemSchema, { title: "" }, "reminders.item")).toBe("reminders.item.title must not be empty");
    expect(MidasRecordSchema.validate(itemSchema, { title: "x".repeat(11) }, "reminders.item")).toBe("reminders.item.title must be at most 10 characters");
    expect(MidasRecordSchema.validate(itemSchema, { title: 7 }, "reminders.item")).toBe("reminders.item.title must be a string, not a number");
    expect(MidasRecordSchema.validate(itemSchema, { title: "x", done: "yes" }, "reminders.item")).toBe("reminders.item.done must be true or false, not a string");
    expect(MidasRecordSchema.validate(itemSchema, { title: "x", count: 1.5 }, "reminders.item")).toBe("reminders.item.count must be a whole number, not a number");
    expect(MidasRecordSchema.validate(itemSchema, { title: "x", count: 9 }, "reminders.item")).toBe("reminders.item.count must be at most 5");
    expect(MidasRecordSchema.validate(itemSchema, { title: "x", every: "hour" }, "reminders.item")).toBe('reminders.item.every must be one of ["day","week"]');
    expect(MidasRecordSchema.validate(itemSchema, { title: "x", tags: [] }, "reminders.item")).toBe("reminders.item.tags must not be empty");
    expect(MidasRecordSchema.validate(itemSchema, { title: "x", tags: ["a", "a"] }, "reminders.item")).toBe("reminders.item.tags must not repeat an item");
    expect(MidasRecordSchema.validate(itemSchema, { title: "x", tags: ["a", 2] }, "reminders.item")).toBe("reminders.item.tags.1 must be a string, not a number");
    expect(MidasRecordSchema.validate(itemSchema, { title: "x", code: "ABC" }, "reminders.item")).toBe("reminders.item.code must match ^[a-z]{3}$");
    expect(MidasRecordSchema.validate(itemSchema, { title: "x", nested: { deep: 0 } }, "reminders.item")).toBe("reminders.item.nested.deep must be more than 0");
    expect(MidasRecordSchema.validate(itemSchema, "not an object", "reminders.item")).toBe("reminders.item must be an object, not a string");
  });

  it("checks the Midas formats: instants with an offset, dates, wall-clock times, time zones", () => {
    const withAt = (at: unknown) => MidasRecordSchema.validate(itemSchema, { title: "x", at }, "reminders.item");
    expect(withAt("2026-10-15T09:30:00.000Z")).toBeNull();
    expect(withAt("2026-10-15T09:30:00+02:00")).toBeNull();
    expect(withAt("2026-10-15T09:30Z")).toBeNull();
    // Rule 5: no epoch milliseconds, no instant without an offset, no plain date as an instant.
    expect(withAt(1760520600000)).toBe("reminders.item.at must be a string, not a number");
    expect(withAt("2026-10-15T09:30:00")).toContain("reminders.item.at must be an ISO 8601 date and time with an offset");
    expect(withAt("2026-10-15")).toContain("reminders.item.at must be an ISO 8601 date and time with an offset");
    expect(withAt("2026-13-45T09:30:00Z")).toContain("reminders.item.at must be an ISO 8601 date and time with an offset");

    expect(MidasRecordSchema.validate(itemSchema, { title: "x", day: "2026-10-15" }, "reminders.item")).toBeNull();
    expect(MidasRecordSchema.validate(itemSchema, { title: "x", day: "15/10/2026" }, "reminders.item")).toBe("reminders.item.day must be a date like 2026-10-15");
    expect(MidasRecordSchema.validate(itemSchema, { title: "x", time: "09:30" }, "reminders.item")).toBeNull();
    expect(MidasRecordSchema.validate(itemSchema, { title: "x", time: "9:30" }, "reminders.item")).toBe("reminders.item.time must be a time like 09:30");
    expect(MidasRecordSchema.validate(itemSchema, { title: "x", time: "24:00" }, "reminders.item")).toBe("reminders.item.time must be a time like 09:30");
    expect(MidasRecordSchema.validate(itemSchema, { title: "x", zone: "America/New_York" }, "reminders.item")).toBeNull();
    expect(MidasRecordSchema.validate(itemSchema, { title: "x", zone: "Mars/Olympus" }, "reminders.item")).toBe("reminders.item.zone is not a known time zone");
  });

  it("follows $ref into $defs and reports an unknown reference", () => {
    const schema = { type: "object", properties: { a: { $ref: "#/$defs/missing" } }, $defs: {} };
    expect(MidasRecordSchema.validate(schema, { a: 1 }, "t")).toBe("t.a uses an unknown schema reference #/$defs/missing");
  });

  it("supports additionalProperties, anyOf, oneOf, not, if/then and dependentRequired", () => {
    const closed = { type: "object", properties: { a: { type: "string" } }, additionalProperties: false };
    expect(MidasRecordSchema.validate(closed, { a: "x", b: 1 }, "t")).toBe("t.b is not a field of this type");

    const typed = { type: "object", properties: { a: { type: "string" } }, additionalProperties: { type: "number" } };
    expect(MidasRecordSchema.validate(typed, { a: "x", b: 1 }, "t")).toBeNull();
    expect(MidasRecordSchema.validate(typed, { a: "x", b: "no" }, "t")).toBe("t.b must be a number, not a string");

    const either = { anyOf: [{ type: "string" }, { type: "number" }] };
    expect(MidasRecordSchema.validate(either, 3, "t")).toBeNull();
    expect(MidasRecordSchema.validate(either, true, "t")).toBe("t must be a string, not true or false");

    const exactlyOne = { oneOf: [{ type: "number", minimum: 0 }, { type: "number", maximum: 10 }] };
    expect(MidasRecordSchema.validate(exactlyOne, 50, "t")).toBeNull();
    expect(MidasRecordSchema.validate(exactlyOne, 5, "t")).toBe("t fits more than one of its allowed forms");

    const never = { not: { const: "banned" } };
    expect(MidasRecordSchema.validate(never, "banned", "t")).toBe("t is not allowed");
    expect(MidasRecordSchema.validate(never, "fine", "t")).toBeNull();

    const weekdaysOnlyWeekly = {
      type: "object",
      properties: { every: { type: "string" }, weekdays: { type: "array" } },
      if: { required: ["weekdays"] },
      then: { properties: { every: { const: "week" } } },
    };
    expect(MidasRecordSchema.validate(weekdaysOnlyWeekly, { every: "day", weekdays: [1] }, "t")).toBe('t.every must be "week"');
    expect(MidasRecordSchema.validate(weekdaysOnlyWeekly, { every: "day" }, "t")).toBeNull();

    const paired = { type: "object", dependentRequired: { time: ["date"] } };
    expect(MidasRecordSchema.validate(paired, { time: "09:00" }, "t")).toBe("t.date is required with time");
  });
});

describe("types by key prefix", () => {
  it("finds the longest matching prefix", () => {
    expect(MidasRecordSchema.typeForKey(types, "reminder:42")?.$type).toBe("reminders.item");
    expect(MidasRecordSchema.typeForKey(types, "reminder:special:42")?.$type).toBe("reminders.special");
    expect(MidasRecordSchema.typeForKey(types, "list:home")?.$type).toBe("reminders.list");
    expect(MidasRecordSchema.typeForKey(types, "task:42")).toBeNull();
    expect(MidasRecordSchema.typeForKey(undefined, "reminder:42")).toBeNull();
  });

  it("stamps $type first and never changes the given value", () => {
    const value = { title: "Call", $type: "wrong" };
    const stamped = MidasRecordSchema.stampType(types, "reminder:1", value) as Record<string, unknown>;
    expect(Object.keys(stamped)).toEqual(["$type", "title"]);
    expect(stamped.$type).toBe("reminders.item");
    expect(value.$type).toBe("wrong");
    expect(MidasRecordSchema.stampType(types, "task:1", value)).toBe(value);
    expect(MidasRecordSchema.stampType(types, "reminder:1", "text")).toBe("text");
  });

  it("checkRecord refuses a key without a type, a missing or wrong $type, and a record off its schema", () => {
    const good = { $type: "reminders.item", title: "Call" };
    expect(MidasRecordSchema.checkRecord(types, "reminder:1", good)).toBeNull();
    expect(MidasRecordSchema.checkRecord(types, "task:1", good)).toBe("no record type is declared for task:1");
    expect(MidasRecordSchema.checkRecord(types, "reminder:1", { title: "Call" })).toBe('reminders.item.$type must be "reminders.item"');
    expect(MidasRecordSchema.checkRecord(types, "reminder:1", { $type: "reminders.list", title: "Call" })).toBe('reminders.item.$type must be "reminders.item"');
    expect(MidasRecordSchema.checkRecord(types, "reminder:1", { $type: "reminders.item" })).toBe("reminders.item.title is required");
    expect(MidasRecordSchema.checkRecord(types, "reminder:1", "text")).toBe("reminders.item must be an object, not a string");
    // No types block: nothing is checked (a Sidekick version from before schemas).
    expect(MidasRecordSchema.checkRecord(undefined, "task:1", { anything: 1 })).toBeNull();
  });
});

describe("mergePatch (RFC 7396)", () => {
  it("removes null fields, merges objects, replaces everything else, and leaves its inputs alone", () => {
    const target = { title: "Call", snoozedUntil: "2026-10-15T10:00:00Z", repeat: { every: "week", interval: 2 }, tags: ["a"] };
    const patch = { snoozedUntil: null, done: true, repeat: { interval: 3 }, tags: ["b"] };
    const result = MidasRecordSchema.mergePatch(target, patch);
    expect(result).toEqual({ title: "Call", done: true, repeat: { every: "week", interval: 3 }, tags: ["b"] });
    expect(target.snoozedUntil).toBe("2026-10-15T10:00:00Z");
    expect(patch.repeat).toEqual({ interval: 3 });
  });

  it("a non-object patch replaces the target; a patch on a missing target builds it", () => {
    expect(MidasRecordSchema.mergePatch({ a: 1 }, "text")).toBe("text");
    expect(MidasRecordSchema.mergePatch(undefined, { a: { b: 1 }, c: null })).toEqual({ a: { b: 1 } });
  });
});
