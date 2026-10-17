// Voice reminders fix pass after the founder's first DeepSeek eval (founder, 2026-10-16; report
// backend/voice-eval-2026-10-16T07-02-00-131Z.md). The app reads the when words the model copies
// (whenText) and settles the day itself: a time already past today moves to its next occurrence
// unless "today" was said, a named weekday is worked out in code, a weekly repeat without weekdays
// takes its first date's weekday (as the page reads it), "add X to <list>" titles drop the list
// words. The model's real replies from that run are replayed here; the paid API is never called.
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import vm from "node:vm";
import { describe, expect, it } from "vitest";
import { callModel, loadGolden, main, parseArgs, replayRun, scoreCase } from "../scripts/eval-voice.mjs";
import {
  MAX_REPLY_TOKENS,
  buildOpenRouterRequest,
  buildPrompt,
  outcomeFromModelContent,
  parseJsonObjectText,
  readWhenWords,
  resolveReply,
  splitListAddTitle,
  type ModelReply,
  type VoiceContext,
  type VoiceOutcome,
} from "../src/voice.ts";

const golden = loadGolden();
const recordedRun = JSON.parse(readFileSync(new URL("../scripts/voice-replies-2026-10-16.json", import.meta.url), "utf8"));
const bundleHtml = readFileSync(new URL("../../sidekicks/reminders/index.html", import.meta.url), "utf8");

function loadRemindersLogic() {
  const scriptMatch = bundleHtml.match(/<script>([\s\S]*?)<\/script>/);
  if (!scriptMatch) {
    throw new Error("index.html has no inline script");
  }
  const sandboxWindow = { location: { origin: "sidekick://reminders" } };
  const sandbox = { window: sandboxWindow, console, Intl, Date, Math, JSON };
  vm.createContext(sandbox);
  vm.runInContext(scriptMatch[1], sandbox);
  return (sandbox as Record<string, any>).RemindersLogic;
}

const pageLogic = loadRemindersLogic();

const LA = "America/Los_Angeles";
const LISTS = [
  { id: "list:work", name: "Work" },
  { id: "list:groceries", name: "Groceries" },
];
// Wednesday Oct 14, 2026, 10:00 in Los Angeles (golden context A)
const WEDNESDAY_10AM = "2026-10-14T10:00:00-07:00";
// Friday Oct 16, 2026, 18:30 in Los Angeles (golden context B)
const FRIDAY_630PM = "2026-10-16T18:30:00-07:00";
// Saturday Mar 13, 2027, 16:00 in Chicago (golden context D)
const SATURDAY_4PM_CHICAGO = "2027-03-13T16:00:00-06:00";
// Monday Dec 28, 2026, 09:00 in London (golden context E)
const MONDAY_9AM_LONDON = "2026-12-28T09:00:00Z";
// Sunday Feb 28, 2027, 11:00 in Kolkata (golden context F)
const SUNDAY_11AM_KOLKATA = "2027-02-28T11:00:00+05:30";
// Sunday Feb 27, 2028, 23:10 in Tokyo, a leap year (golden context H)
const SUNDAY_LATE_TOKYO = "2028-02-27T23:10:00+09:00";

function makeContext(now: string, transcript: string, timeZone = LA): VoiceContext {
  return { transcript, now, timeZone, locale: "en-US", lists: LISTS };
}

function makeReply(fields: Partial<ModelReply>): ModelReply {
  const defaults: ModelReply = {
    isReminder: true, title: "Call mom", notes: null, whenKind: "absolute", minutesFromNow: null,
    daysFromNow: null, date: null, yearMissing: false, weekday: null, weekdayNext: false, time: null,
    ampmStated: false, partOfDay: null, repeat: null, listId: null, whenText: "", confident: true,
  };
  return { ...defaults, ...fields };
}

function whenOf(outcome: VoiceOutcome) {
  if (outcome.status !== "done") {
    return "not-done:" + outcome.reason;
  }
  return (outcome.reminder.date ?? "no date") + " " + (outcome.reminder.time ?? "all-day");
}

