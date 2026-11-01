// Water, build 22 (founder, 2026-10-31, docs/briefs/build-22-2026-10-31.md "Water and Reminders"):
// - Water remove (Amogh asked; CONCERNS #19): removing a drink is easy to find (Today's amount opens
//   the Log, each day of the week strip opens that day) and works for earlier days too (each
//   earlier day in the Log opens a Day screen with an × on every drink and on "From widget").
//   jess gets the same as hydration.remove.
// - The widget at 0 L, option A of docs/mockups/water-zero-and-help-2026-10-27.html part 1: the
//   page sends a fill `floor` of 0.1 so an empty day still shows a thin low tide.
process.env.TZ = "America/Los_Angeles";

import { readFileSync } from "node:fs";
import vm from "node:vm";
import { describe, expect, it } from "vitest";
import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import { loadToolsScript, sidekickToolsProblems } from "../scripts/sidekick-tools.mjs";

const folder = new URL("../../sidekicks/hydration/", import.meta.url);
const html = readFileSync(new URL("index.html", folder), "utf8");
const toolsText = readFileSync(new URL("tools.js", folder), "utf8");
const manifest = JSON.parse(readFileSync(new URL("manifest.json", folder), "utf8"));

type Value = Record<string, unknown>;
type StoreRequest = { op: string; key?: string; prefix?: string; value?: Value };
type Outcome = { ops?: Array<{ op: string; key: string; value?: Value }>; refused?: string; result: { text: string; [field: string]: unknown } };

/* ---------- The page, run in a sandbox ---------- */

function pageScript(pageHtml: string) {
  const start = pageHtml.indexOf("<script>") + "<script>".length;
  const end = pageHtml.indexOf("</script>", start);
  return pageHtml.slice(start, end);
}

function settingsValue(): Value {
  return {
    $type: "hydration.settings", goalMl: 2500, unit: "ml", presetsMl: [250, 500, 750], remindStart: "09:00", remindEnd: "21:00",
    everyHours: 2, remindersOn: false, createdAt: "2026-10-01T00:00:00.000Z",
  };
}

function localDateKey(daysAgo: number) {
  const date = new Date(Date.now() - daysAgo * 86400000);
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return date.getFullYear() + "-" + month + "-" + day;
}

// Noon of a local date, as an ISO instant
function noonOf(dateKey: string, minute = 0) {
  const [year, month, day] = dateKey.split("-").map(Number);
  return new Date(year, month - 1, day, 12, minute).toISOString();
}

function waitForWrites() {
  return new Promise((resolve) => setTimeout(resolve, 30));
}

type Page = {
  html: () => string;
  click: (dataset: Record<string, string>) => Promise<void>;
  records: Map<string, Value>;
};

async function openPage(dayRecords: Array<[string, Value]>): Promise<Page> {
  const records = new Map<string, Value>([["settings:main", settingsValue()], ...dayRecords]);
  const main = { innerHTML: "", setAttribute() {} };
  const listeners: Record<string, (event: unknown) => void> = {};

  function storeReply(request: StoreRequest): Value {
    if (request.op === "get") {
      const key = String(request.key);
      return { ok: true, value: records.has(key) ? records.get(key) : null };
    }
    if (request.op === "query") {
      const prefix = String(request.prefix ?? "");
      const found: Array<{ key: string; value: Value }> = [];
      for (const [key, value] of records) {
        if (key.startsWith(prefix)) {
          found.push({ key, value });
        }
      }
      return { ok: true, records: found };
    }
    if (request.op === "set" && request.key) {
      records.set(request.key, request.value as Value);
    }
    return { ok: true };
  }

  async function fetchFromPage(_url: string, options: { body: string }) {
    const reply = storeReply(JSON.parse(options.body) as StoreRequest);
    return { json: async () => reply };
  }

  function elementById(id: string) {
    return id === "main" ? main : { innerHTML: "", setAttribute() {} };
  }

  function listen(name: string, listener: (event: unknown) => void) {
    listeners[name] = listener;
  }

  function ignore() {
    // timers, scrolling and window listeners are not part of this check
  }

  const sandbox: Value = {
    window: { location: { origin: "sidekick://hydration" }, innerWidth: 402, innerHeight: 874, addEventListener: ignore, scrollTo: ignore },
    document: { hidden: false, getElementById: elementById, addEventListener: listen },
    fetch: fetchFromPage,
    console: { warn: ignore, log: ignore },
    setTimeout, clearTimeout, setInterval: ignore,
    Intl, Date, Math, JSON, Promise, Array, Object, String, Number,
  };
  vm.createContext(sandbox);
  vm.runInContext(pageScript(html) + "\n;globalThis.__app = WaterApp;", sandbox);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const app = sandbox.__app as any;
  await app.whenReady();

  async function click(dataset: Record<string, string>) {
    const target = { dataset, tagName: "BUTTON", closest: () => target };
    listeners.click({ target });
    await waitForWrites();
  }

  return { html: () => main.innerHTML, click, records };
}

