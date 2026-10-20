// OLD RECORD SHAPES ARE ALLOWED HERE ONLY: this file tests the upgrade-on-read converter
// (backend/scripts/record-upgrades.mjs) and the migration (backend/scripts/migrate-records.mjs),
// so its fixtures hold the record formats used before the unified data format (founder,
// 2026-10-20). Their description lives only in docs/legacy/LEGACY-RECORD-FORMATS.DO-NOT-READ.md
// (do not read it); never copy these fixtures into other tests.

import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import { insertStatements, planMigration } from "../scripts/migrate-records.mjs";
import {
  cleanCareRule,
  instantText,
  itemCount,
  migrationOpId,
  recordsAfter,
  replayOps,
  typesFor,
  upgradeSidekickRecords,
} from "../scripts/record-upgrades.mjs";

// Moving existing data (unified data plan, section 8): every old shape in the 2026-10-13
// inventory becomes today's shape through new ops only, nothing lost, every result passing the
// manifest schemas, and running it twice changes nothing.

function readManifest(sidekickId: string) {
  return JSON.parse(readFileSync(new URL(`../../sidekicks/${sidekickId}/manifest.json`, import.meta.url), "utf8"));
}

const remindersManifest = readManifest("reminders");
const careManifest = readManifest("care-reminders");

function sha256Hex(text: string) {
  return createHash("sha256").update(text).digest("hex");
}

function valueOf(plan: { writes: Array<{ key: string; value: unknown }> }, key: string) {
  const write = plan.writes.find((candidate) => candidate.key === key);
  return write?.value as Record<string, unknown> | undefined;
}

function expectEveryWriteFits(plan: { writes: Array<{ key: string; value: unknown }> }, manifest: unknown) {
  const types = typesFor(manifest as { types?: unknown });
  for (const write of plan.writes) {
    expect(MidasRecordSchema.checkRecord(types, write.key, write.value), `${write.key} does not fit`).toBeNull();
  }
}

