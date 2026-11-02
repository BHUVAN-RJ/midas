// Build 22 dead-end sweep for App Review guideline 2.1 (lead brief, founder approved 2026-11-01,
// docs/briefs/build-22-2026-10-31.md): screens that had no way forward.
// - Water: "Can't Open Water" had no button and never recovered; it now has "Try Again", which
//   runs the first load again.
// - Reminders: a failure part-way through an Apple Reminders import left the "Importing…" card
//   (no buttons, taps swallowed) on screen for good; it now closes and "Import Failed" shows.
process.env.TZ = "America/Los_Angeles";

import { readFileSync } from "node:fs";
import vm from "node:vm";
import { describe, expect, it } from "vitest";

type Value = Record<string, unknown>;
type StoreRequest = { op: string; key?: string; prefix?: string; value?: Value };

function pageScript(pageHtml: string) {
  const start = pageHtml.indexOf("<script>") + "<script>".length;
  const end = pageHtml.indexOf("</script>", start);
  return pageHtml.slice(start, end);
}

function waitForWrites() {
  return new Promise((resolve) => setTimeout(resolve, 30));
}

/* ---------- Water: Try Again on "Can't Open Water" ---------- */

const waterHtml = readFileSync(new URL("../../sidekicks/hydration/index.html", import.meta.url), "utf8");

function waterSettings(): Value {
  return {
    $type: "hydration.settings", goalMl: 2500, unit: "ml", presetsMl: [250, 500, 750], remindStart: "09:00", remindEnd: "21:00",
    everyHours: 2, remindersOn: false, createdAt: "2026-10-01T00:00:00.000Z",
  };
}

async function openFailingWater() {
  const records = new Map<string, Value>([["settings:main", waterSettings()]]);
  const main = { innerHTML: "", setAttribute() {} };
  const listeners: Record<string, (event: unknown) => void> = {};
  const connection = { up: false };

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

  // The store cannot be reached until the test brings the connection up
  async function fetchFromPage(_url: string, options: { body: string }) {
    if (!connection.up) {
      throw new Error("store unreachable");
    }
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
  vm.runInContext(pageScript(waterHtml) + "\n;globalThis.__app = WaterApp;", sandbox);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const app = sandbox.__app as any;
  await app.whenReady().catch(ignore);
  await waitForWrites();

  async function click(dataset: Record<string, string>) {
    const target = { dataset, tagName: "BUTTON", closest: () => target };
    listeners.click({ target });
    await waitForWrites();
  }

  return { html: () => main.innerHTML, click, connection };
}

describe("Water: the load failure screen has a way forward", () => {
  it("shows Try Again under Can't Open Water", async () => {
    const page = await openFailingWater();
    expect(page.html()).toContain("Can’t Open Water");
    expect(page.html()).toContain('<button class="primary" data-action="retry-load">Try Again</button>');
  });

  it("Try Again opens Water once the store answers", async () => {
    const page = await openFailingWater();
    page.connection.up = true;
    await page.click({ action: "retry-load" });
    expect(page.html()).not.toContain("Can’t Open Water");
    expect(page.html()).toContain('data-action="show-log"');
  });

  it("Try Again while the store still fails shows the failure screen again, with Try Again", async () => {
    const page = await openFailingWater();
    await page.click({ action: "retry-load" });
    expect(page.html()).toContain("Can’t Open Water");
    expect(page.html()).toContain('data-action="retry-load"');
  });
});

/* ---------- Reminders: the Importing… card closes when an import fails ---------- */

const remindersScript = pageScript(readFileSync(new URL("../../sidekicks/reminders/index.html", import.meta.url), "utf8"));

// The page's own bringInTask, run with its helpers replaced by recorders. The whole page needs a
// document this suite does not have; bringInTask is the part that decides what happens on failure.
function remindersBringInTask() {
  const start = remindersScript.indexOf("  function bringInTask(");
  const end = remindersScript.indexOf("  function bringInSteps(");
  expect(start).toBeGreaterThan(-1);
  expect(end).toBeGreaterThan(start);
  return remindersScript.slice(start, end);
}

async function runFailingImport() {
  const calls: string[] = [];
  const sandbox: Value = {
    calls,
    console: { warn() {} },
    bringInSteps() {
      return async function failPartWay() {
        calls.push("steps");
        throw new Error("bad entry in the export");
      };
    },
    hideProgress() {
      calls.push("hideProgress");
    },
    showAlert(title: string, message: string) {
      calls.push("alert:" + title + "|" + message);
    },
    enqueueWrite(task: unknown) {
      calls.push(task === sandbox.reloadRecordsTask ? "enqueue:reload" : "enqueue:other");
    },
    reloadRecordsTask() {},
  };
  vm.createContext(sandbox);
  vm.runInContext(remindersBringInTask() + "\n;globalThis.__task = bringInTask({}, {});", sandbox);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  await (sandbox.__task as any)();
  return calls;
}

describe("Reminders: a failed import never leaves Importing… on screen", () => {
  it("closes the progress card, then shows Import Failed, then reads the store again", async () => {
    const calls = await runFailingImport();
    expect(calls).toEqual(["steps", "hideProgress", "alert:Import Failed|Try again.", "enqueue:reload"]);
  });

  it("the import's own steps still end by closing the progress card", () => {
    const start = remindersScript.indexOf("  function bringInSteps(");
    const end = remindersScript.indexOf("  async function applyBringInUpdates(");
    const steps = remindersScript.slice(start, end);
    expect(steps).toContain("hideProgress();");
  });
});
