// Care's settings (repair lanes W5, founder D1, 2026-11-13): every part a person would name has a
// colour, size or show setting in manifest.json "settings", drawn by the settings engine
// (shell/sdk/midas-settings.js) from settings:self; the dates follow "dates.format"; a hidden
// feature's tool answers "turned off". The page runs in Node against a fake shell that answers the
// store protocol, as in hydration-home-screen.test.ts; its rendered markup is parsed and every
// catalogue selector must match an element in it. Starter lists still seed through settings:seeded,
// which shares the care.settings type with settings:self.
process.env.TZ = "America/Los_Angeles";

import { readFileSync } from "node:fs";
import vm from "node:vm";
import { describe, expect, it } from "vitest";
import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import MidasSettings from "../../shell/sdk/midas-settings.js";
import { loadToolsScript } from "../scripts/sidekick-tools.mjs";

const folder = new URL("../../sidekicks/care-reminders/", import.meta.url);
const html = readFileSync(new URL("index.html", folder), "utf8");
const toolsText = readFileSync(new URL("tools.js", folder), "utf8");
const manifest = JSON.parse(readFileSync(new URL("manifest.json", folder), "utf8"));
const catalogue = manifest.settings;

const LA = "America/Los_Angeles";
// Tuesday Oct 20, 2026, 10:00 in Los Angeles
const NOW_MS = Date.parse("2026-10-20T17:00:00.000Z");
const MINUTE_MS = 60000;

type Value = Record<string, unknown>;
type StoreRequest = { op: string; key?: string; value?: Value; patch?: Value; prefix?: string };
type Entry = { key: string; type: string; selector?: string; tools?: string[]; default: unknown };
type Records = Array<{ key: string; value: Value }>;

function pageScript(pageHtml: string) {
  const start = pageHtml.indexOf("<script>") + "<script>".length;
  const end = pageHtml.indexOf("</script>", start);
  return pageHtml.slice(start, end);
}

function isoAt(milliseconds: number) {
  return new Date(milliseconds).toISOString();
}

function listValue(name: string, icon: string, color: string, order: number): Value {
  return { $type: "care.list", name, icon, color, alerts: [], order, createdAt: "2026-10-01T00:00:00.000Z" };
}

function itemValue(title: string, list: string, atMs: number, done: boolean): Value {
  const value: Value = { $type: "care.item", title, list, at: isoAt(atMs), timeZone: LA, done, createdAt: "2026-10-01T00:00:00.000Z" };
  if (done) {
    value.completedAt = isoAt(atMs + 5 * MINUTE_MS);
  }
  return value;
}

// A home screen with an upcoming, a late and a done reminder today, and a list of later ones
function careRecords(): Map<string, Value> {
  const records = new Map<string, Value>();
  records.set("settings:seeded", { $type: "care.settings", at: "2026-10-01T00:00:00.000Z" });
  records.set("list:medicine", listValue("Medicine", "pill", "butter", 0));
  records.set("list:appointments", listValue("Appointments", "stethoscope", "charcoal", 1));
  records.set("list:later", listValue("Later", "calendar-dots", "sky", 2));
  records.set("reminder:ipills001", itemValue("Pills", "medicine", NOW_MS + 30 * MINUTE_MS, false));
  records.set("reminder:idone0001", itemValue("Vitamins", "medicine", NOW_MS - 120 * MINUTE_MS, true));
  records.set("reminder:ilate0001", itemValue("Call clinic", "appointments", NOW_MS - 60 * MINUTE_MS, false));
  // Wed Oct 21 (Tomorrow), Fri Oct 23 (a weekday), Thu Nov 5 (a date)
  records.set("reminder:itomorrw", itemValue("Refill", "later", NOW_MS + 24 * 60 * MINUTE_MS, false));
  records.set("reminder:ifriday1", itemValue("Dentist", "later", NOW_MS + 3 * 24 * 60 * MINUTE_MS, false));
  records.set("reminder:inovembr", itemValue("Eye exam", "later", NOW_MS + 16 * 24 * 60 * MINUTE_MS, false));
  return records;
}