describe("reminders records", () => {
  const oldRecords = [
    { key: "task:milk", value: { title: "Milk", body: "2 litres", list: null, done: false, timeZone: "America/Los_Angeles", createdAt: 1760000000000 } },
    { key: "reminder:dentist", value: { title: "Dentist", notes: "Bring the card", body: "Bring the card", list: "health", done: false, timeZone: "America/Los_Angeles", at: 1760515200000, allDay: false, repeat: { every: "week", interval: 2, until: 1792000000000 }, snoozedUntil: 1760518800000, lastDoneAt: "2026-10-08T03:00:00.000Z" } },
    { key: "reminder:done", value: { title: "Paid", done: true, completedAt: "2026-10-10T10:00:00.000Z", timeZone: "UTC", list: null } },
    { key: "list:health", value: { name: "Health", color: "#FF3B30", icon: "list", source: null, createdAt: "2026-10-01T00:00:00.000Z" } },
    { key: "history:0000", value: { items: [{ id: "h1", title: "Old", done: true, date: null }] } },
    { key: "settings:sidebar", value: { order: ["today", "health"] } },
    { key: "import:req1:0000", value: { source: "apple-reminders", origin: "iphone", exportedAt: "2026-10-10T21:30:00-07:00", timeZone: "America/Los_Angeles", part: 0, parts: 1, lists: [], reminders: [] } },
    { key: "request:req1", value: { kind: "import.apple-reminders", status: "done", createdAt: "2026-10-10T21:29:00.000Z", finishedAt: "2026-10-10T21:30:00-07:00", parts: 1, prefix: "import:req1:", lists: 0, reminders: 0 } },
    { key: "widget:today", value: { version: 1, name: "Today", small: { text: "x" } } },
  ];

  it("folds task: into reminder:, drops body, writes instants as text, leaves nulls out, stamps $type", () => {
    const plan = upgradeSidekickRecords("reminders", oldRecords, remindersManifest);
    expect(plan.problems).toEqual([]);
    expect(plan.deletes).toEqual(["task:milk", "settings:sidebar"]);
    expectEveryWriteFits(plan, remindersManifest);

    const milk = valueOf(plan, "reminder:milk");
    expect(milk).toEqual({ $type: "reminders.item", title: "Milk", notes: "2 litres", done: false, timeZone: "America/Los_Angeles", createdAt: "2025-10-09T08:53:20.000Z" });
    const dentist = valueOf(plan, "reminder:dentist");
    expect(dentist?.body).toBeUndefined();
    expect(dentist?.notes).toBe("Bring the card");
    expect(dentist?.at).toBe("2025-10-15T08:00:00.000Z");
    expect(dentist?.snoozedUntil).toBe("2025-10-15T09:00:00.000Z");
    expect((dentist?.repeat as Record<string, unknown>).until).toBe("2026-10-14T17:46:40.000Z");
    expect(dentist?.lastDoneAt).toBe("2026-10-08T03:00:00.000Z");
    expect(valueOf(plan, "reminder:done")).toEqual({ $type: "reminders.item", title: "Paid", done: true, completedAt: "2026-10-10T10:00:00.000Z", timeZone: "UTC" });
    expect(valueOf(plan, "list:health")).toEqual({ $type: "reminders.list", name: "Health", color: "#FF3B30", icon: "list", createdAt: "2026-10-01T00:00:00.000Z" });
    expect(valueOf(plan, "history:0000")?.$type).toBe("reminders.history");
    expect(valueOf(plan, "settings:self")).toEqual({ $type: "reminders.settings", order: ["today", "health"] });
    expect(valueOf(plan, "import:req1:0000")?.$type).toBe("reminders.import");
    expect(valueOf(plan, "request:req1")?.$type).toBe("midas.request");
    expect(valueOf(plan, "widget:today")?.$type).toBe("midas.widget");
    expect(plan.writes).toHaveLength(9);
  });

  it("loses no item and changes nothing the second time", () => {
    const plan = upgradeSidekickRecords("reminders", oldRecords, remindersManifest);
    const after = recordsAfter(oldRecords, plan);
    expect(itemCount(oldRecords)).toBe(3);
    expect(itemCount(after)).toBe(3);
    const secondPlan = upgradeSidekickRecords("reminders", after, remindersManifest);
    expect(secondPlan.writes).toEqual([]);
    expect(secondPlan.deletes).toEqual([]);
    expect(secondPlan.unchanged).toBe(after.length);
  });

  it("keeps the reminder: record when both task: and reminder: exist for one id, and still retires task:", () => {
    const both = [
      { key: "task:x", value: { title: "Old undated" } },
      { key: "reminder:x", value: { $type: "reminders.item", title: "Newer dated", at: "2026-10-15T08:00:00.000Z" } },
    ];
    const plan = upgradeSidekickRecords("reminders", both, remindersManifest);
    expect(plan.deletes).toEqual(["task:x"]);
    expect(plan.writes).toEqual([]);
    expect(plan.unchanged).toBe(1);
  });

  it("reports a record that cannot pass its schema instead of writing it", () => {
    const plan = upgradeSidekickRecords("reminders", [{ key: "reminder:bad", value: { title: "", at: "2026-10-15T08:00:00.000Z" } }], remindersManifest);
    expect(plan.writes).toEqual([]);
    expect(plan.problems).toEqual([{ key: "reminder:bad", problem: "reminders.item.title must not be empty" }]);
  });
});