function dayRecord(entries: Array<{ at: string; ml: number }>, extraMl = 0): Value {
  let total = extraMl;
  for (const entry of entries) {
    total += entry.ml;
  }
  return { $type: "hydration.day", ml: total, goalMl: 2500, entries };
}

/* ---------- Finding it ---------- */

describe("Water remove: easy to find", () => {
  it("Today's amount opens the Log, and each day of the week strip opens that day", async () => {
    const page = await openPage([]);
    const today = page.html();
    expect(today).toMatch(/<div class="amount"[^>]*data-action="show-log"/);
    expect(today).toContain('data-action="show-day" data-date="' + localDateKey(2) + '"');
    expect(today).toContain('data-action="show-day" data-date="' + localDateKey(0) + '"');
  });

  it("each earlier day in the Log opens its Day screen with an × on every drink", async () => {
    const yesterday = localDateKey(1);
    const first = { at: noonOf(yesterday, 0), ml: 500 };
    const second = { at: noonOf(yesterday, 30), ml: 250 };
    const page = await openPage([["water:" + yesterday, dayRecord([first, second], 300)]]);
    await page.click({ action: "show-log" });
    expect(page.html()).toContain('<button class="row open" data-action="show-day" data-date="' + yesterday + '"');
    await page.click({ action: "show-day", date: yesterday });
    const dayScreen = page.html();
    expect(dayScreen).toContain('data-action="show-log"');
    expect(dayScreen).toContain('data-action="remove-entry" data-at="' + first.at + '" data-date="' + yesterday + '"');
    expect(dayScreen).toContain('data-action="remove-entry" data-at="' + second.at + '" data-date="' + yesterday + '"');
    expect(dayScreen).toContain("From widget");
    expect(dayScreen).toContain('data-action="remove-widget-amount" data-date="' + yesterday + '"');
  });

  it("today's day in the week strip opens the Log, not a Day screen", async () => {
    const page = await openPage([]);
    await page.click({ action: "show-day", date: localDateKey(0) });
    expect(page.html()).toContain('<div class="lab">Today</div>');
  });
});

/* ---------- Removing on an earlier day ---------- */

describe("Water remove: earlier days", () => {
  it("the × on an earlier day's drink takes it and its ml off that day only", async () => {
    const yesterday = localDateKey(1);
    const today = localDateKey(0);
    const kept = { at: noonOf(yesterday, 0), ml: 500 };
    const removed = { at: noonOf(yesterday, 30), ml: 250 };
    const todayDrink = { at: new Date().toISOString(), ml: 750 };
    const page = await openPage([
      ["water:" + yesterday, dayRecord([kept, removed])],
      ["water:" + today, dayRecord([todayDrink])],
    ]);
    await page.click({ action: "show-day", date: yesterday });
    await page.click({ action: "remove-entry", at: removed.at, date: yesterday });
    const after = page.records.get("water:" + yesterday) as Value;
    expect(after.ml).toBe(500);
    expect(after.entries).toEqual([kept]);
    expect((page.records.get("water:" + today) as Value).ml).toBe(750);
    expect(page.html()).not.toContain(removed.at);
    expect(page.html()).toContain(kept.at);
  });

  it("the × on an earlier day's From widget takes the widget's amount off", async () => {
    const twoDaysAgo = localDateKey(2);
    const drink = { at: noonOf(twoDaysAgo), ml: 500 };
    const page = await openPage([["water:" + twoDaysAgo, dayRecord([drink], 750)]]);
    await page.click({ action: "show-day", date: twoDaysAgo });
    await page.click({ action: "remove-widget-amount", date: twoDaysAgo });
    expect((page.records.get("water:" + twoDaysAgo) as Value).ml).toBe(500);
    expect(page.html()).not.toContain("From widget");
  });

  it("today's × still works without a date", async () => {
    const today = localDateKey(0);
    const drink = { at: new Date(Date.now() - 60000).toISOString(), ml: 250 };
    const page = await openPage([["water:" + today, dayRecord([drink])]]);
    await page.click({ action: "remove-entry", at: drink.at });
    expect((page.records.get("water:" + today) as Value).ml).toBe(0);
  });
});

/* ---------- jess: hydration.remove ---------- */

const loaded = loadToolsScript(toolsText);
if (!("tools" in loaded)) {
  throw new Error(loaded.problem);
}
const tools = loaded.tools;
// Sunday Oct 25, 2026, 12:30 in Los Angeles
const NOW = "2026-10-25T19:30:00.000Z";

function toolRecords(): Array<{ key: string; value: Value }> {
  return [
    { key: "settings:main", value: settingsValue() },
    {
      key: "water:2026-10-24",
      value: {
        $type: "hydration.day", ml: 1750, goalMl: 2500,
        entries: [{ at: "2026-10-24T16:00:00.000Z", ml: 500 }, { at: "2026-10-24T20:00:00.000Z", ml: 500 }, { at: "2026-10-24T18:00:00.000Z", ml: 250 }],
      },
    },
    { key: "water:2026-10-25", value: { $type: "hydration.day", ml: 750, goalMl: 2500, entries: [{ at: "2026-10-25T16:10:00.000Z", ml: 500 }, { at: "2026-10-25T18:40:00.000Z", ml: 250 }] } },
  ];
}