function reminderOrThrow(outcome: VoiceOutcome) {
  if (outcome.status !== "done") {
    throw new Error("expected a reminder, got not-done: " + outcome.reason);
  }
  return outcome.reminder;
}

type FixCase = { name: string; now: string; zone?: string; say: string; reply: Partial<ModelReply>; when: string };

// Each case is a reply DeepSeek really gave on 2026-10-16 (golden id in the name), cut to the
// fields that matter, and the result the golden set expects
const FIX_CASES: FixCase[] = [
  // Pattern 1: a time already past today moves to its next occurrence unless "today" was said
  { name: "A-ap-02 at 8am said at 10, model wrote today", now: WEDNESDAY_10AM, say: "remind me at 8am to take my vitamins", reply: { date: "2026-10-14", time: "08:00", ampmStated: true, whenText: "at 8am" }, when: "2026-10-15 08:00" },
  { name: "A-ap-05 at midnight, model wrote today", now: WEDNESDAY_10AM, say: "remind me at midnight to lock the back door", reply: { date: "2026-10-14", time: "00:00", ampmStated: true, whenText: "at midnight" }, when: "2026-10-15 00:00" },
  { name: "A-pod-05 in the morning, model wrote today", now: WEDNESDAY_10AM, say: "remind me in the morning to defrost the freezer", reply: { date: "2026-10-14", partOfDay: "morning", whenText: "in the morning" }, when: "2026-10-15 09:00" },
  { name: "B-hr-01 at 6 said at 18:30, model wrote today", now: FRIDAY_630PM, say: "remind me at 6 to feed the fish", reply: { date: "2026-10-16", time: "06:00", whenText: "at 6" }, when: "2026-10-17 18:00" },
  { name: "a time still ahead today stays today", now: WEDNESDAY_10AM, say: "remind me at 4pm to call mom", reply: { date: "2026-10-14", time: "16:00", ampmStated: true, whenText: "at 4pm" }, when: "2026-10-14 16:00" },
  { name: "A-nd-08 today at 8am said at 10 is still past", now: WEDNESDAY_10AM, say: "remind me today at 8am to stretch", reply: { date: "2026-10-14", time: "08:00", ampmStated: true, whenText: "today at 8am" }, when: "not-done:past" },
  { name: "A-nd-01 yesterday at 5, model wrote today", now: WEDNESDAY_10AM, say: "remind me yesterday at 5 to call Sam", reply: { date: "2026-10-14", time: "17:00", ampmStated: true, whenText: "yesterday at 5" }, when: "not-done:past" },
  { name: "D-hr-05 at 3:15 tomorrow", now: SATURDAY_4PM_CHICAGO, zone: "America/Chicago", say: "remind me at 3:15 tomorrow to take the cake out", reply: { date: "2027-03-15", time: "03:15", whenText: "at 3:15 tomorrow" }, when: "2027-03-14 15:15" },
  // Pattern 2: the weekday is read from the words, the date is worked out in code
  { name: "A-wk-05 Wednesday at 8am said Wednesday 10:00", now: WEDNESDAY_10AM, say: "remind me Wednesday at 8am to pay the gardener", reply: { date: "2026-10-14", time: "08:00", ampmStated: true, whenText: "Wednesday at 8am" }, when: "2026-10-21 08:00" },
  { name: "A-wk-04 on Wednesday said on a Wednesday is today", now: WEDNESDAY_10AM, say: "remind me on Wednesday to take out the recycling", reply: { date: "2026-10-21", whenText: "on Wednesday" }, when: "2026-10-14 all-day" },
  { name: "A-tw-06 on Thursday, the Friday in the title ignored", now: WEDNESDAY_10AM, say: "remind me to order the Friday pizza on Thursday", reply: { date: "2026-10-22", whenText: "on Thursday" }, when: "2026-10-15 all-day" },
  { name: "B-fri-01 Friday at 9pm said Friday 18:30", now: FRIDAY_630PM, say: "remind me Friday at 9pm to call Leo", reply: { date: "2026-10-23", time: "21:00", ampmStated: true, whenText: "Friday at 9pm" }, when: "2026-10-16 21:00" },
  { name: "B-fri-05 on Friday at 7 said Friday 18:30", now: FRIDAY_630PM, say: "remind me on Friday at 7 to order takeout", reply: { date: "2026-10-23", time: "07:00", whenText: "on Friday at 7" }, when: "2026-10-16 19:00" },
  { name: "D-wk-03 next Sunday said on a Saturday", now: SATURDAY_4PM_CHICAGO, zone: "America/Chicago", say: "remind me next Sunday to call aunt Rosa", reply: { date: "2027-03-21", whenText: "next Sunday" }, when: "2027-03-14 all-day" },
  { name: "H-wk-02 Sunday said on a Sunday night", now: SUNDAY_LATE_TOKYO, zone: "Asia/Tokyo", say: "remind me Sunday to clean the room", reply: { whenKind: "relative", date: "2028-03-05", whenText: "Sunday" }, when: "2028-02-27 all-day" },
  { name: "Wednesday at 9 said Wednesday 10:00 is 21:00 today", now: WEDNESDAY_10AM, say: "remind me Wednesday at 9 to call mom", reply: { weekday: 3, time: "09:00", whenText: "Wednesday at 9" }, when: "2026-10-14 21:00" },
  // Pattern 5: the said day of the month stands; a time that was not said is dropped
  { name: "E-cal-03 February 29th in a common year", now: MONDAY_9AM_LONDON, zone: "Europe/London", say: "remind me on February 29th to renew the lease", reply: { date: "2027-02-28", yearMissing: true, whenText: "on February 29th" }, when: "not-done:bad-date" },
  { name: "H-leap-05 on the 30th said on Feb 27 skips February", now: SUNDAY_LATE_TOKYO, zone: "Asia/Tokyo", say: "remind me on the 30th to submit the essay", reply: { date: "2028-02-29", yearMissing: true, whenText: "on the 30th" }, when: "2028-03-30 all-day" },
  { name: "E-rep-01 every year on December 25th said Dec 28", now: MONDAY_9AM_LONDON, zone: "Europe/London", say: "remind me every year on December 25th to call grandad", reply: { date: "2026-12-25", repeat: { every: "year", interval: 1, weekdays: [] }, whenText: "every year on December 25th" }, when: "2027-12-25 all-day" },
  { name: "A-tw-04 the 9 o'clock show is not the reminder time", now: WEDNESDAY_10AM, say: "remind me to buy tickets for the 9 o'clock show tomorrow", reply: { date: "2026-10-15", time: "09:00", whenText: "tomorrow" }, when: "2026-10-15 all-day" },
  { name: "D-wk-04 the 5pm in the note is not the reminder time", now: SATURDAY_4PM_CHICAGO, zone: "America/Chicago", say: "remind me Friday to submit the grant, add note deadline is 5pm", reply: { date: "2027-03-19", time: "17:00", ampmStated: true, whenText: "Friday" }, when: "2027-03-19 all-day" },
  { name: "A-rep-14 Sunday night is tonight's 20:00", now: WEDNESDAY_10AM, say: "remind me every week on Sunday night to set out the trash cans", reply: { date: "2026-10-18", partOfDay: "evening", repeat: { every: "week", interval: 1, weekdays: [] }, whenText: "every week on Sunday night" }, when: "2026-10-18 20:00" },
  { name: "A-rep-11 every morning with no when words", now: WEDNESDAY_10AM, say: "remind me every morning to make the bed", reply: { whenKind: "none", repeat: { every: "day", interval: 1, weekdays: [] } }, when: "2026-10-15 09:00" },
];

