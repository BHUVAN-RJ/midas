// The To-Do Sidekick's record types (docs/briefs/todo-sidekick.md, step 1; founder 2026-10-31):
// a to-do is a reminder:<id> record of type todo.item, so the notification engine, the tick from a
// notification and the shell's reminder check work as built; list:<id> and settings:self as in
// docs/primitives/todo/records.md. Every record shape the page writes must pass manifest.json the
// way the shell's write gate checks it, and wrong shapes must be refused.
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import { typesBlockProblems, validateManifest } from "../scripts/bundle-tools.mjs";

const manifestText = readFileSync(new URL("../../sidekicks/todo/manifest.json", import.meta.url), "utf8");
const manifest = JSON.parse(manifestText);

type Value = Record<string, unknown>;

function schemaProblem(key: string, value: Value) {
  const stamped = MidasRecordSchema.stampType(manifest.types, key, value);
  return MidasRecordSchema.checkRecord(manifest.types, key, stamped);
}

// A timed, repeating to-do with every field the page writes
function fullTodo(fields: Value = {}): Value {
  return {
    title: "Gym", notes: "Legs", list: "personal", when: "2026-10-31", part: "morning", time: "07:30",
    deadline: "2026-11-02", recur: { every: "weekday", from: "schedule" },
    subtasks: [{ id: "s1", title: "Stretch", done: false }], done: false, createdAt: "2026-10-31T15:00:00.000Z",
    order: 1730386800000.5, emoji: "💪", color: "#30A46C", inToday: "2026-10-31", someday: false,
    at: "2026-10-31T14:30:00.000Z", timeZone: "America/Los_Angeles", ...fields,
  };
}

const MINE = {
  look: "notebook", theme: "auto", accent: "#2F6FEB", textSize: "m", density: "comfy", font: "system",
  checkbox: "end", showMeta: true, dateColors: true, tickSound: "chimes", haptic: true,
  celebrate: "allDone", doneGoes: "stay", add: "row", parse: true, swipeRight: "complete",
  swipeLeft: "delete", home: "tabs", todayModel: "carry", dayParts: false,
};

describe("todo: the manifest", () => {
  it("is To-Do, with its own id, icon and types in the todo namespace", () => {
    expect(validateManifest(manifest, "todo")).toEqual([]);
    expect(typesBlockProblems(manifest.types, "todo")).toEqual([]);
    expect(manifest.id).toBe("todo");
    expect(manifest.name).toBe("To-Do");
    expect(manifest.types["reminder:"].$type).toBe("todo.item");
    expect(manifest.types["list:"].$type).toBe("todo.list");
    expect(manifest.types["settings:"].$type).toBe("todo.settings");
  });

  it("would be refused under another Sidekick's id (the namespace is checked)", () => {
    expect(validateManifest(manifest, "reminders").length).toBeGreaterThan(0);
  });
});