describe("care-reminders records", () => {
  const oldRecords = [
    { key: "list:appointments", value: { name: "Appointments", icon: "stethoscope", color: "charcoal", order: 0, createdAt: "2026-10-12T00:00:00.000Z", alerts: [{ id: "r1", kind: "daysBefore", days: 1, time: "18:00", text: null }, { id: "r3", kind: "before", minutes: 60, text: "Soon: {title}" }] } },
    { key: "list:medicine", value: { name: "Medicine", icon: "pill", color: "butter", order: 1, createdAt: "2026-10-12T00:00:00.000Z", alerts: [] } },
    { key: "reminder:dentist", value: { kind: "care-item", at: "2026-10-20T20:00:00.000Z", title: "Dentist", body: "", timeZone: "America/Los_Angeles", done: false, list: "appointments", icon: "tooth", seriesId: "s1", alertRules: [], createdAt: 1760000000000 } },
    { key: "reminder:dentist~r1", value: { kind: "care-alert", at: "2026-10-20T01:00:00.000Z", title: "Dentist tomorrow at 1:00 PM", body: "", timeZone: "America/Los_Angeles", done: true, alertOf: "dentist", rule: "r1", occurrenceAt: "2026-10-20T20:00:00.000Z", lastDoneAt: "2026-10-20T01:02:00.000Z" } },
    { key: "reminder:dentist~r3", value: { kind: "care-alert", at: "2026-10-20T19:00:00.000Z", title: "Soon: Dentist", body: "", timeZone: "America/Los_Angeles", done: false, alertOf: "dentist", rule: "r3", occurrenceAt: "2026-10-20T20:00:00.000Z" } },
    { key: "reminder:pills", value: { kind: "care-item", at: "2026-10-12T15:00:00.000Z", title: "Pills", body: "", timeZone: "America/Los_Angeles", done: false, list: "medicine", repeat: { every: "day" }, everyHours: 4 } },
    { key: "reminder:pills@1200", value: { kind: "care-slot", at: "2026-10-12T19:00:00.000Z", title: "Pills", body: "", timeZone: "America/Los_Angeles", done: false, repeat: { every: "day" }, slotOf: "pills", time: "12:00", lastDoneAt: "2026-10-14T19:03:00.000Z" } },
    { key: "reminder:pills@1600", value: { kind: "care-slot", at: "2026-10-12T23:00:00.000Z", title: "Pills", body: "", timeZone: "America/Los_Angeles", done: false, repeat: { every: "day" }, slotOf: "pills", time: "16:00" } },
    { key: "reminder:walk", value: { kind: "care-item", at: "2026-10-01T15:00:00.000Z", title: "Walk", body: "", timeZone: "America/Los_Angeles", done: false, list: "appointments", repeat: { every: "day" }, doneThrough: "2026-10-13T15:00:00.000Z" } },
    { key: "reminder:walk~r1", value: { kind: "care-alert", at: "2026-10-15T01:00:00.000Z", title: "Walk tomorrow", body: "", timeZone: "America/Los_Angeles", done: true, alertOf: "walk", rule: "r1", occurrenceAt: "2026-10-15T15:00:00.000Z" } },
    { key: "settings:seeded", value: { at: "2026-10-12T00:00:00.000Z" } },
  ];

  it("folds alert and time records into their items, copies the list's rules, retires the old fields", () => {
    const plan = upgradeSidekickRecords("care-reminders", oldRecords, careManifest);
    expect(plan.problems).toEqual([]);
    expect(plan.deletes.sort()).toEqual(["reminder:dentist~r1", "reminder:dentist~r3", "reminder:pills@1200", "reminder:pills@1600", "reminder:walk~r1"]);
    expectEveryWriteFits(plan, careManifest);

    const dentist = valueOf(plan, "reminder:dentist");
    expect(dentist).toEqual({
      $type: "care.item", at: "2026-10-20T20:00:00.000Z", title: "Dentist", timeZone: "America/Los_Angeles", list: "appointments",
      done: true, completedAt: "2026-10-20T01:02:00.000Z", createdAt: "2025-10-09T08:53:20.000Z",
      alerts: [{ id: "r1", kind: "daysBefore", days: 1, time: "18:00" }, { id: "r3", kind: "before", minutes: 60, text: "Soon: {title}" }],
    });
    const pills = valueOf(plan, "reminder:pills");
    expect(pills).toEqual({
      $type: "care.item", at: "2026-10-12T15:00:00.000Z", title: "Pills", timeZone: "America/Los_Angeles", done: false, list: "medicine",
      repeat: { every: "day" }, everyHours: 4, slotsDone: { "12:00": "2026-10-14T19:03:00.000Z" },
    });
    const walk = valueOf(plan, "reminder:walk");
    expect(walk?.doneThrough).toBe("2026-10-15T15:00:00.000Z");
    expect(walk?.done).toBe(false);
    expect(walk?.alerts).toEqual([{ id: "r1", kind: "daysBefore", days: 1, time: "18:00" }, { id: "r3", kind: "before", minutes: 60, text: "Soon: {title}" }]);
    const appointments = valueOf(plan, "list:appointments");
    expect(appointments?.$type).toBe("care.list");
    expect((appointments?.alerts as Array<Record<string, unknown>>)[0]).toEqual({ id: "r1", kind: "daysBefore", days: 1, time: "18:00" });
    expect(valueOf(plan, "settings:seeded")).toEqual({ $type: "care.settings", at: "2026-10-12T00:00:00.000Z" });
  });

  it("loses no item and is quiet the second time", () => {
    const plan = upgradeSidekickRecords("care-reminders", oldRecords, careManifest);
    const after = recordsAfter(oldRecords, plan);
    expect(itemCount(oldRecords)).toBe(3);
    expect(itemCount(after)).toBe(3);
    const secondPlan = upgradeSidekickRecords("care-reminders", after, careManifest);
    expect(secondPlan.writes).toEqual([]);
    expect(secondPlan.deletes).toEqual([]);
  });

  it("cleans rules the way the page does", () => {
    expect(cleanCareRule({ id: "a", kind: "daysBefore", days: 30, time: "18:00", text: null })).toEqual({ id: "a", kind: "daysBefore", days: 14, time: "18:00" });
    expect(cleanCareRule({ id: "b", kind: "morningOf", text: "  Up! " })).toEqual({ id: "b", kind: "morningOf", time: "08:00", text: "Up!" });
    expect(cleanCareRule({ id: "c", kind: "before", minutes: 0 })).toEqual({ id: "c", kind: "before", minutes: 60 });
  });
});