describe("fix pass: the app settles the day from the when words", () => {
  for (const fixCase of FIX_CASES) {
    it(fixCase.name + " -> " + fixCase.when, () => {
      const context = makeContext(fixCase.now, fixCase.say, fixCase.zone ?? LA);
      const outcome = resolveReply(makeReply(fixCase.reply), context);
      expect(whenOf(outcome)).toBe(fixCase.when);
    });
  }

  it("leaves a reply with no when words exactly as the model gave it", () => {
    const context = makeContext(WEDNESDAY_10AM, "remind me Wednesday to call mom");
    const outcome = resolveReply(makeReply({ date: "2026-10-21" }), context);
    expect(whenOf(outcome)).toBe("2026-10-21 all-day");
  });

  it("keeps the model's date when the words name a month and a day", () => {
    const context = makeContext(WEDNESDAY_10AM, "remind me on Friday October 23rd to call mom");
    const outcome = resolveReply(makeReply({ date: "2026-10-23", whenText: "on Friday October 23rd" }), context);
    expect(whenOf(outcome)).toBe("2026-10-23 all-day");
  });

  it("keeps two named weekdays as the model's weekly repeat", () => {
    const context = makeContext(WEDNESDAY_10AM, "remind me every Monday and Thursday at 9am to call mom");
    const reply = makeReply({ time: "09:00", ampmStated: true, repeat: { every: "week", interval: 1, weekdays: [1, 4] }, whenText: "every Monday and Thursday at 9am" });
    const reminder = reminderOrThrow(resolveReply(reply, context));
    expect(reminder.date).toBe("2026-10-15");
    expect(reminder.repeat).toEqual({ every: "week", weekdays: [1, 4] });
  });

  it("turns every weekday said as a daily repeat into Monday to Friday", () => {
    const context = makeContext(MONDAY_9AM_LONDON, "remind me every weekday at 8:30am to do the school run", "Europe/London");
    const reply = makeReply({ date: "2026-12-29", time: "08:30", ampmStated: true, repeat: { every: "day", interval: 1, weekdays: [] }, whenText: "every weekday at 8:30am" });
    const reminder = reminderOrThrow(resolveReply(reply, context));
    expect(reminder.repeat).toEqual({ every: "week", weekdays: [1, 2, 3, 4, 5] });
    expect(reminder.date).toBe("2026-12-29");
  });

  it("starts a monthly repeat on the said day of the month, today included", () => {
    const context = makeContext(SUNDAY_11AM_KOLKATA, "remind me every month on the 28th to pay the maid", "Asia/Kolkata");
    const reply = makeReply({ date: "2027-03-28", repeat: { every: "month", interval: 1, weekdays: [] }, whenText: "every month on the 28th" });
    expect(whenOf(resolveReply(reply, context))).toBe("2027-02-28 all-day");
  });

  it("reads the when words: weekday, next, day offset, month, day of month, clock, part of day", () => {
    expect(readWhenWords("next Tuesday at 9")).toMatchObject({ weekdays: [2], saysNext: true, saysClock: true, dayOffset: null });
    expect(readWhenWords("the day after tomorrow")).toMatchObject({ dayOffset: 2, saysClock: false });
    expect(readWhenWords("on the 30th")).toMatchObject({ dayOfMonth: 30, monthNamed: false, saysClock: false });
    expect(readWhenWords("March 3rd 2027")).toMatchObject({ dayOfMonth: 3, monthNamed: true, yearSaid: true });
    expect(readWhenWords("Sunday night")).toMatchObject({ weekdays: [0], partOfDay: "tonight" });
    expect(readWhenWords("every morning and evening").partOfDay).toBe(null);
    expect(readWhenWords("on fridays at noon")).toMatchObject({ weekdays: [5], saysClock: true });
  });
});

