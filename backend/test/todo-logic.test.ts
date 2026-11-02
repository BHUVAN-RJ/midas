// The To-Do Sidekick's own logic (docs/briefs/todo-sidekick.md, step 2): TodoLogic is taken out
// of sidekicks/todo/index.html and run on its own, the way tools.js carries it. These are the 22
// checks run against the prototype (docs/mockups/todo-primitive-2026-10-31.html), rewritten
// against the real logic, plus the Trash, the Apple Reminders import and the page's own rules
// (one script, the store helper pasted unchanged, no browser storage, every record it writes
// passes manifest.json).
process.env.TZ = "America/Los_Angeles";

import { readFileSync } from "node:fs";
import vm from "node:vm";
import { describe, expect, it } from "vitest";
import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import { findForbiddenPrimitives } from "../scripts/bundle-tools.mjs";

const html = readFileSync(new URL("../../sidekicks/todo/index.html", import.meta.url), "utf8");
const storeHelper = readFileSync(new URL("../../shell/sdk/midas-store.js", import.meta.url), "utf8");
const manifest = JSON.parse(readFileSync(new URL("../../sidekicks/todo/manifest.json", import.meta.url), "utf8"));

function todoLogicSource(pageHtml: string) {
  const start = pageHtml.indexOf("var TodoLogic = (function createTodoLogic() {");
  const end = pageHtml.indexOf("\n})();\n", start) + "\n})();\n".length;
  if (start === -1 || end <= start) {
    throw new Error("TodoLogic is not in index.html");
  }
  return pageHtml.slice(start, end);
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const Logic: any = vm.runInNewContext(todoLogicSource(html) + "\n;TodoLogic;", { Intl, Date, Math, JSON });

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Todo = Record<string, any>;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Model = { todos: Record<string, Todo>; lists: Record<string, any>; settings: Record<string, any>; preset: string };

// Saturday Oct 31, 2026, 10:00 in Los Angeles (PDT, UTC-7)
const TODAY = "2026-10-31";
const NOW = Date.parse("2026-10-31T17:00:00.000Z");
const ZONE = "America/Los_Angeles";

function day(offset: number) {
  return Logic.addDays(TODAY, offset);
}

function emptyModel(settings: Record<string, unknown> = {}): Model {
  const model = Logic.modelFromRecords([]);
  Object.assign(model.settings, settings);
  return model;
}

let counter = 0;
function addTodo(model: Model, fields: Todo): Todo {
  counter += 1;
  const todo = Logic.blankTodo({ order: counter, ...fields }, NOW, "t" + counter);
  model.todos[todo.id] = todo;
  return todo;
}

function apply(model: Model, todos: Todo[]) {
  for (const todo of todos) {
    model.todos[todo.id] = todo;
  }
}

function titles(items: Todo[]) {
  return items.map((item) => item.title);
}

function schemaProblem(key: string, value: Record<string, unknown>) {
  const stamped = MidasRecordSchema.stampType(manifest.types, key, value);
  return MidasRecordSchema.checkRecord(manifest.types, key, stamped);
}

// The prototype's sample day: six for Today, one carried over from three days ago
function sampleModel(settings: Record<string, unknown> = {}): Model {
  const model = emptyModel(settings);
  model.lists.personal = { id: "personal", name: "Personal", emoji: null, color: "#2F6FEB", wallpaper: "ocean", order: 1, externalId: null, stored: null };
  addTodo(model, { title: "Laundry", when: day(-3) });
  addTodo(model, { title: "Gym", when: TODAY, part: "morning" });
  addTodo(model, { title: "Email Sam", when: TODAY });
  addTodo(model, { title: "Pay rent", when: TODAY, deadline: day(1) });
  addTodo(model, { title: "Groceries", when: TODAY, list: "personal" });
  addTodo(model, { title: "Read", when: TODAY, part: "evening" });
  addTodo(model, { title: "Trip plan", when: day(2) });
  addTodo(model, { title: "Learn piano", someday: true });
  return model;
}

describe("todo: the page itself", () => {
  it("has one plain script, the store helper pasted unchanged, and no browser storage", () => {
    expect(html.match(/<script\b[^>]*>/g)).toEqual(["<script>"]);
    expect(html.includes(storeHelper.trim())).toBe(true);
    expect(html).not.toMatch(/localStorage|sessionStorage|indexedDB/);
    // CSP: no inline handlers in the markup
    expect(html).not.toMatch(/<[^>]+\son[a-z]+\s*=\s*["']/i);
    // The deploy gate's own check (an "import" followed by a word, in a comment too, fails it)
    expect(findForbiddenPrimitives(html)).toEqual([]);
  });

  it("has the haptic switch the tick toggles", () => {
    expect(html).toMatch(/<input type="checkbox" switch id="hapticInput">/);
  });
});

describe("todo: Today (check 2)", () => {
  it("shows the six for today and the one carried over, marked Since", () => {
    const model = sampleModel();
    const items = Logic.todayItems(model, TODAY, null);
    expect(items).toHaveLength(6);
    expect(titles(items)).toContain("Laundry");
    expect(titles(items)).not.toContain("Trip plan");
    expect(titles(items)).not.toContain("Learn piano");
    // The page shows it as "Since Oct 28" (no red outside the Overdue model)
    expect(Logic.friendlyDay(day(-3), TODAY)).toBe("Oct 28");
    expect(Logic.friendlyDay(day(-1), TODAY)).toBe("Yesterday");
    expect(Logic.friendlyDay(day(1), TODAY)).toBe("Tomorrow");
  });
});

describe("todo: natural language (checks 3, 4, 21)", () => {
  it("reads a day, a time, a list and a repeat out of the line", () => {
    const model = sampleModel();
    const parsed = Logic.parseEntry("Call dad tomorrow at 5pm #personal every week", model, TODAY);
    expect(parsed.title).toBe("Call dad");
    expect(parsed.when).toBe(day(1));
    expect(parsed.time).toBe("17:00");
    expect(parsed.list).toBe("personal");
    expect(parsed.recur).toEqual({ every: "week", from: "schedule" });
  });

  it("keeps the line as typed when understanding is off", () => {
    const model = sampleModel({ parse: false });
    const parsed = Logic.parseEntry("Call dad tomorrow at 5pm", model, TODAY);
    expect(parsed.title).toBe("Call dad tomorrow at 5pm");
    expect(parsed.when).toBeNull();
    expect(parsed.time).toBeNull();
  });

  it("puts a weekday on the next one of that day (quick entry)", () => {
    const todo = Logic.todoFromEntry("Book flights friday", {}, emptyModel(), TODAY, NOW);
    expect(todo.title).toBe("Book flights");
    expect(todo.when).toBe("2026-11-06");
  });

  it("returns nothing for a line with no title", () => {
    expect(Logic.todoFromEntry("   ", {}, emptyModel(), TODAY, NOW)).toBeNull();
  });
});

describe("todo: repeats (checks 5, 6)", () => {
  it("makes the next copy once when ticked; a second tick inside 2 s is ignored", () => {
    const model = emptyModel();
    const gym = addTodo(model, { title: "Gym", when: TODAY, recur: { every: "weekday", from: "schedule" } });
    const changes = Logic.completeTodo(model, gym.id, NOW, TODAY);
    apply(model, changes.todos);
    expect(changes.created).toHaveLength(1);
    const next = model.todos[changes.created[0]];
    // Saturday's weekday repeat comes back on Monday
    expect(next.when).toBe("2026-11-02");
    expect(next.done).toBe(false);
    expect(model.todos[gym.id].nextId).toBe(next.id);
    expect(Logic.isDoubleTick(model.todos[gym.id], NOW, NOW + 1500)).toBe(true);
    expect(Logic.isDoubleTick(model.todos[gym.id], NOW, NOW + 2500)).toBe(false);
    const again = Logic.completeTodo(model, gym.id, NOW + 3000, TODAY);
    expect(again.created).toEqual([]);
  });

  it("counts After Done from the tick, and a fallen-behind schedule from after today", () => {
    expect(Logic.nextRepeatDay({ when: day(-10), recur: { every: "day", from: "done" } }, TODAY)).toBe(day(1));
    expect(Logic.nextRepeatDay({ when: day(-10), recur: { every: "week", from: "schedule" } }, TODAY)).toBe(day(4));
    expect(Logic.nextRepeatDay({ when: "2026-10-15", recur: { every: "month", from: "schedule" } }, TODAY)).toBe("2026-11-15");
  });

  it("undo after a tick removes the next copy and un-ticks", () => {
    const model = emptyModel();
    const gym = addTodo(model, { title: "Gym", when: TODAY, recur: { every: "day", from: "schedule" } });
    const before = Logic.copyJson(gym);
    const changes = Logic.completeTodo(model, gym.id, NOW, TODAY);
    apply(model, changes.todos);
    // The page's undo: the snapshot back, the created ones removed
    model.todos[gym.id] = before;
    for (const id of changes.created) {
      delete model.todos[id];
    }
    expect(Object.keys(model.todos)).toEqual([gym.id]);
    expect(model.todos[gym.id].done).toBe(false);
  });

  it("gives a repeat ticked from a notification its next copy when next seen, keeping when it was ticked", () => {
    const record = { title: "Pills", when: TODAY, time: "08:00", recur: { every: "day", from: "schedule" }, done: true, completedAt: "2026-10-31T15:05:00.000Z" };
    const model = Logic.modelFromRecords([{ key: "reminder:p1", value: record }]);
    const changes = Logic.missingNextCopies(model, NOW, TODAY);
    expect(changes.created).toHaveLength(1);
    const ticked = changes.todos.find((todo: Todo) => todo.id === "p1");
    expect(ticked.completedAt).toBe("2026-10-31T15:05:00.000Z");
    const next = changes.todos.find((todo: Todo) => todo.id !== "p1");
    expect(next.when).toBe(day(1));
    apply(model, changes.todos);
    expect(Logic.missingNextCopies(model, NOW, TODAY).created).toEqual([]);
  });

  it("unticking clears done and its moment", () => {
    const todo = Logic.uncompleteTodo({ title: "x", done: true, completedAt: "2026-10-31T15:05:00.000Z" });
    expect(todo.done).toBe(false);
    expect(todo.completedAt).toBeNull();
  });
});

describe("todo: real record shapes (check 7)", () => {
  it("writes what the schema takes: no nulls, at and timeZone only when timed", () => {
    const model = emptyModel();
    const timed = addTodo(model, { title: "Call dad", when: day(1), time: "17:00", recur: { every: "week", from: "schedule" } });
    const untimed = addTodo(model, { title: "Milk", when: TODAY });
    const undated = addTodo(model, { title: "Someday thing", someday: true });
    const timedValue = Logic.todoRecordValue(timed, ZONE);
    expect(timedValue.at).toBe("2026-11-02T01:00:00.000Z");
    expect(timedValue.timeZone).toBe(ZONE);
    const untimedValue = Logic.todoRecordValue(untimed, ZONE);
    expect("at" in untimedValue).toBe(false);
    expect("timeZone" in untimedValue).toBe(false);
    for (const [id, value] of [[timed.id, timedValue], [untimed.id, untimedValue], [undated.id, Logic.todoRecordValue(undated, ZONE)]]) {
      expect(Object.values(value as object)).not.toContain(null);
      expect(schemaProblem(Logic.todoKey(id), value as Record<string, unknown>)).toBeNull();
    }
  });

  it("keeps what the shell wrote, and drops a snooze when the time moves", () => {
    const stored = { title: "Call", when: TODAY, time: "17:00", at: "2026-11-01T00:00:00.000Z", timeZone: ZONE, alerts: [{ before: 10 }], reminderType: "timeSensitive", snoozedUntil: "2026-11-01T00:10:00.000Z", done: false };
    const todo = Logic.todoFromRecord("reminder:c1", stored);
    const same = Logic.todoRecordValue(todo, ZONE);
    expect(same.alerts).toEqual([{ before: 10 }]);
    expect(same.reminderType).toBe("timeSensitive");
    expect(same.snoozedUntil).toBe("2026-11-01T00:10:00.000Z");
    todo.time = "18:00";
    const moved = Logic.todoRecordValue(todo, ZONE);
    expect(moved.at).toBe("2026-11-01T01:00:00.000Z");
    expect("snoozedUntil" in moved).toBe(false);
    expect(moved.alerts).toEqual([{ before: 10 }]);
  });

  it("writes the founder's settings and every preset as a valid settings:self", () => {
    expect(Logic.DEFAULT_SETTINGS).toEqual({
      look: "notebook", theme: "auto", accent: "#2F6FEB", textSize: "m", density: "comfy", font: "system",
      checkbox: "end", showMeta: true, dateColors: true, tickSound: "chimes", haptic: true,
      celebrate: "allDone", doneGoes: "stay", add: "row", parse: true, swipeRight: "complete",
      swipeLeft: "delete", home: "tabs", todayModel: "carry", dayParts: false,
    });
    expect(Logic.PRESETS.mine.name).toBe("Mine");
    expect(Logic.presetSettings("mine")).toEqual(Logic.DEFAULT_SETTINGS);
    for (const preset of Logic.PRESET_IDS) {
      expect(schemaProblem("settings:self", Logic.settingsRecordValue(Logic.presetSettings(preset), preset)), preset).toBeNull();
    }
  });
});

describe("todo: the four done modes (checks 8, 9, 10)", () => {
  function tickedModel(doneGoes: string) {
    const model = emptyModel({ doneGoes });
    const first = addTodo(model, { title: "First", when: TODAY });
    addTodo(model, { title: "Second", when: TODAY });
    apply(model, Logic.completeTodo(model, first.id, NOW, TODAY).todos);
    return { model, first };
  }

  it("Stay keeps the done one in place", () => {
    const { model } = tickedModel("stay");
    const arranged = Logic.arrangeDone(Logic.todayItems(model, TODAY, null), "stay");
    expect(titles(arranged.main)).toEqual(["First", "Second"]);
  });

  it("Sink moves it to the bottom", () => {
    const { model } = tickedModel("sink");
    const arranged = Logic.arrangeDone(Logic.todayItems(model, TODAY, null), "sink");
    expect(titles(arranged.main)).toEqual(["Second", "First"]);
  });

  it("Hide keeps it behind Show Done (1)", () => {
    const { model } = tickedModel("hide");
    const arranged = Logic.arrangeDone(Logic.todayItems(model, TODAY, null), "hide");
    expect(titles(arranged.main)).toEqual(["Second"]);
    expect(arranged.done).toHaveLength(1);
  });

  it("Logbook shows it only while it was just ticked, then in the Logbook", () => {
    const { model, first } = tickedModel("logbook");
    expect(titles(Logic.todayItems(model, TODAY, first.id))).toContain("First");
    expect(titles(Logic.todayItems(model, TODAY, null))).toEqual(["Second"]);
    expect(titles(Logic.logbookItems(model))).toEqual(["First"]);
  });

  it("a done one from another day is gone from Today in every mode", () => {
    const model = emptyModel();
    addTodo(model, { title: "Old", when: day(-1), done: true, completedAt: "2026-10-30T17:00:00.000Z" });
    expect(Logic.todayItems(model, TODAY, null)).toEqual([]);
  });
});

describe("todo: the four today models (checks 11, 12, 13)", () => {
  it("Carry over puts late ones in Today; Overdue puts them first under Overdue", () => {
    const carry = sampleModel({ todayModel: "carry" });
    expect(Logic.todaySections(carry, Logic.todayItems(carry, TODAY, null), TODAY).map((section: Todo) => section.kind)).toEqual(["today"]);
    const stay = sampleModel({ todayModel: "stay" });
    const sections = Logic.todaySections(stay, Logic.todayItems(stay, TODAY, null), TODAY);
    expect(sections[0].kind).toBe("overdue");
    expect(titles(sections[0].items)).toEqual(["Laundry"]);
    expect(Logic.overdueCount(stay, TODAY)).toBe(1);
  });

  it("Fresh Start shows only what was added today, offers the rest, and Add All brings them in", () => {
    const model = sampleModel({ todayModel: "fresh" });
    expect(Logic.todayItems(model, TODAY, null)).toEqual([]);
    const suggestions = Logic.freshSuggestions(model, TODAY);
    expect(titles(suggestions)).toContain("Laundry");
    expect(suggestions).toHaveLength(6);
    apply(model, suggestions.map((todo: Todo) => Logic.addedToToday(todo, TODAY)));
    expect(Logic.todayItems(model, TODAY, null)).toHaveLength(6);
    expect(Logic.freshSuggestions(model, TODAY)).toEqual([]);
  });

  it("Start Dates hides future ones from their list and counts them as Later", () => {
    const model = emptyModel({ todayModel: "gated" });
    addTodo(model, { title: "Now", when: TODAY });
    addTodo(model, { title: "No date" });
    addTodo(model, { title: "Next week", when: day(7) });
    expect(titles(Logic.listItems(model, "inbox", TODAY, null))).toEqual(["Now", "No date"]);
    expect(Logic.laterCount(model, "inbox", TODAY)).toBe(1);
    const carry = { ...model, settings: { ...model.settings, todayModel: "carry" } };
    expect(Logic.listItems(carry, "inbox", TODAY, null)).toHaveLength(3);
  });

  it("parts of day split Today when they are on", () => {
    const model = sampleModel({ dayParts: true });
    const sections = Logic.todaySections(model, Logic.todayItems(model, TODAY, null), TODAY);
    expect(sections.map((section: Todo) => section.part)).toEqual(["none", "morning", "afternoon", "evening"]);
    expect(titles(sections[1].items)).toEqual(["Gym"]);
  });
});

describe("todo: search (check 14)", () => {
  it("finds open and done ones, and a done one can be added again for today", () => {
    const model = emptyModel();
    addTodo(model, { title: "Buy milk", when: TODAY });
    const old = addTodo(model, { title: "Milk again", done: true, completedAt: "2026-10-20T17:00:00.000Z" });
    addTodo(model, { title: "Milk in trash", deletedAt: "2026-10-30T17:00:00.000Z" });
    const found = Logic.searchItems(model, "MILK");
    expect(titles(found.open)).toEqual(["Buy milk"]);
    expect(titles(found.done)).toEqual(["Milk again"]);
    const again = Logic.againTodo(old, TODAY, NOW);
    expect(again.title).toBe("Milk again");
    expect(again.done).toBe(false);
    expect(again.when).toBe(TODAY);
    expect(again.id).not.toBe(old.id);
  });
});

describe("todo: delete and the Trash (check 15)", () => {
  it("moves a deleted one to the Trash, restores it, and removes ones older than 30 days", () => {
    const model = emptyModel();
    const milk = addTodo(model, { title: "Milk", when: TODAY });
    const before = Logic.copyJson(milk);
    apply(model, [Logic.trashedTodo(milk, NOW)]);
    expect(Logic.todayItems(model, TODAY, null)).toEqual([]);
    expect(titles(Logic.trashItems(model))).toEqual(["Milk"]);
    expect(schemaProblem("reminder:" + milk.id, Logic.todoRecordValue(model.todos[milk.id], ZONE))).toBeNull();
    // Undo puts the snapshot back
    model.todos[milk.id] = before;
    expect(Logic.trashItems(model)).toEqual([]);
    apply(model, [Logic.trashedTodo(milk, NOW)]);
    apply(model, [Logic.restoredTodo(model.todos[milk.id])]);
    expect(Logic.todoRecordValue(model.todos[milk.id], ZONE).deletedAt).toBeUndefined();
    const old = addTodo(model, { title: "Old", deletedAt: new Date(NOW - 31 * 86400000).toISOString() });
    addTodo(model, { title: "Recent", deletedAt: new Date(NOW - 29 * 86400000).toISOString() });
    expect(Logic.expiredTrashIds(model, NOW)).toEqual([old.id]);
  });

  it("a trashed timed to-do loses its at, so it never notifies", () => {
    const todo = Logic.blankTodo({ title: "Call", when: TODAY, time: "17:00" }, NOW, "c1");
    expect(Logic.todoRecordValue(Logic.trashedTodo(todo, NOW), ZONE).at).toBeUndefined();
  });
});

describe("todo: escaping and order (checks 16, 17)", () => {
  it("escapes a title wherever it is shown", () => {
    expect(Logic.escapeHtml('<img src=x onerror="a">&')).toBe("&lt;img src=x onerror=&quot;a&quot;&gt;&amp;");
    const parsed = Logic.parseEntry("<b>hi</b> tomorrow", emptyModel(), TODAY);
    const preview = Logic.previewHtml("<b>hi</b> tomorrow", parsed);
    expect(preview).not.toContain("<b>");
    expect(preview).toContain("&lt;b&gt;");
  });

  it("orders between two neighbours with one write", () => {
    expect(Logic.orderBetween(10, 20, NOW)).toBe(15);
    expect(Logic.orderBetween(null, 10, NOW)).toBe(9);
    expect(Logic.orderBetween(10, null, NOW)).toBe(11);
    expect(Logic.orderBetween(null, null, NOW)).toBe(NOW);
  });
});

describe("todo: Make It Yours (checks 18, 19, 20)", () => {
  it("every panel option is a value settings:self takes and the page reads back", () => {
    for (const group of Logic.PANEL) {
      for (const option of group[1]) {
        const field = option[0];
        const choices = option[2] === "accent" ? Logic.ACCENTS.map((accent: string) => [accent]) : option[2];
        for (const choice of choices) {
          const settings = { ...Logic.DEFAULT_SETTINGS, [field]: choice[0] };
          expect(Logic.isSettingValue(field, choice[0]), field).toBe(true);
          const value = Logic.settingsRecordValue(settings, "custom");
          expect(schemaProblem("settings:self", value), field).toBeNull();
          const read = Logic.settingsFrom(value);
          expect(read.settings[field], field).toEqual(choice[0]);
          expect(read.preset).toBe("custom");
        }
      }
    }
  });

  it("covers every settings field in the panel, and ignores unknown values on read", () => {
    expect(Logic.settingFields().sort()).toEqual(Object.keys(Logic.DEFAULT_SETTINGS).sort());
    const read = Logic.settingsFrom({ look: "glass", haptic: "on", preset: "basic" });
    expect(read.settings).toEqual(Logic.DEFAULT_SETTINGS);
    expect(read.preset).toBe("mine");
  });
});

describe("todo: lists (check 22)", () => {
  it("asks before deleting a list with open to-dos, and never deletes the Inbox", () => {
    const model = sampleModel();
    const plan = Logic.listDeletePlan(model, "personal");
    expect(plan.asksFirst).toBe(true);
    expect(plan.openCount).toBe(1);
    expect(plan.todoIds).toHaveLength(1);
    model.lists.empty = { id: "empty", name: "Empty", order: 2 };
    expect(Logic.listDeletePlan(model, "empty").asksFirst).toBe(false);
    expect(Logic.listDeletePlan(model, "inbox").allowed).toBe(false);
  });

  it("the Inbox is there without being written", () => {
    const model = Logic.modelFromRecords([]);
    expect(model.lists.inbox.name).toBe("Inbox");
  });
});

describe("todo: import from Apple Reminders", () => {
  const exported = {
    lists: [{ id: "L1", title: "Work", color: "#2F6FEB" }],
    reminders: [
      { id: "R1", externalId: "E1", listId: "L1", title: "Send report", completed: false, due: { allDay: true, date: "2026-11-03" } },
      { id: "R2", externalId: "E2", listId: "L1", title: "Standup", completed: false, due: { allDay: false, date: "2026-11-02", time: "09:30" }, recurrence: [{ frequency: "weekly", interval: 1, daysOfWeek: [{ weekday: 2 }, { weekday: 3 }, { weekday: 4 }, { weekday: 5 }, { weekday: 6 }] }] },
      { id: "R3", externalId: "E3", listId: "L1", title: "Every 2 days", completed: false, recurrence: [{ frequency: "daily", interval: 2 }] },
    ],
  };

  it("joins the shell's parts in order", () => {
    const joined = Logic.joinImportParts([
      { key: "import:x:0001", value: { part: 1, parts: 2, lists: [], reminders: [exported.reminders[1]] } },
      { key: "import:x:0000", value: { part: 0, parts: 2, lists: exported.lists, reminders: [exported.reminders[0]] } },
    ]);
    expect(joined.reminders.map((reminder: Todo) => reminder.externalId)).toEqual(["E1", "E2"]);
    expect(Logic.joinImportParts([])).toBeNull();
  });

  it("brings lists and reminders in, matched on externalId the second time", () => {
    const model = emptyModel();
    const plan = Logic.importPlan(model, exported, NOW);
    expect(plan.counts).toEqual({ imported: 3, updated: 0, upToDate: 0, repeatsNotImported: 1 });
    expect(plan.lists).toHaveLength(1);
    const standup = plan.todos.find((todo: Todo) => todo.externalId === "E2");
    expect(standup.recur).toEqual({ every: "weekday", from: "schedule" });
    expect(standup.time).toBe("09:30");
    expect(standup.list).toBe(plan.lists[0].id);
    for (const todo of plan.todos) {
      expect(schemaProblem(Logic.todoKey(todo.id), Logic.todoRecordValue(todo, ZONE))).toBeNull();
    }
    expect(schemaProblem(Logic.listKey(plan.lists[0].id), Logic.listRecordValue(plan.lists[0]))).toBeNull();
    for (const list of plan.lists) {
      model.lists[list.id] = list;
    }
    apply(model, plan.todos);
    const again = Logic.importPlan(model, exported, NOW);
    expect(again.counts.imported).toBe(0);
    expect(again.counts.upToDate).toBe(3);
    expect(again.lists).toEqual([]);
    const changed = { ...exported, reminders: [{ ...exported.reminders[0], title: "Send the report" }] };
    const updated = Logic.importPlan(model, changed, NOW);
    expect(updated.counts.updated).toBe(1);
    expect(updated.todos[0].id).toBe(plan.todos.find((todo: Todo) => todo.externalId === "E1").id);
  });
});