describe("the op log", () => {
  it("replays to the latest record per key, tombstones remove, grouped by user and Sidekick", () => {
    const rows = [
      { seq: 1, user_id: "u1", sidekick_id: "reminders", key: "reminder:a", value: JSON.stringify({ title: "first" }), deleted: 0 },
      { seq: 2, user_id: "u1", sidekick_id: "reminders", key: "reminder:a", value: JSON.stringify({ title: "second" }), deleted: 0 },
      { seq: 3, user_id: "u1", sidekick_id: "reminders", key: "task:b", value: JSON.stringify({ title: "gone" }), deleted: 0 },
      { seq: 4, user_id: "u1", sidekick_id: "reminders", key: "task:b", value: null, deleted: 1 },
      { seq: 5, user_id: "u2", sidekick_id: "care-reminders", key: "list:x", value: JSON.stringify({ name: "X" }), deleted: 0 },
      { seq: 6, user_id: "u1", sidekick_id: "reminders", key: "broken", value: "{not json", deleted: 0 },
    ];
    const groups = replayOps(rows);
    expect(groups).toEqual([
      { userId: "u1", sidekickId: "reminders", records: [{ key: "reminder:a", value: { title: "second" } }] },
      { userId: "u2", sidekickId: "care-reminders", records: [{ key: "list:x", value: { name: "X" } }] },
    ]);
  });

  it("gives every op a deterministic id the server accepts", () => {
    const first = migrationOpId(sha256Hex, "u1", "reminders", "reminder:a", { b: 1, a: 2 });
    const same = migrationOpId(sha256Hex, "u1", "reminders", "reminder:a", { a: 2, b: 1 });
    const other = migrationOpId(sha256Hex, "u1", "reminders", "reminder:a", null);
    expect(first).toBe(same);
    expect(first).not.toBe(other);
    expect(first).toMatch(/^[A-Za-z0-9_-]{8,64}$/);
    expect(instantText(1760000000000)).toBe("2025-10-09T08:53:20.000Z");
    expect(instantText("2025-10-09T08:53:20.000Z")).toBe("2025-10-09T08:53:20.000Z");
  });

  it("plans per user and Sidekick, counts items, and writes inserts that never overwrite or delete", () => {
    const rows = [
      { seq: 1, user_id: "u1", sidekick_id: "reminders", key: "task:a", value: JSON.stringify({ title: "A" }), deleted: 0 },
      { seq: 2, user_id: "u1", sidekick_id: "reminders", key: "settings:sidebar", value: JSON.stringify({ order: ["today"] }), deleted: 0 },
      { seq: 3, user_id: "u2", sidekick_id: "reminders", key: "reminder:b", value: JSON.stringify({ $type: "reminders.item", title: "B" }), deleted: 0 },
    ];
    const manifestFor = (sidekickId: string) => (sidekickId === "reminders" ? remindersManifest : null);
    const plans = planMigration(rows, manifestFor);
    expect(plans.map((entry) => [entry.userId, entry.plan.writes.length, entry.plan.deletes.length, entry.itemsBefore, entry.itemsAfter])).toEqual([
      ["u1", 2, 2, 1, 1],
      ["u2", 0, 0, 1, 1],
    ]);
    expect(planMigration(rows, manifestFor, "u2").map((entry) => entry.userId)).toEqual(["u2"]);

    const statements = insertStatements("u1", "reminders", plans[0].plan, "2026-10-15T20:00:00.000Z");
    expect(statements).toHaveLength(1);
    const statement = statements[0];
    expect(statement.startsWith("INSERT INTO ops (op_id, user_id, sidekick_id, key, value, deleted, client_time, received_at) VALUES")).toBe(true);
    expect(statement.endsWith("ON CONFLICT(op_id) DO NOTHING")).toBe(true);
    expect(statement.toUpperCase()).not.toContain("DELETE FROM");
    expect(statement.toUpperCase()).not.toContain("UPDATE ");
    expect(statement).toContain("'reminder:a'");
    expect(statement).toContain("'task:a', NULL, 1");
    expect(statement).toContain("'settings:self'");
    expect(statement).toContain("'settings:sidebar', NULL, 1");
    expect(statement.match(/'mig1-/g)).toHaveLength(4);

    // Many ops go in chunks of 40.
    const manyRecords = [];
    for (let index = 0; index < 85; index += 1) {
      manyRecords.push({ key: `task:${index}`, value: { title: `t${index}` } });
    }
    const bigPlan = upgradeSidekickRecords("reminders", manyRecords, remindersManifest);
    expect(insertStatements("u1", "reminders", bigPlan, "2026-10-15T20:00:00.000Z")).toHaveLength(5);
  });
});