describe("fix pass: weekly repeats name their weekday, as the page reads them", () => {
  it("B-fri-07 every Friday at 8pm with no weekdays gets [5]", () => {
    const context = makeContext(FRIDAY_630PM, "remind me every Friday at 8pm to call grandma");
    const reply = makeReply({ date: "2026-10-16", time: "20:00", ampmStated: true, repeat: { every: "week", interval: 1, weekdays: [] }, whenText: "every Friday at 8pm" });
    const reminder = reminderOrThrow(resolveReply(reply, context));
    expect(reminder.date).toBe("2026-10-16");
    expect(reminder.repeat).toEqual({ every: "week", weekdays: [5] });
  });

  it("A-rep-04 every other week with no day takes the start day's weekday", () => {
    const context = makeContext(WEDNESDAY_10AM, "remind me every other week to clean the fridge");
    const reply = makeReply({ whenKind: "none", repeat: { every: "week", interval: 2, weekdays: [] } });
    const reminder = reminderOrThrow(resolveReply(reply, context));
    expect(reminder.repeat).toEqual({ every: "week", interval: 2, weekdays: [3] });
  });

  it("the page places a weekly repeat the same with and without the start weekday written out", () => {
    function itemWith(repeat: Record<string, unknown>) {
      return {
        id: "abc123def456", title: "Call grandma", notes: "", list: null, date: "2026-10-16", time: "20:00",
        repeat, timeZone: LA, done: false, completedAt: null, snoozedUntil: null, lastDoneAt: null,
        doneThrough: null, createdAt: "2026-10-16T17:00:00.000Z", source: null,
      };
    }
    function placementDays(item: Record<string, unknown>, nowIso: string) {
      const placement = pageLogic.placeItem(item, nowIso, LA);
      const parts: string[] = [];
      for (const slot of ["today", "upcoming", "overdue"]) {
        const entry = placement[slot];
        parts.push(slot + "=" + (entry ? entry.day + " " + entry.time : "none"));
      }
      return parts.join(", ");
    }
    const bare = itemWith({ every: "week", interval: 2 });
    const written = itemWith({ every: "week", interval: 2, weekdays: [5] });
    for (let offset = 0; offset < 40; offset += 1) {
      const nowIso = new Date(Date.parse("2026-10-16T19:00:00-07:00") + offset * 86400000).toISOString();
      expect(placementDays(written, nowIso), nowIso).toBe(placementDays(bare, nowIso));
    }
  });

  it("the scorer counts a weekly repeat without weekdays as its start day's weekday", () => {
    const expected = { title: "Call grandma", date: "2026-10-16", time: "20:00", repeat: { every: "week", weekdays: [5] } };
    function doneWith(repeat: Record<string, unknown>) {
      const reminder = { title: "Call grandma", notes: null, list: null, date: "2026-10-16", time: "20:00", allDay: false, at: null, repeat, timeZone: LA };
      return { status: "done", reminder };
    }
    expect(scoreCase(expected, doneWith({ every: "week" })).wrongFields).toEqual([]);
    expect(scoreCase(expected, doneWith({ every: "week", weekdays: [4] })).wrongFields).toEqual(["repeat"]);
  });
});