function callRemove(input: Value): Outcome {
  const full = { date: null, amount: null, unit: null, fromWidget: null, ...input };
  return JSON.parse(JSON.stringify(tools.handlers.remove(full, toolRecords(), NOW)));
}

function written(outcome: Outcome, key: string): Value {
  for (const op of outcome.ops || []) {
    if (op.key === key) {
      return op.value as Value;
    }
  }
  throw new Error("nothing written to " + key);
}

function expectValidWrites(outcome: Outcome) {
  expect(outcome.refused).toBeUndefined();
  for (const op of outcome.ops || []) {
    const stamped = MidasRecordSchema.stampType(manifest.types, op.key, op.value);
    expect(MidasRecordSchema.checkRecord(manifest.types, op.key, stamped), op.key).toBeNull();
  }
}

describe("hydration.remove", () => {
  it("is in the manifest, wired to the page's × buttons, and passes the tools gate", () => {
    const names: string[] = [];
    for (const tool of manifest.agent.tools) {
      names.push(tool.name);
    }
    expect(names).toContain("hydration.remove");
    let removeTool: Value | null = null;
    for (const tool of manifest.agent.tools) {
      if (tool.name === "hydration.remove") {
        removeTool = tool;
      }
    }
    const meta = (removeTool as Value)._meta as Value;
    expect(meta["midas/page-actions"]).toEqual(["remove-entry", "remove-widget-amount"]);
    expect(typeof tools.handlers.remove).toBe("function");
    expect(sidekickToolsProblems(manifest, toolsText, html, "hydration")).toEqual([]);
  });

  it("with nothing said, takes today's latest drink", () => {
    const outcome = callRemove({});
    expectValidWrites(outcome);
    const today = written(outcome, "water:2026-10-25");
    expect(today.ml).toBe(500);
    expect(today.entries).toEqual([{ at: "2026-10-25T16:10:00.000Z", ml: 500 }]);
    expect(outcome.result.text).toBe("Removed 250 ml");
  });

  it("on an earlier day, takes the latest drink of the amount said", () => {
    const outcome = callRemove({ date: "2026-10-24", amount: 0.5, unit: "l" });
    expectValidWrites(outcome);
    const day = written(outcome, "water:2026-10-24");
    expect(day.ml).toBe(1250);
    expect(day.entries).toEqual([{ at: "2026-10-24T16:00:00.000Z", ml: 500 }, { at: "2026-10-24T18:00:00.000Z", ml: 250 }]);
    expect(outcome.result.date).toBe("2026-10-24");
  });

  it("takes what the widget added that day", () => {
    const outcome = callRemove({ date: "2026-10-24", fromWidget: true });
    expectValidWrites(outcome);
    expect(written(outcome, "water:2026-10-24").ml).toBe(1250);
    expect(outcome.result.text).toBe("Removed 500 ml");
  });

  it("refuses a later day, a drink that is not there and an empty widget amount, writing nothing", () => {
    const later = callRemove({ date: "2026-10-26" });
    expect(later.refused).toBe("day-not-offered");
    expect(later.ops).toBeUndefined();
    const missing = callRemove({ date: "2026-10-24", amount: 900, unit: "ml" });
    expect(missing.refused).toBe("nothing-to-remove");
    const noDay = callRemove({ date: "2026-10-20" });
    expect(noDay.refused).toBe("nothing-to-remove");
    const noWidget = callRemove({ fromWidget: true });
    expect(noWidget.refused).toBe("nothing-to-remove");
  });
});

/* ---------- The widget at 0 L: a floor ---------- */

function waterLogicSource(pageHtml: string) {
  const start = pageHtml.indexOf("var WaterLogic = (function createWaterLogic() {");
  const end = pageHtml.indexOf("\n})();\n", start) + "\n})();\n".length;
  return pageHtml.slice(start, end);
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const Logic: any = vm.runInNewContext(waterLogicSource(html) + "\n;WaterLogic;", {});

describe("Water widget at 0 L (option A, low tide)", () => {
  it("every size of the Tide widget, and its older-build fallback, sends a floor of 0.1 on the sea", () => {
    const entries = JSON.parse(JSON.stringify(Logic.widgetRecords(Logic.settingsFrom({ unit: "l", goalMl: 2500 }))));
    expect(entries.length).toBe(1);
    for (const widget of [entries[0].value, entries[0].fallback]) {
      for (const size of ["small", "medium", "large"]) {
        expect(widget[size].fill, size).toBeDefined();
        expect(widget[size].floor, size).toBe(0.1);
      }
    }
  });

  it("the plain stand-in has no sea, so no floor", () => {
    const entries = JSON.parse(JSON.stringify(Logic.widgetRecords(Logic.settingsFrom({ unit: "ml", goalMl: 2000 }))));
    expect(JSON.stringify(entries[0].plain)).not.toContain('"floor"');
  });
});
