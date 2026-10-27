// Water, founder 2026-10-27: "The day on the top left should also show 0 days." The streak chip
// replaces the "Water" title on Today (docs/PRODUCT.md, "Water's help menu"), so it is there on
// every day, 0 days included.
process.env.TZ = "America/Los_Angeles";

import { readFileSync } from "node:fs";
import vm from "node:vm";
import { describe, expect, it } from "vitest";

const html = readFileSync(new URL("../../sidekicks/hydration/index.html", import.meta.url), "utf8");

type Value = Record<string, unknown>;
type StoreRequest = { op: string; key?: string; prefix?: string };

function pageScript(pageHtml: string) {
  const start = pageHtml.indexOf("<script>") + "<script>".length;
  const end = pageHtml.indexOf("</script>", start);
  return pageHtml.slice(start, end);
}

function settingsValue(): Value {
  return {
    $type: "hydration.settings", goalMl: 2500, unit: "ml", presetsMl: [250, 500, 750], remindStart: "09:00", remindEnd: "21:00",
    everyHours: 2, remindersOn: true, createdAt: "2026-10-01T00:00:00.000Z",
  };
}

function localDateKey(daysAgo: number) {
  const date = new Date(Date.now() - daysAgo * 86400000);
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return date.getFullYear() + "-" + month + "-" + day;
}

function dayValue(dateKey: string, ml: number): Value {
  return { $type: "hydration.day", date: dateKey, ml, entries: [] };
}

// Answers the page's store protocol from a fixed set of records
function storeReply(records: Map<string, Value>, request: StoreRequest): Value {
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
  return { ok: true };
}

async function todayHtml(dayRecords: Array<[string, Value]>) {
  const records = new Map<string, Value>([["settings:main", settingsValue()], ...dayRecords]);
  const main = { innerHTML: "", setAttribute() {} };

  async function fetchFromPage(_url: string, options: { body: string }) {
    const reply = storeReply(records, JSON.parse(options.body) as StoreRequest);
    return { json: async () => reply };
  }

  function elementById(id: string) {
    return id === "main" ? main : { innerHTML: "", setAttribute() {} };
  }

  function ignore() {
    // timers, scrolling and listeners are not part of this check
  }

  const sandbox: Value = {
    window: { location: { origin: "sidekick://hydration" }, innerWidth: 402, innerHeight: 874, addEventListener: ignore, scrollTo: ignore },
    document: { hidden: false, getElementById: elementById, addEventListener: ignore },
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
  return main.innerHTML;
}

function streakChip(pageHtml: string) {
  const match = /<div class="streak-chip">[\s\S]*?<\/div>/.exec(pageHtml);
  return match ? match[0] : "";
}

describe("Water: the streak chip on Today", () => {
  it("shows 0 days when nothing is logged", async () => {
    const pageHtml = await todayHtml([]);
    expect(streakChip(pageHtml)).toContain("<span>0 days</span>");
  });

  it("shows 0 days when yesterday missed the goal and today has not met it yet", async () => {
    const yesterday = localDateKey(1);
    const today = localDateKey(0);
    const pageHtml = await todayHtml([
      ["water:" + yesterday, dayValue(yesterday, 1000)],
      ["water:" + today, dayValue(today, 500)],
    ]);
    expect(streakChip(pageHtml)).toContain("<span>0 days</span>");
  });

  it("still shows 1 day and 2 days", async () => {
    const yesterday = localDateKey(1);
    const twoDaysAgo = localDateKey(2);
    const oneDay = await todayHtml([["water:" + yesterday, dayValue(yesterday, 2600)]]);
    expect(streakChip(oneDay)).toContain("<span>1 day</span>");
    const twoDays = await todayHtml([
      ["water:" + twoDaysAgo, dayValue(twoDaysAgo, 2600)],
      ["water:" + yesterday, dayValue(yesterday, 2600)],
    ]);
    expect(streakChip(twoDays)).toContain("<span>2 days</span>");
  });

  it("sits first in the top row, before the ? button", async () => {
    const pageHtml = await todayHtml([]);
    const topRowStart = pageHtml.indexOf('<div class="top-row">');
    const chipAt = pageHtml.indexOf('<div class="streak-chip">');
    const helpAt = pageHtml.indexOf('data-action="toggle-help"');
    expect(topRowStart).toBeGreaterThanOrEqual(0);
    expect(chipAt).toBe(topRowStart + '<div class="top-row">'.length);
    expect(chipAt).toBeLessThan(helpAt);
  });
});