// The phone's store, as SidekickStoreChannel answers the page
function fakeShell(records: Map<string, Value>) {
  function answer(request: StoreRequest): Value {
    const key = String(request.key ?? "");
    if (request.op === "set") {
      records.set(key, JSON.parse(JSON.stringify(request.value)) as Value);
      return { ok: true };
    }
    if (request.op === "get") {
      return { ok: true, value: records.has(key) ? records.get(key) : null };
    }
    if (request.op === "delete") {
      records.delete(key);
      return { ok: true };
    }
    if (request.op === "update") {
      const merged = { ...(records.get(key) ?? {}), ...(request.patch ?? {}) };
      records.set(key, merged);
      return { ok: true, value: merged };
    }
    if (request.op === "query") {
      const prefix = String(request.prefix ?? "");
      const found: Records = [];
      const keys = Array.from(records.keys());
      keys.sort();
      for (const recordKey of keys) {
        if (recordKey.startsWith(prefix)) {
          found.push({ key: recordKey, value: records.get(recordKey) as Value });
        }
      }
      return { ok: true, records: found };
    }
    if (request.op === "focus") {
      return { ok: true, focus: null };
    }
    return { ok: false, error: "unknown op " + request.op };
  }

  async function fetchFromPage(url: string, options: { body: string }) {
    expect(url).toBe("sidekick://care-reminders/_midas/store");
    const reply = answer(JSON.parse(options.body) as StoreRequest);
    return { json: async () => reply };
  }

  return { fetchFromPage };
}

// Date with the clock held at NOW_MS, so "today" and "in 30 min" do not depend on when tests run
function fixedClockDate() {
  const RealDate = Date;
  class FixedDate extends RealDate {
    constructor(...args: unknown[]) {
      if (args.length === 0) {
        super(NOW_MS);
      } else {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        super(...(args as [any]));
      }
    }

    static now() {
      return NOW_MS;
    }
  }
  return FixedDate;
}

type Handler = (event: unknown) => void;
type FakeElement = { id: string; innerHTML: string; textContent: string; setAttribute: () => void };

function waitForPage() {
  return new Promise(function afterQueuedWork(resolve) {
    setTimeout(resolve, 20);
  });
}

async function loadPage(records: Map<string, Value>) {
  const shell = fakeShell(records);
  const elements = new Map<string, FakeElement>();
  const documentHandlers = new Map<string, Handler[]>();

  function makeElement(id: string): FakeElement {
    return { id, innerHTML: "", textContent: "", setAttribute() {} };
  }

  function elementById(id: string) {
    if (!elements.has(id)) {
      elements.set(id, makeElement(id));
    }
    return elements.get(id);
  }

  // The engine's style element: created once, then found by its id
  function createElement() {
    return makeElement("");
  }

  function appendToHead(element: FakeElement) {
    if (element.id !== "") {
      elements.set(element.id, element);
    }
  }

  function addDocumentListener(name: string, handler: Handler) {
    const handlers = documentHandlers.get(name) ?? [];
    handlers.push(handler);
    documentHandlers.set(name, handlers);
  }

  function ignore() {
    // the page's timers and scrolling are not part of these checks
    return 0;
  }

  const sandbox: Value = {
    window: { location: { origin: "sidekick://care-reminders" }, addEventListener: ignore, scrollTo: ignore },
    document: { hidden: false, getElementById: elementById, createElement, head: { appendChild: appendToHead }, addEventListener: addDocumentListener },
    fetch: shell.fetchFromPage,
    crypto: globalThis.crypto,
    console: { warn: ignore, log: ignore },
    setTimeout: ignore, clearTimeout: ignore, setInterval: ignore, clearInterval: ignore,
    Intl, Date: fixedClockDate(), Math, JSON, Promise, Array, Object, String, Number, Uint8Array, Map, Set, Response,
  };
  vm.createContext(sandbox);
  vm.runInContext(pageScript(html) + "\n;globalThis.__app = CareApp; globalThis.__catalogue = SETTINGS_CATALOGUE;", sandbox);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const app = sandbox.__app as any;
  await app.whenReady();
  await waitForPage();

  function markup(id: string) {
    return elementById(id)?.innerHTML ?? "";
  }

  function settingsCss() {
    return elements.get("midas-settings")?.textContent ?? "";
  }

  function click(attributes: Record<string, string>) {
    const actionElement = {
      disabled: false,
      getAttribute(name: string) {
        return name in attributes ? attributes[name] : null;
      },
    };
    const target = {
      closest() {
        return actionElement;
      },
    };
    for (const handler of documentHandlers.get("click") ?? []) {
      handler({ target, preventDefault() {} });
    }
  }

  // The engine reads settings:self again whenever the page is shown
  async function showAgain() {
    for (const handler of documentHandlers.get("visibilitychange") ?? []) {
      handler({});
    }
    await waitForPage();
  }

  return { app, markup, settingsCss, click, showAgain, pageCatalogue: sandbox.__catalogue };
}