describe("fix pass: add <thing> to <list>", () => {
  it("A-list-06 Add bananas to groceries is Bananas on Groceries", () => {
    expect(splitListAddTitle("Add bananas to groceries", "list:groceries", LISTS)).toEqual({ title: "Bananas", listId: "list:groceries" });
  });

  it("finds the list from the words when the model gave none", () => {
    expect(splitListAddTitle("Add milk and bread to my groceries list", null, LISTS)).toEqual({ title: "Milk and bread", listId: "list:groceries" });
  });

  it("A-list-08 a list that does not exist gives the task alone and no list", () => {
    expect(splitListAddTitle("Add renew my passport to my travel list", null, LISTS)).toEqual({ title: "Renew my passport", listId: null });
  });

  it("leaves add <thing> to <something that is not a list> as said", () => {
    expect(splitListAddTitle("Add sugar to the coffee", null, LISTS)).toEqual({ title: "Add sugar to the coffee", listId: null });
    expect(splitListAddTitle("Call the bank", null, LISTS)).toEqual({ title: "Call the bank", listId: null });
  });

  it("the resolver saves the short title on the list", () => {
    const context = makeContext(WEDNESDAY_10AM, "add bananas to groceries");
    const reminder = reminderOrThrow(resolveReply(makeReply({ title: "Add bananas to groceries", whenKind: "none", listId: "list:groceries" }), context));
    expect(reminder.title).toBe("Bananas");
    expect(reminder.list).toBe("list:groceries");
    expect(reminder.date).toBe(null);
  });
});

