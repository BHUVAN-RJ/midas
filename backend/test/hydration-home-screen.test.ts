// Water's "Add to Home Screen" request (founder, 2026-10-26: "yes add this to water hydration";
// docs/WIDGETS.md, "Add to Home Screen"). Since founder 2026-10-27 (docs/PRODUCT.md "Where it
// opens": "remove the add to home screen +" from Settings; "Let's go with A") it opens from a
// "Widget" button on Today, not a row in Settings; the button's showing and hiding is checked in
// hydration-widget-button.test.ts. The whole page runs in Node against a fake shell that answers the
// store protocol (shell/Midas/SidekickStoreChannel.swift): Settings has no row on any build; tapping
// the button writes the request the shell dispatches; on an older build ("unknown op shell") or one
// without the request kind the page knows it cannot ask.
process.env.TZ = "America/Los_Angeles";

import { readFileSync } from "node:fs";
import vm from "node:vm";
import { describe, expect, it } from "vitest";

const html = readFileSync(new URL("../../sidekicks/hydration/index.html", import.meta.url), "utf8");
const HOME_SCREEN_KIND = "home-screen.widget";

type Value = Record<string, unknown>;
type StoreRequest = { op: string; key?: string; value?: Value; patch?: Value; prefix?: string };
type Op = { op: string; key: string; value?: Value };
type ShellBuild = "with-sheet" | "older" | "other-kinds" | "keeps-pending";

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

// The phone's store and the shell's answers, as SidekickStoreChannel gives them
function fakeShell(build: ShellBuild) {
  const records = new Map<string, Value>();
  records.set("settings:main", settingsValue());
  const ops: Op[] = [];

  function answerShellOp(): Value {
    if (build === "older") {
      return { ok: false, error: "unknown op shell" };
    }
    if (build === "other-kinds") {
      return { ok: true, requests: ["import.apple-reminders"] };
    }
    return { ok: true, requests: ["import.apple-reminders", HOME_SCREEN_KIND] };
  }

  function answer(request: StoreRequest): Value {
    if (request.op === "shell") {
      return answerShellOp();
    }
    const key = String(request.key ?? "");
    if (request.op === "set") {
      const value = JSON.parse(JSON.stringify(request.value)) as Value;
      ops.push({ op: "set", key, value: JSON.parse(JSON.stringify(value)) });
      records.set(key, value);
      // The shell shows the sheet and marks the request done before it replies
      if (key.startsWith("request:") && value.kind === HOME_SCREEN_KIND && build !== "keeps-pending") {
        records.set(key, { ...value, status: "done", finishedAt: "2026-10-26T20:00:00-07:00" });
      }
      return { ok: true };
    }
    if (request.op === "get") {
      return { ok: true, value: records.has(key) ? records.get(key) : null };
    }
    if (request.op === "delete") {
      ops.push({ op: "delete", key });
      records.delete(key);
      return { ok: true };
    }
    if (request.op === "update") {
      const merged = { ...(records.get(key) ?? {}), ...(request.patch ?? {}) };
      ops.push({ op: "update", key, value: merged });
      records.set(key, merged);
      return { ok: true, value: merged };
    }
    if (request.op === "query") {
      const prefix = String(request.prefix ?? "");
      const found: Array<{ key: string; value: Value }> = [];
      const keys = Array.from(records.keys());
      keys.sort();
      for (const recordKey of keys) {
        if (recordKey.startsWith(prefix)) {
          found.push({ key: recordKey, value: records.get(recordKey) as Value });
        }
      }
      return { ok: true, records: found };
    }
    return { ok: false, error: "unknown op " + request.op };
  }

  async function fetchFromPage(url: string, options: { body: string }) {
    expect(url).toBe("sidekick://hydration/_midas/store");
    const reply = answer(JSON.parse(options.body) as StoreRequest);
    return { json: async () => reply };
  }

  return { records, ops, fetchFromPage };
}

type Handler = (event: unknown) => void;

