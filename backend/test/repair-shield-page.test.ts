// The shield's page check (docs/briefs/repair-lanes.md W1, "Page opens"; founder D3, 2026-11-13):
// the repaired page opens in WebKit (macOS WKWebView, runner/core-checks/webkit-page.swift) with the
// person's own records through a stand-in store, its first view and every view a tool's control
// opens draw with no new console error, uncaught error, unhandled rejection or refused write, and
// the widget record is still written. These tests open real pages in real WebKit.
import { describe, expect, it } from "vitest";
import { checkPageOpens, checkWidgetRecords, normalisedError } from "../../runner/core-checks/page-check.mjs";
import { openPage } from "../../runner/core-checks/page-open.mjs";
import { repoRoot, sidekickCopy, todoRecords, withPageScript, type Copy } from "./repair-shield-fixtures";

const WEBKIT_TIMEOUT_MS = 120_000;
const todo = sidekickCopy("todo");
const records = todoRecords();

function open(copy: Copy, actions: string[] = []) {
  return openPage({ checkoutRoot: repoRoot, sidekickId: "todo", html: copy.html, manifest: JSON.parse(copy.manifestText), records, actions });
}

async function pageProblems(after: Copy, actions: string[] = []) {
  const beforeResults = await open(todo, actions);
  const afterResults = await open(after, actions);
  return { page: checkPageOpens({ beforeResults, afterResults }), widget: checkWidgetRecords({ beforeResults, afterResults }), afterResults };
}

describe("shield: the page opens in WebKit", () => {
  it("opens To-Do with the person's to-dos, draws them, and writes its widget record", async () => {
    const results = await open(todo, ["go-search"]);
    const first = results[0];
    expect(first.name).toBe("open");
    expect(first.report.errors).toEqual([]);
    expect(first.report.visibleElements).toBeGreaterThan(10);
    const widgetStep = results[1];
    const widgetWrites = widgetStep.report.writes.filter((write: { key: string }) => write.key === "widget:today");
    expect(widgetWrites.length).toBeGreaterThan(0);
    expect(widgetWrites[0].problem).toBe(null);
    // The tap really happened: the search view is a different view
    expect(results[2].report.action).toEqual({ name: "go-search", found: true });
    const verdict = checkPageOpens({ beforeResults: results, afterResults: results });
    expect(verdict.problems).toEqual([]);
  }, WEBKIT_TIMEOUT_MS);

  it("shows the person's own records: a to-do title from their store is on the page", async () => {
    const searchable = withPageScript(todo, "window.addEventListener('load', function () { setTimeout(function () { if (document.body.innerText.indexOf('Buy milk') === -1) { console.error('Buy milk not drawn'); } }, 200); });");
    const { page } = await pageProblems(searchable);
    expect(page.problems).toEqual([]);
  }, WEBKIT_TIMEOUT_MS);

  it("fails a page that throws when it opens", async () => {
    const after = withPageScript(todo, "window.addEventListener('load', function () { throw new Error('shield boom'); });");
    const { page } = await pageProblems(after);
    expect(page.problems.some((problem: string) => problem.startsWith("the first view: uncaught:") && problem.includes("shield boom"))).toBe(true);
  }, WEBKIT_TIMEOUT_MS);

  it("fails a console error and an unhandled rejection, even when the page swaps console.error out", async () => {
    const script = "console.error = function hidden() {}; console.error('quiet failure'); Promise.reject(new Error('lost promise'));";
    const { page } = await pageProblems(withPageScript(todo, script));
    expect(page.problems).toContain("the first view: console.error: quiet failure");
    expect(page.problems).toContain("the first view: unhandled rejection: lost promise");
  }, WEBKIT_TIMEOUT_MS);

  it("fails a page that draws nothing", async () => {
    const blank = { ...todo, html: "<!doctype html><html><head><meta charset=\"utf-8\"></head><body></body></html>" };
    const { page } = await pageProblems(blank);
    expect(page.problems).toContain("the first view draws nothing");
  }, WEBKIT_TIMEOUT_MS);

  it("fails a view that breaks when its control is tapped", async () => {
    const script = "document.addEventListener('click', function (event) { if (event.target.closest('[data-action=\"go-search\"]')) { throw new Error('search broke'); } }, true);";
    const { page } = await pageProblems(withPageScript(todo, script), ["go-search"]);
    expect(page.problems.some((problem: string) => problem.startsWith('the view after a tap on "go-search": uncaught:') && problem.includes("search broke"))).toBe(true);
    expect(page.problems.some((problem: string) => problem.startsWith("the first view"))).toBe(false);
  }, WEBKIT_TIMEOUT_MS);

  it("fails a write the shell would refuse", async () => {
    const script = "window.addEventListener('load', function () { store.set('reminder:bad', { title: 5 }).catch(function ignore() {}); });";
    const { page } = await pageProblems(withPageScript(todo, script));
    expect(page.problems.some((problem: string) => problem.startsWith("the first view: store.set('reminder:bad') refused:"))).toBe(true);
  }, WEBKIT_TIMEOUT_MS);

  it("does not blame the repair for an error the page already had", async () => {
    const script = "window.addEventListener('load', function () { console.error('old fault'); });";
    const brokenBefore = withPageScript(todo, script);
    const beforeResults = await open(brokenBefore);
    const afterResults = await open(withPageScript(brokenBefore, "var unrelatedChange = 1;"));
    expect(afterResults[0].report.errors).toContain("console.error: old fault");
    expect(checkPageOpens({ beforeResults, afterResults }).problems).toEqual([]);
  }, WEBKIT_TIMEOUT_MS);

  it("ignores a report the page posts itself: only the prelude knows the nonce", async () => {
    const forged = "window.webkit.messageHandlers.shield.postMessage(JSON.stringify({ nonce: 'guess', errors: [], writes: [], written: {}, visibleElements: 9, textLength: 9, action: null })); throw new Error('real fault');";
    const { page } = await pageProblems(withPageScript(todo, forged));
    expect(page.problems.some((problem: string) => problem.includes("real fault"))).toBe(true);
  }, WEBKIT_TIMEOUT_MS);

  it("fails a page that stops writing its widget record", async () => {
    const after = { ...todo, html: todo.html.replace("const WIDGET_KEY = 'widget:today';", "const WIDGET_KEY = null;") };
    const { widget } = await pageProblems(after);
    expect(widget.problems).toEqual(["widget:today is no longer written; the widget would stop updating"]);
  }, WEBKIT_TIMEOUT_MS);

  it("compares errors without line numbers, which every edit moves", () => {
    expect(normalisedError("uncaught: x is not defined (line 1201)")).toBe("uncaught: x is not defined");
  });
});