describe("fix pass: the reply text, the prompt and the request", () => {
  it("reads a reply that starts with a stray brace (reasoning low, B-rel-04)", () => {
    const context = makeContext(FRIDAY_630PM, "remind me in 3 hours to switch the laundry");
    const reply = makeReply({ title: "Switch the laundry", whenKind: "relative", minutesFromNow: 180, whenText: "in 3 hours" });
    const outcome = outcomeFromModelContent("{\n" + JSON.stringify(reply, null, 2), context);
    expect(whenOf(outcome)).toBe("2026-10-16 21:30");
  });

  it("still refuses text with no JSON object in it", () => {
    const context = makeContext(FRIDAY_630PM, "remind me in 3 hours to switch the laundry");
    expect(parseJsonObjectText("Sure, here you go")).toBe(undefined);
    expect(parseJsonObjectText("{ not json }")).toBe(undefined);
    expect(outcomeFromModelContent("{ \"isReminder\": tru", context)).toMatchObject({ status: "not-done", reason: "bad-reply" });
  });

  it("tells the model to leave the date to the app and the new title and list rules", () => {
    const system = buildPrompt(makeContext(WEDNESDAY_10AM, "x")).system;
    expect(system).toContain("never today's date, even when that time has passed");
    expect(system).toContain("put it in weekday and let the app find the date");
    expect(system).toContain("\"add bananas to groceries\" =\n  \"Bananas\"");
    expect(system).toContain("\"turn off the lights\"");
    expect(system).toContain("\"call the family\" is not the Family list");
    expect(system).toContain("\"note deadline is 5pm\": time null");
    expect(system).not.toContain("\"this Friday\"-style days you can read off the table");
  });

  it("caps the reply tokens so a reasoning run cannot go on for ever", () => {
    const body = buildOpenRouterRequest(makeContext(WEDNESDAY_10AM, "x"), { reasoning: "low" });
    expect(MAX_REPLY_TOKENS).toBe(2000);
    expect(body.max_tokens).toBe(2000);
  });
});