/* ---------- A small HTML tree and CSS selector matcher, for the page's own markup ---------- */

type TreeNode = { tag: string; classes: string[]; id: string; parent: TreeNode | null; children: TreeNode[] };

const VOID_TAGS = ["input", "br", "img", "meta", "link", "hr", "use"];
const TAG_PATTERN = /<!--[\s\S]*?-->|<(\/)?([a-zA-Z][a-zA-Z0-9-]*)((?:[^>"']|"[^"]*"|'[^']*')*)>/g;

function attributeOf(attributeText: string, name: string) {
  const pattern = new RegExp("(?:^|\\s)" + name + "=\"([^\"]*)\"");
  const found = pattern.exec(attributeText);
  return found ? found[1] : "";
}

function parseTree(markup: string): TreeNode {
  const root: TreeNode = { tag: "#document", classes: [], id: "", parent: null, children: [] };
  let current = root;
  for (const token of markup.matchAll(TAG_PATTERN)) {
    const tag = token[2] ? token[2].toLowerCase() : "";
    if (tag === "") {
      continue;
    }
    if (token[1] === "/") {
      // Close up to the matching open tag
      let open: TreeNode | null = current;
      while (open !== null && open.tag !== tag) {
        open = open.parent;
      }
      if (open !== null && open.parent !== null) {
        current = open.parent;
      }
      continue;
    }
    const attributeText = token[3] ?? "";
    const classText = attributeOf(attributeText, "class");
    const classes = classText.split(/\s+/).filter(Boolean);
    const node: TreeNode = { tag, classes, id: attributeOf(attributeText, "id"), parent: current, children: [] };
    current.children.push(node);
    const selfClosing = attributeText.trim().endsWith("/") || VOID_TAGS.includes(tag);
    if (!selfClosing) {
      current = node;
    }
  }
  return root;
}

function allNodes(root: TreeNode): TreeNode[] {
  const found: TreeNode[] = [];
  const pending = [...root.children];
  while (pending.length > 0) {
    const node = pending.shift() as TreeNode;
    found.push(node);
    pending.push(...node.children);
  }
  return found;
}

type Compound = { tag: string; classes: string[]; ids: string[]; notClasses: string[]; root: boolean };
type Step = { compound: Compound; combinator: string };

const COMPOUND_PART = /:not\(\.([\w-]+)\)|:root|\.([\w-]+)|#([\w-]+)|^([a-z][a-z0-9]*)/g;

function parseCompound(text: string): Compound {
  const compound: Compound = { tag: "", classes: [], ids: [], notClasses: [], root: false };
  let consumed = "";
  for (const part of text.matchAll(COMPOUND_PART)) {
    consumed += part[0];
    if (part[1]) {
      compound.notClasses.push(part[1]);
    } else if (part[0] === ":root") {
      compound.root = true;
    } else if (part[2]) {
      compound.classes.push(part[2]);
    } else if (part[3]) {
      compound.ids.push(part[3]);
    } else if (part[4]) {
      compound.tag = part[4];
    }
  }
  // A selector this matcher does not understand fails the test instead of passing quietly
  expect(consumed, "selector part " + text).toBe(text);
  return compound;
}

function parseComplex(text: string): Step[] {
  const spaced = text.trim().replace(/\s*([>~+])\s*/g, " $1 ");
  const tokens = spaced.split(/\s+/);
  const steps: Step[] = [];
  let combinator = " ";
  for (const token of tokens) {
    if (token === ">" || token === "~" || token === "+") {
      combinator = token;
      continue;
    }
    steps.push({ compound: parseCompound(token), combinator });
    combinator = " ";
  }
  return steps;
}

function compoundMatches(node: TreeNode, compound: Compound) {
  if (compound.root) {
    return node.tag === "html";
  }
  if (compound.tag !== "" && node.tag !== compound.tag) {
    return false;
  }
  for (const className of compound.classes) {
    if (!node.classes.includes(className)) {
      return false;
    }
  }
  for (const id of compound.ids) {
    if (node.id !== id) {
      return false;
    }
  }
  for (const className of compound.notClasses) {
    if (node.classes.includes(className)) {
      return false;
    }
  }
  return true;
}

function previousSiblings(node: TreeNode) {
  if (node.parent === null) {
    return [];
  }
  const siblings = node.parent.children;
  return siblings.slice(0, siblings.indexOf(node));
}

// Right to left, as a browser matches
function stepsMatch(node: TreeNode, steps: Step[], index: number): boolean {
  if (!compoundMatches(node, steps[index].compound)) {
    return false;
  }
  if (index === 0) {
    return true;
  }
  const combinator = steps[index].combinator;
  if (combinator === ">") {
    return node.parent !== null && stepsMatch(node.parent, steps, index - 1);
  }
  if (combinator === "~") {
    return previousSiblings(node).some(function siblingMatches(sibling) {
      return stepsMatch(sibling, steps, index - 1);
    });
  }
  let ancestor = node.parent;
  while (ancestor !== null) {
    if (stepsMatch(ancestor, steps, index - 1)) {
      return true;
    }
    ancestor = ancestor.parent;
  }
  return false;
}

// Each comma part of a selector, with whether it matches an element in any of the documents
function selectorPartsMatched(selector: string, documents: TreeNode[]) {
  const results: Array<{ part: string; matched: boolean }> = [];
  for (const part of selector.split(",")) {
    const steps = parseComplex(part);
    let matched = false;
    for (const documentRoot of documents) {
      const nodes = allNodes(documentRoot);
      const hit = nodes.some(function nodeMatches(node) {
        return stepsMatch(node, steps, steps.length - 1);
      });
      if (hit) {
        matched = true;
      }
    }
    results.push({ part: part.trim(), matched });
  }
  return results;
}

function pageDocument(main: string, sheets: string, bar: string) {
  return parseTree(
    '<html><body><div id="main">' + main + '</div><div id="sheets">' + sheets + '</div><div id="bar">' + bar + "</div></body></html>",
  );
}

/* ---------- tools.js ---------- */

const loaded = loadToolsScript(toolsText);
if (!("tools" in loaded)) {
  throw new Error(loaded.problem);
}
const tools = loaded.tools;
const NOW = isoAt(NOW_MS);

function toolRecords(settingsSelf: Value | null): Records {
  const records: Records = [];
  for (const [key, value] of careRecords()) {
    records.push({ key, value });
  }
  if (settingsSelf !== null) {
    records.push({ key: "settings:self", value: settingsSelf });
  }
  return records;
}

type Outcome = { ops?: Array<{ op: string; key: string; value?: Value }>; refused?: string; result: { text: string } };

function callTool(verb: string, input: Value, records: Records): Outcome {
  const outcome = tools.handlers[verb](input, records, NOW);
  return JSON.parse(JSON.stringify(outcome));
}

function entries(): Entry[] {
  return catalogue.entries as Entry[];
}

describe("Care's settings catalogue", () => {
  it("is a catalogue the engine accepts, with a date format left at the page's own", () => {
    expect(MidasSettings.catalogueProblems(catalogue)).toEqual([]);
    const dates = MidasSettings.entryFor(catalogue, "dates.format");
    expect(dates.type).toBe("dateFormat");
    expect(dates.default).toBe("auto");
  });

  it("gives settings:self a schema property for every key, as the engine writes it", () => {
    const properties = manifest.types["settings:"].schema.properties;
    for (const entry of entries()) {
      expect(properties[entry.key], entry.key).toEqual(MidasSettings.propertySchemaFor(entry));
    }
    // settings:seeded keeps its own field under the same type
    expect(properties.at).toEqual({ type: "string", format: "date-time" });
  });

  it("is the same catalogue in the page, tools.js and the manifest", () => {
    const sandbox: Value = {};
    vm.createContext(sandbox);
    vm.runInContext(toolsText + "\n;globalThis.__catalogue = SETTINGS_CATALOGUE;", sandbox);
    expect(JSON.parse(JSON.stringify(sandbox.__catalogue))).toEqual(catalogue);
    const catalogueLine = html.split("\n").find(function isCatalogueLine(line) {
      return line.startsWith("var SETTINGS_CATALOGUE = ");
    });
    expect(catalogueLine).toBeDefined();
    const pageCatalogue = JSON.parse(String(catalogueLine).slice("var SETTINGS_CATALOGUE = ".length).replace(/;\s*$/, ""));
    expect(pageCatalogue).toEqual(catalogue);
  });

  it("names a set_setting tool whose keys are the catalogue's", () => {
    const tool = manifest.agent.tools.find(function isSetSetting(candidate: { name: string }) {
      return candidate.name === "care-reminders.set_setting";
    });
    expect(tool).toBeDefined();
    const keys = entries().map(function keyOf(entry) {
      return entry.key;
    });
    expect(tool.inputSchema.properties.key.enum).toEqual(keys);
  });

  it("only turns off tools that exist", () => {
    const toolNames = manifest.agent.tools.map(function nameOf(tool: { name: string }) {
      return tool.name;
    });
    for (const entry of entries()) {
      for (const toolName of entry.tools ?? []) {
        expect(toolNames, entry.key).toContain(toolName);
      }
    }
  });
});

describe("Care's page with the settings engine", () => {
  it("matches every catalogue selector to an element the page draws", async () => {
    const page = await loadPage(careRecords());
    const home = pageDocument(page.markup("main"), page.markup("sheets"), page.markup("bar"));
    page.click({ "data-action": "open-list", "data-id": "medicine" });
    const listPage = pageDocument(page.markup("main"), page.markup("sheets"), page.markup("bar"));
    page.click({ "data-action": "new-reminder", "data-list": "medicine" });
    await waitForPage();
    const withSheet = pageDocument(page.markup("main"), page.markup("sheets"), page.markup("bar"));
    await page.app.deleteList("later");
    await waitForPage();
    const withBar = pageDocument(page.markup("main"), page.markup("sheets"), page.markup("bar"));
    const documents = [home, listPage, withSheet, withBar];

    // The matcher can fail: a part the page never draws matches nothing
    expect(selectorPartsMatched(".no-such-part", documents)).toEqual([{ part: ".no-such-part", matched: false }]);
    expect(selectorPartsMatched("#bar .ruler", documents)).toEqual([{ part: "#bar .ruler", matched: false }]);

    const unmatched: string[] = [];
    for (const entry of entries()) {
      if (typeof entry.selector !== "string") {
        continue;
      }
      for (const result of selectorPartsMatched(entry.selector, documents)) {
        if (!result.matched) {
          unmatched.push(entry.key + ": " + result.part);
        }
      }
    }
    expect(unmatched).toEqual([]);
  });

  it("keeps the Today list's selector off a list page", async () => {
    const page = await loadPage(careRecords());
    page.click({ "data-action": "open-list", "data-id": "medicine" });
    const listPage = pageDocument(page.markup("main"), "", "");
    const today = MidasSettings.entryFor(catalogue, "today.show");
    const results = selectorPartsMatched(today.selector, [listPage]);
    expect(results.every(function isUnmatched(result) {
      return !result.matched;
    })).toBe(true);
  });

  it("carries the manifest's catalogue in the running page", async () => {
    const page = await loadPage(careRecords());
    expect(JSON.parse(JSON.stringify(page.pageCatalogue))).toEqual(catalogue);
  });

  it("draws a changed settings:self live, without reopening", async () => {
    const records = careRecords();
    const page = await loadPage(records);
    expect(page.settingsCss()).toBe("");
    records.set("settings:self", { $type: "care.settings", "page.colour": "#112233", "addReminder.show": false, "title.size": "xl" });
    await page.showAgain();
    const css = page.settingsCss();
    expect(css).toContain(":root { --paper: #112233 !important; }");
    expect(css).toContain(".add-row { display: none !important; }");
    expect(css).toContain(".head .h1 { zoom: 1.4 !important; }");
  });

  it("writes reminder dates in the chosen format and keeps Tomorrow and today's words", async () => {
    const records = careRecords();
    const page = await loadPage(records);
    page.click({ "data-action": "open-list", "data-id": "later" });
    const asBuilt = page.markup("main");
    expect(asBuilt).toContain("Tomorrow");
    expect(asBuilt).not.toContain("5 Nov 2026");
    expect(asBuilt).not.toContain("23 Oct 2026");

    records.set("settings:self", { $type: "care.settings", "dates.format": "day-month-year" });
    await page.showAgain();
    const chosen = page.markup("main");
    expect(chosen).toContain("5 Nov 2026");
    expect(chosen).toContain("23 Oct 2026");
    expect(chosen).toContain("Tomorrow");
    expect(chosen).not.toContain("22 Oct 2026");

    records.set("settings:self", { $type: "care.settings", "dates.format": "auto" });
    await page.showAgain();
    expect(page.markup("main")).toBe(asBuilt);
  });

  it("still seeds the starter lists once, next to a settings:self", async () => {
    const records = new Map<string, Value>();
    records.set("settings:self", { $type: "care.settings", "page.colour": "#112233" });
    await loadPage(records);
    expect(records.get("settings:seeded")).toMatchObject({ $type: "care.settings" });
    const listKeys = Array.from(records.keys()).filter(function isList(key) {
      return key.startsWith("list:");
    });
    expect(listKeys.length).toBeGreaterThan(0);
    expect(records.get("settings:self")).toEqual({ $type: "care.settings", "page.colour": "#112233" });
    for (const key of ["settings:seeded", "settings:self"]) {
      const value = records.get(key) as Value;
      expect(MidasRecordSchema.checkRecord(manifest.types, key, value), key).toBeNull();
    }
  });
});

describe("Care's tools with the settings engine", () => {
  it("set_setting writes settings:self, keeping what is there, and the record fits the manifest", () => {
    const outcome = callTool("set_setting", { key: "reminderNames.colour", value: "#335577" }, toolRecords({ $type: "care.settings", "title.show": false }));
    expect(outcome.refused).toBeUndefined();
    expect(outcome.ops?.length).toBe(1);
    const op = outcome.ops?.[0];
    expect(op?.key).toBe("settings:self");
    expect(op?.value).toEqual({ $type: "care.settings", "title.show": false, "reminderNames.colour": "#335577" });
    const stamped = MidasRecordSchema.stampType(manifest.types, "settings:self", op?.value);
    expect(MidasRecordSchema.checkRecord(manifest.types, "settings:self", stamped)).toBeNull();
  });

  it("set_setting on a fresh Sidekick leaves settings:seeded alone", () => {
    const outcome = callTool("set_setting", { key: "dates.format", value: "month-day" }, toolRecords(null));
    const keys = (outcome.ops ?? []).map(function keyOf(op) {
      return op.key;
    });
    expect(keys).toEqual(["settings:self"]);
    const stamped = MidasRecordSchema.stampType(manifest.types, "settings:self", outcome.ops?.[0].value);
    expect(stamped.$type).toBe("care.settings");
    expect(MidasRecordSchema.checkRecord(manifest.types, "settings:self", stamped)).toBeNull();
  });

  it("set_setting refuses a value the catalogue does not offer", () => {
    const outcome = callTool("set_setting", { key: "page.size", value: "huge" }, toolRecords(null));
    expect(outcome.refused).toBe("value-not-offered");
    expect(outcome.ops).toBeUndefined();
  });

  it("a hidden Add Reminder button turns off adding a reminder, and only that", () => {
    const hidden = toolRecords({ $type: "care.settings", "addReminder.show": false });
    const added = callTool("add", { title: "Stretch", list: "Medicine", when: null, everyHours: null }, hidden);
    expect(added.refused).toBe("turned-off");
    expect(added.result.text).toBe("Add Reminder button is turned off");
    const completed = callTool("complete", { item: "Pills" }, hidden);
    expect(completed.refused).not.toBe("turned-off");
    expect(completed.ops?.length ?? 0).toBeGreaterThan(0);
    const listMade = callTool("create_list", { name: "Pets", icon: "dog", color: "sage" }, hidden);
    expect(listMade.refused).not.toBe("turned-off");

    const shown = callTool("add", { title: "Stretch", list: "Medicine", when: null, everyHours: null }, toolRecords(null));
    expect(shown.refused).not.toBe("turned-off");
  });

  it("a hidden New List button turns off making a list", () => {
    const hidden = toolRecords({ $type: "care.settings", "newList.show": false });
    const listMade = callTool("create_list", { name: "Pets", icon: "dog", color: "sage" }, hidden);
    expect(listMade.refused).toBe("turned-off");
    const shown = callTool("create_list", { name: "Pets", icon: "dog", color: "sage" }, toolRecords(null));
    expect(shown.refused).toBeUndefined();
    expect(shown.ops?.length ?? 0).toBeGreaterThan(0);
  });
});