describe("todo: reminder: records (one to-do)", () => {
  it("accepts a full timed to-do, an untimed one with a title only, and a trashed one", () => {
    expect(schemaProblem("reminder:a1", fullTodo())).toBeNull();
    expect(schemaProblem("reminder:a2", { title: "Milk" })).toBeNull();
    expect(schemaProblem("reminder:a3", fullTodo({ deletedAt: "2026-10-31T16:00:00.000Z", externalId: "E1", nextId: "b7" }))).toBeNull();
  });

  it("keeps what the shell writes back from a notification (Done, Snooze)", () => {
    const fromShell = fullTodo({
      done: true, completedAt: "2026-10-31T15:10:00.000Z", snoozedUntil: "2026-10-31T15:20:00.000Z",
      snoozes: { "~a1": "2026-10-31T15:25:00.000Z" }, lastDoneAt: "2026-10-31T15:10:00.000Z",
      doneThrough: "2026-10-31T15:10:00.000Z", reminderType: "timeSensitive",
    });
    expect(schemaProblem("reminder:a1", fromShell)).toBeNull();
  });

  it("refuses a to-do without a title, or with an empty one", () => {
    expect(schemaProblem("reminder:a1", { notes: "x" })).toBe("todo.item.title is required");
    expect(schemaProblem("reminder:a1", fullTodo({ title: "" }))).not.toBeNull();
  });

  it("refuses wrong dates, times, parts and colours", () => {
    expect(schemaProblem("reminder:a1", fullTodo({ when: "tomorrow" }))).not.toBeNull();
    expect(schemaProblem("reminder:a1", fullTodo({ deadline: "2026/11/02" }))).not.toBeNull();
    expect(schemaProblem("reminder:a1", fullTodo({ time: "5pm" }))).not.toBeNull();
    expect(schemaProblem("reminder:a1", fullTodo({ part: "night" }))).not.toBeNull();
    expect(schemaProblem("reminder:a1", fullTodo({ color: "red" }))).not.toBeNull();
    expect(schemaProblem("reminder:a1", fullTodo({ completedAt: "yesterday" }))).not.toBeNull();
    expect(schemaProblem("reminder:a1", fullTodo({ at: "2026-10-31 07:30" }))).not.toBeNull();
    expect(schemaProblem("reminder:a1", fullTodo({ timeZone: "Mars/Olympus" }))).not.toBeNull();
  });

  it("takes only the repeats the page offers, under recur (the shell's own repeat has no weekday)", () => {
    for (const every of ["day", "weekday", "week", "month"]) {
      expect(schemaProblem("reminder:a1", fullTodo({ recur: { every, from: "done" } })), every).toBeNull();
    }
    expect(schemaProblem("reminder:a1", fullTodo({ recur: { every: "year", from: "schedule" } }))).not.toBeNull();
    expect(schemaProblem("reminder:a1", fullTodo({ recur: { every: "day" } }))).not.toBeNull();
    expect(schemaProblem("reminder:a1", fullTodo({ recur: { every: "day", from: "done", interval: 2 } }))).not.toBeNull();
  });

  it("refuses null where a field should be left out, and a subtask without its fields", () => {
    expect(schemaProblem("reminder:a1", fullTodo({ when: null }))).not.toBeNull();
    expect(schemaProblem("reminder:a1", fullTodo({ subtasks: [{ id: "s1", title: "Stretch" }] }))).not.toBeNull();
    expect(schemaProblem("reminder:a1", fullTodo({ done: "yes" }))).not.toBeNull();
  });
});

describe("todo: list: and settings:self", () => {
  it("accepts a list as records.md section 2 describes it, and refuses one without a name", () => {
    expect(schemaProblem("list:groceries", { name: "Groceries", emoji: "🛒", color: "#FFB224", wallpaper: "sand", order: 4 })).toBeNull();
    expect(schemaProblem("list:inbox", { name: "Inbox", color: "#2F6FEB", wallpaper: "sky", order: 0 })).toBeNull();
    expect(schemaProblem("list:x", { emoji: "🛒" })).toBe("todo.list.name is required");
    expect(schemaProblem("list:x", { name: "" })).not.toBeNull();
    expect(schemaProblem("list:x", { name: "X", color: "blue" })).not.toBeNull();
  });

  it("accepts the founder's own selections (2026-10-31) with every preset name", () => {
    expect(schemaProblem("settings:self", MINE)).toBeNull();
    for (const preset of ["mine", "paper", "notebook", "soft", "wallpaper", "heat", "custom"]) {
      expect(schemaProblem("settings:self", { ...MINE, preset }), preset).toBeNull();
    }
  });

  it("refuses a value no option in Make It Yours offers", () => {
    expect(schemaProblem("settings:self", { ...MINE, look: "glass" })).not.toBeNull();
    expect(schemaProblem("settings:self", { ...MINE, todayModel: "never" })).not.toBeNull();
    expect(schemaProblem("settings:self", { ...MINE, haptic: "on" })).not.toBeNull();
    expect(schemaProblem("settings:self", { ...MINE, accent: "blue" })).not.toBeNull();
    expect(schemaProblem("settings:self", { ...MINE, preset: "basic" })).not.toBeNull();
  });
});

describe("todo: import: parts from the shell's Apple Reminders import", () => {
  it("accepts the part shape the shell writes and refuses one without its part numbers", () => {
    const part = { source: "apple-reminders", origin: "iphone", exportedAt: "2026-10-31T09:00:00-07:00", timeZone: "America/Los_Angeles", part: 0, parts: 1, lists: [], reminders: [] };
    expect(schemaProblem("import:i1:0000", part)).toBeNull();
    expect(schemaProblem("import:i1:0000", { source: "apple-reminders" })).not.toBeNull();
  });
});