describe("fix pass: the eval script", () => {
  function goldenContext() {
    return { ...golden.contexts.A, transcript: "remind me in 20 minutes to check the oven" };
  }

  function steppingClock() {
    let now = 0;
    function readClock() {
      now += 100;
      return now;
    }
    return readClock;
  }

  it("tries a timed-out call once more and keeps the second answer", async () => {
    let calls = 0;
    async function flakyFetch() {
      calls += 1;
      if (calls === 1) {
        const abort = new Error("aborted");
        abort.name = "AbortError";
        throw abort;
      }
      const payload = { provider: "DeepInfra", choices: [{ finish_reason: "stop", message: { content: "{}" } }], usage: { cost: 0.0002, completion_tokens: 90 } };
      return { ok: true, status: 200, json: async () => payload };
    }
    const call = await callModel({ context: goldenContext(), reasoning: "low", apiKey: "k", fetchImpl: flakyFetch, clock: steppingClock(), model: undefined });
    expect(calls).toBe(2);
    expect(call.ok).toBe(true);
    expect(call.attempts).toBe(2);
    expect(call.details).toMatchObject({ provider: "DeepInfra", finishReason: "stop" });
    expect(call.cost).toBeCloseTo(0.0002, 10);
  });

  it("gives up after two timeouts and does not retry a 400", async () => {
    let timeoutCalls = 0;
    async function alwaysTimesOut() {
      timeoutCalls += 1;
      const abort = new Error("aborted");
      abort.name = "AbortError";
      throw abort;
    }
    const timedOut = await callModel({ context: goldenContext(), reasoning: "low", apiKey: "k", fetchImpl: alwaysTimesOut, clock: steppingClock(), model: undefined });
    expect(timeoutCalls).toBe(2);
    expect(timedOut).toMatchObject({ ok: false, error: "timeout", attempts: 2 });

    let badRequestCalls = 0;
    async function badRequest() {
      badRequestCalls += 1;
      return { ok: false, status: 400, json: async () => ({}) };
    }
    const rejected = await callModel({ context: goldenContext(), reasoning: "low", apiKey: "k", fetchImpl: badRequest, clock: steppingClock(), model: undefined });
    expect(badRequestCalls).toBe(1);
    expect(rejected).toMatchObject({ ok: false, error: "HTTP 400", attempts: 1 });
  });

  it("aborts a call that runs past the timeout it was given", async () => {
    function hangingFetch(_url: string, init: { signal: AbortSignal }) {
      return new Promise((_resolve, reject) => {
        function rejectOnAbort() {
          const abort = new Error("aborted");
          abort.name = "AbortError";
          reject(abort);
        }
        init.signal.addEventListener("abort", rejectOnAbort);
      });
    }
    const call = await callModel({ context: goldenContext(), reasoning: "low", apiKey: "k", fetchImpl: hangingFetch, clock: steppingClock(), model: undefined, timeoutMs: 20 });
    expect(call).toMatchObject({ ok: false, error: "timeout", attempts: 2 });
  });

  it("reads --timeout in seconds and --replay, and defaults to 60 s", () => {
    expect(parseArgs([]).timeoutMs).toBe(60000);
    expect(parseArgs(["--timeout", "30"]).timeoutMs).toBe(30000);
    expect(parseArgs(["--replay", "old.json"]).replay).toBe("old.json");
    expect(() => parseArgs(["--timeout", "soon"])).toThrow("--timeout");
  });

  it("replays the 2026-10-16 replies: reasoning off fails only on what needs the new prompt", () => {
    const offRun = replayRun(golden, recordedRun.runs[0]);
    const failing: string[] = [];
    for (const result of offRun.results) {
      if (!result.score.pass) {
        failing.push(result.id);
      }
    }
    expect(offRun.reasoning).toBe("off");
    expect(offRun.summary.total).toBe(300);
    // Was 42 failures (86.0% pass). Left: not confident about an unknown list, a light switch
    // taken as a reminder, and "call the family" put on the Family list
    expect(failing).toEqual(["A-list-08", "C-nr-01", "E-ye-02"]);
  });

  it("replays the 2026-10-16 replies: reasoning low fails only on timeouts and the new-prompt cases", () => {
    const lowRun = replayRun(golden, recordedRun.runs[1]);
    const failingWithReply: string[] = [];
    let timeouts = 0;
    for (const result of lowRun.results) {
      if (result.error === "timeout") {
        timeouts += 1;
      } else if (!result.score.pass) {
        failingWithReply.push(result.id);
      }
    }
    expect(lowRun.reasoning).toBe("low");
    expect(timeouts).toBe(63);
    expect(failingWithReply).toEqual(["A-list-06", "A-tw-04", "C-nr-01", "E-list-01"]);
  });

  it("main --replay writes a report without a key and without calling anything", async () => {
    const folder = mkdtempSync(join(tmpdir(), "voice-replay-"));
    const prefix = join(folder, "replay");
    async function forbiddenFetch(): Promise<never> {
      throw new Error("replay must not call the model");
    }
    const replayPath = new URL("../scripts/voice-replies-2026-10-16.json", import.meta.url).pathname;
    const finished = await main(["--replay", replayPath, "--out", prefix], {}, forbiddenFetch);
    const report = readFileSync(prefix + ".md", "utf8");
    expect(finished.runs.length).toBe(2);
    expect(report).toContain("replay of 2026-10-16T07:02:00.131Z, no calls");
    expect(report).toContain("| Exact and title (pass) | 99.0% |");
  });
});