function loadPage(build: ShellBuild) {
  const shell = fakeShell(build);
  const elements = new Map<string, { innerHTML: string; setAttribute: () => void }>();
  const documentHandlers = new Map<string, Handler>();

  function elementById(id: string) {
    if (!elements.has(id)) {
      elements.set(id, { innerHTML: "", setAttribute() {} });
    }
    return elements.get(id);
  }

  function addDocumentListener(name: string, handler: Handler) {
    documentHandlers.set(name, handler);
  }

  function ignore() {
    // the page's timers, scrolling and resize are not part of these checks
  }

  const sandbox: Value = {
    window: { location: { origin: "sidekick://hydration" }, innerWidth: 402, innerHeight: 874, addEventListener: ignore, scrollTo: ignore },
    document: { hidden: false, getElementById: elementById, addEventListener: addDocumentListener },
    fetch: shell.fetchFromPage,
    console: { warn: ignore, log: ignore },
    setTimeout, clearTimeout, setInterval: ignore,
    Intl, Date, Math, JSON, Promise, Array, Object, String, Number,
  };
  vm.createContext(sandbox);
  vm.runInContext(pageScript(html) + "\n;globalThis.__app = WaterApp;", sandbox);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const app = sandbox.__app as any;

  function mainHtml() {
    return elementById("main")?.innerHTML ?? "";
  }

  // A tap on the element with this data-action, as the page's own click listener gets it
  function tap(action: string) {
    const target = { tagName: "BUTTON", dataset: { action } };
    const clickHandler = documentHandlers.get("click") as Handler;
    clickHandler({ target: { closest: () => target } });
  }

  return { app, shell, mainHtml, tap };
}

async function settled(check: () => boolean) {
  for (let attempt = 0; attempt < 200; attempt += 1) {
    if (check()) {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, 1));
  }
}

async function openSettings(build: ShellBuild) {
  const page = loadPage(build);
  await page.app.whenReady();
  page.app.show("settings");
  return page;
}

function requestOps(ops: Op[]) {
  const found: Op[] = [];
  for (const op of ops) {
    if (op.key.startsWith("request:")) {
      found.push(op);
    }
  }
  return found;
}

describe("Water: Add to Home Screen", () => {
  it("has no row in Settings, even on a build that has the sheet", async () => {
    const page = await openSettings("with-sheet");
    expect(page.app.state().homeScreen).toBe(true);
    expect(page.mainHtml()).toContain("Reminders");
    expect(page.mainHtml()).not.toContain('data-action="add-home-screen"');
    expect(page.mainHtml()).not.toContain("Add to Home Screen");
  });

  it("writes the request the shell shows the sheet for, then removes it once done", async () => {
    const page = await openSettings("with-sheet");
    page.tap("add-home-screen");
    await settled(() => requestOps(page.shell.ops).length >= 2);
    const ops = requestOps(page.shell.ops);
    expect(ops.length).toBe(2);
    const written = ops[0];
    expect(written.op).toBe("set");
    expect(written.key).toMatch(/^request:h[0-9a-z]+$/);
    expect(written.value?.kind).toBe(HOME_SCREEN_KIND);
    expect(written.value?.widget).toBe("sidekick");
    expect(written.value?.status).toBe("pending");
    expect(Number.isNaN(Date.parse(String(written.value?.createdAt)))).toBe(false);
    expect(ops[1]).toEqual({ op: "delete", key: written.key });
    expect(page.shell.records.has(written.key)).toBe(false);
  });

  it("leaves a request the shell has not answered", async () => {
    const page = await openSettings("keeps-pending");
    page.tap("add-home-screen");
    await settled(() => requestOps(page.shell.ops).length >= 1);
    await settled(() => false);
    const ops = requestOps(page.shell.ops);
    expect(ops.length).toBe(1);
    expect(ops[0].op).toBe("set");
    expect(page.shell.records.get(ops[0].key)?.status).toBe("pending");
  });

  it("hides the button on an older build, which answers unknown op shell", async () => {
    const page = await openSettings("older");
    expect(page.app.state().homeScreen).toBe(false);
    expect(page.mainHtml()).toContain("Reminders");
    expect(page.mainHtml()).not.toContain("add-home-screen");
    expect(page.mainHtml()).not.toContain("Add to Home Screen");
  });

  it("hides the button on a build that answers but has no such request", async () => {
    const page = await openSettings("other-kinds");
    expect(page.app.state().homeScreen).toBe(false);
    expect(page.mainHtml()).not.toContain("add-home-screen");
  });

  it("is a button in the page, not a tool", () => {
    const manifest = JSON.parse(readFileSync(new URL("../../sidekicks/hydration/manifest.json", import.meta.url), "utf8"));
    const toolNames: string[] = [];
    for (const tool of manifest.agent.tools) {
      toolNames.push(tool.name);
    }
    expect(toolNames.join(" ")).not.toMatch(/home|screen|widget/i);
  });
});
