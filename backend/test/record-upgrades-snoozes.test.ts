// OLD RECORD SHAPES ARE ALLOWED HERE ONLY: this file tests the upgrade-on-read converter
// (backend/scripts/record-upgrades.mjs) and the migration (backend/scripts/migrate-records.mjs),
// so its fixtures hold the record formats used before the unified data format (founder,
// 2026-10-20). Their description lives only in docs/legacy/LEGACY-RECORD-FORMATS.DO-NOT-READ.md
// (do not read it); never copy these fixtures into other tests.

import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import { recordsAfter, typesFor, upgradeSidekickRecords } from "../scripts/record-upgrades.mjs";

// Founder decision 2026-10-15: a snooze on an early alert or an hourly time is that one's own,
// never the item's. Before the rework each alert (`~rule`) and time (`@HHMM`) record carried its
// own `snoozedUntil`; the migration carries those into the item's `snoozes` map, keyed by the
// notification's suffix, so every pending snooze survives with its own wording.

function readManifest(sidekickId: string) {
  return JSON.parse(readFileSync(new URL(`../../sidekicks/${sidekickId}/manifest.json`, import.meta.url), "utf8"));
}

const careManifest = readManifest("care-reminders");
const careTypes = typesFor(careManifest);

function valueOf(plan: { writes: Array<{ key: string; value: unknown }> }, key: string) {
  const write = plan.writes.find((candidate) => candidate.key === key);
  return write?.value as Record<string, unknown> | undefined;
}

const oldRecords = [
  { key: "list:appointments", value: { name: "Appointments", icon: "stethoscope", color: "charcoal", order: 0, alerts: [{ id: "r1", kind: "daysBefore", days: 1, time: "18:00", text: null }, { id: "r3", kind: "before", minutes: 60, text: "Soon: {title}" }] } },
  { key: "reminder:dentist", value: { kind: "care-item", at: "2026-10-20T20:00:00.000Z", title: "Dentist", body: "", timeZone: "America/Los_Angeles", done: false, list: "appointments", snoozedUntil: "2026-10-20T20:30:00.000Z" } },
  // Snoozed, not done: its snooze must survive as the alert's own.
  { key: "reminder:dentist~r1", value: { kind: "care-alert", at: "2026-10-20T01:00:00.000Z", title: "Dentist tomorrow at 1:00 PM", body: "", timeZone: "America/Los_Angeles", done: false, alertOf: "dentist", rule: "r1", occurrenceAt: "2026-10-20T20:00:00.000Z", snoozedUntil: "2026-10-20T01:10:00.000Z" } },
  // Done: a snooze on a done alert is over and is not carried.
  { key: "reminder:dentist~r3", value: { kind: "care-alert", at: "2026-10-20T19:00:00.000Z", title: "Soon: Dentist", body: "", timeZone: "America/Los_Angeles", done: true, alertOf: "dentist", rule: "r3", occurrenceAt: "2026-10-20T20:00:00.000Z", snoozedUntil: "2026-10-20T19:10:00.000Z", lastDoneAt: "2026-10-20T19:12:00.000Z" } },
  { key: "reminder:pills", value: { kind: "care-item", at: "2026-10-12T15:00:00.000Z", title: "Pills", body: "", timeZone: "America/Los_Angeles", done: false, list: "medicine", repeat: { every: "day" }, everyHours: 4 } },
  // An hourly time snoozed (epoch milliseconds, the oldest shape) and another untouched.
  { key: "reminder:pills@1200", value: { kind: "care-slot", at: "2026-10-12T19:00:00.000Z", title: "Pills", body: "", timeZone: "America/Los_Angeles", done: false, repeat: { every: "day" }, slotOf: "pills", time: "12:00", snoozedUntil: 1792092600000 } },
  { key: "reminder:pills@1600", value: { kind: "care-slot", at: "2026-10-12T23:00:00.000Z", title: "Pills", body: "", timeZone: "America/Los_Angeles", done: false, repeat: { every: "day" }, slotOf: "pills", time: "16:00" } },
  { key: "reminder:walk", value: { kind: "care-item", at: "2026-10-01T15:00:00.000Z", title: "Walk", body: "", timeZone: "America/Los_Angeles", done: false, list: "appointments", repeat: { every: "day" } } },
];

describe("old alert and time snoozes", () => {
  it("become the item's own entries per alert and per time, the item's snooze untouched", () => {
    const plan = upgradeSidekickRecords("care-reminders", oldRecords, careManifest);
    expect(plan.problems).toEqual([]);
    const dentist = valueOf(plan, "reminder:dentist");
    expect(dentist?.snoozes).toEqual({ "~r1": "2026-10-20T01:10:00.000Z" });
    expect(dentist?.snoozedUntil).toBe("2026-10-20T20:30:00.000Z");
    // The event was completed by Done on r3.
    expect(dentist?.done).toBe(true);
    const pills = valueOf(plan, "reminder:pills");
    expect(pills?.snoozes).toEqual({ "@1200": "2026-10-15T19:30:00.000Z" });
    expect(pills?.snoozedUntil).toBeUndefined();
    const walk = valueOf(plan, "reminder:walk");
    expect(walk).toBeDefined();
    expect(walk).not.toHaveProperty("snoozes");
  });

  it("pass the care.item schema and are quiet the second time", () => {
    const plan = upgradeSidekickRecords("care-reminders", oldRecords, careManifest);
    for (const write of plan.writes) {
      expect(MidasRecordSchema.checkRecord(careTypes, write.key, write.value), `${write.key} does not fit`).toBeNull();
    }
    const after = recordsAfter(oldRecords, plan);
    const secondPlan = upgradeSidekickRecords("care-reminders", after, careManifest);
    expect(secondPlan.writes).toEqual([]);
  });
});

describe("the care.item snoozes field", () => {
  const item = { $type: "care.item", title: "Dentist", at: "2026-10-20T20:00:00.000Z" };

  it("takes alert and time suffixes to dates", () => {
    const snoozes = { "~r1": "2026-10-20T01:10:00.000Z", "@1200": "2026-10-20T19:30:00.000Z" };
    expect(MidasRecordSchema.checkRecord(careTypes, "reminder:dentist", { ...item, snoozes })).toBeNull();
  });

  it("refuses a value that is not a date and a key that is not a suffix", () => {
    expect(MidasRecordSchema.checkRecord(careTypes, "reminder:dentist", { ...item, snoozes: { "~r1": "someday" } })).toContain("snoozes");
    expect(MidasRecordSchema.checkRecord(careTypes, "reminder:dentist", { ...item, snoozes: { r1: "2026-10-20T01:10:00.000Z" } })).toContain("snoozes");
  });
});
