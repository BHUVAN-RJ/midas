// The To-Do Sidekick's Home Screen widget (founder, 2026-11-02: "these look fine, start creating
// them"; docs/mockups/todo-widget-2026-11-02.html with the suggested picks; docs/briefs/todo.md
// "Widget"; docs/CONCERNS.md 25). The page writes widget:today from TodoWidget: Today's open
// to-dos with a tick, through the shell's `when: 'planned'` source (app build 22), in the page's
// own look, accent, Today model and tick side. The shell fills and checks the same description
// in shell/MidasTests/SidekickWidgetPlannedDayTests.swift; the first test here keeps the two in step.
process.env.TZ = "America/Los_Angeles";

import { readFileSync } from "node:fs";
import vm from "node:vm";
import { describe, expect, it } from "vitest";
import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import MidasShellTypes from "../../shell/sdk/shell-types.js";

const html = readFileSync(new URL("../../sidekicks/todo/index.html", import.meta.url), "utf8");
const shellCheck = readFileSync(new URL("../../shell/MidasTests/SidekickWidgetPlannedDayTests.swift", import.meta.url), "utf8");
const toolsSource = readFileSync(new URL("../../sidekicks/todo/tools.js", import.meta.url), "utf8");
const manifest = JSON.parse(readFileSync(new URL("../../sidekicks/todo/manifest.json", import.meta.url), "utf8"));

function blockSource(pageHtml: string, opening: string) {
  const start = pageHtml.indexOf(opening);
  const end = pageHtml.indexOf("\n})();\n", start) + "\n})();\n".length;
  if (start === -1 || end <= start) {
    throw new Error("not in index.html: " + opening);
  }
  return pageHtml.slice(start, end);
}

const widgetSource = blockSource(html, "var TodoWidget = (function createTodoWidget() {");
const logicSource = blockSource(html, "var TodoLogic = (function createTodoLogic() {");
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const Widget: any = vm.runInNewContext(widgetSource + "\n;TodoWidget;", {});
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const Logic: any = vm.runInNewContext(logicSource + "\n;TodoLogic;", { Intl, Date, Math, JSON });

type Piece = Record<string, unknown>;

function settings(changes: Record<string, unknown> = {}) {
  return { ...Logic.DEFAULT_SETTINGS, ...changes };
}

function described(changes: Record<string, unknown> = {}) {
  return JSON.parse(JSON.stringify(Widget.widgetDescription(settings(changes))));
}

function childrenOf(piece: Piece): Piece[] {
  const children: Piece[] = [];
  for (const name of ["vstack", "hstack", "grid"]) {
    if (Array.isArray(piece[name])) {
      children.push(...(piece[name] as Piece[]));
    }
  }
  if (piece.row && typeof piece.row === "object") {
    children.push(piece.row as Piece);
  }
  return children;
}

function walk(piece: Piece, depth: number, found: Array<{ piece: Piece; depth: number }>) {
  found.push({ piece, depth });
  for (const child of childrenOf(piece)) {
    walk(child, depth + 1, found);
  }
}

function piecesOf(size: Piece) {
  const found: Array<{ piece: Piece; depth: number }> = [];
  walk(size, 1, found);
  return found;
}

function rowOf(size: Piece): Piece[] {
  for (const entry of piecesOf(size)) {
    if (entry.piece.list === "$today.items") {
      return (entry.piece.row as Piece).hstack as Piece[];
    }
  }
  throw new Error("no list");
}

function listOf(size: Piece): Piece {
  for (const entry of piecesOf(size)) {
    if (entry.piece.list === "$today.items") {
      return entry.piece;
    }
  }
  throw new Error("no list");
}

function tickIndex(row: Piece[]) {
  for (let index = 0; index < row.length; index += 1) {
    if ("tick" in row[index]) {
      return index;
    }
  }
  return -1;
}

function deepest(pieces: Array<{ piece: Piece; depth: number }>) {
  let depth = 0;
  for (const entry of pieces) {
    depth = Math.max(depth, entry.depth);
  }
  return depth;
}

// The JSON the shell test fills: between ##""" and """## in the Swift file
function shellTestWidget() {
  const start = shellCheck.indexOf('##"""') + '##"""'.length;
  const end = shellCheck.indexOf('"""##', start);
  return JSON.parse(shellCheck.slice(start, end));
}

describe("To-Do widget: the description", () => {
  it("is the one the shell fills and checks in its own test (default settings, small)", () => {
    const widget = described();
    const shellWidget = shellTestWidget();
    expect(widget.sources).toEqual(shellWidget.sources);
    expect(widget.background).toEqual(shellWidget.background);
    expect(widget.tint).toBe(shellWidget.tint);
    expect(widget.name).toBe(shellWidget.name);
    expect(widget.version).toBe(shellWidget.version);
    expect(widget.small).toEqual(shellWidget.small);
  });

  it("reads Today through the planned source, by the page's Today model", () => {
    expect(described().sources.today).toEqual({ records: "reminder:", when: "planned", model: "carry", where: { $type: "todo.item" }, limit: 50 });
    for (const model of ["stay", "fresh", "gated"]) {
      expect(described({ todayModel: model }).sources.today.model).toBe(model);
    }
  });

  it("lists 3 rows small and medium, 9 large, each with +N More", () => {
    const widget = described();
    expect(listOf(widget.small).limit).toBe(3);
    expect(listOf(widget.medium).limit).toBe(3);
    expect(listOf(widget.large).limit).toBe(9);
    for (const size of ["small", "medium", "large"]) {
      expect(listOf(widget[size]).more).toBe("+$more More");
      // Rows at least 8 pt apart against mis-ticks (TD-OUT-02, P3)
      expect(listOf(widget[size]).spacing).toBeGreaterThanOrEqual(8);
    }
  });

  it("puts the tick where the page puts its checkbox", () => {
    for (const checkbox of ["end", "none"]) {
      const row = rowOf(described({ checkbox }).small);
      expect(tickIndex(row), checkbox).toBe(row.length - 1);
    }
    for (const checkbox of ["circle", "square"]) {
      expect(tickIndex(rowOf(described({ checkbox }).small)), checkbox).toBe(0);
    }
  });

  it("draws the page's look and accent in light and dark", () => {
    expect(described({ look: "paper" }).background).toEqual({ light: "#FFFFFF", dark: "#1E2128" });
    expect(described({ look: "heat" }).background).toEqual({ light: "#000000", dark: "#000000" });
    const green = described({ accent: "#30A46C" });
    expect(green.tint).toBe("#30A46C");
    const greenRow = rowOf(green.small);
    const tick = greenRow[tickIndex(greenRow)];
    expect(tick.color).toEqual({ light: "#30A46C", dark: Widget.nightAccent("#30A46C") });
    // The night accent is the same hue, lighter
    expect(Widget.nightAccent("#2F6FEB")).toBe("#5B8DEF");
    expect(Widget.nightAccent("not a colour")).toBe("#5B8DEF");
  });

  it("gives every explicit colour as a light and dark pair (docs/WIDGETS.md, Light and dark)", () => {
    const widget = described();
    for (const size of ["small", "medium", "large"]) {
      for (const entry of piecesOf(widget[size])) {
        const color = entry.piece.color;
        if (color === undefined || color === "secondary" || color === "primary") {
          continue;
        }
        expect(color, JSON.stringify(entry.piece)).toEqual({ light: expect.stringMatching(/^#[0-9A-F]{6}$/), dark: expect.stringMatching(/^#[0-9A-F]{6}$/) });
      }
    }
  });

  it("says All Done or Nothing Today when nothing is open, never Open Midas", () => {
    const texts: string[] = [];
    for (const entry of piecesOf(described().small)) {
      if (typeof entry.piece.text === "string") {
        texts.push(entry.piece.text);
      }
    }
    expect(texts).toEqual(["Today", "$today.open", "$item.title", "$item.time", "All Done", "Nothing Today"]);
  });

  it("stays inside the widget limits and passes the shell's record type", () => {
    const widget = described();
    for (const size of ["small", "medium", "large"]) {
      const pieces = piecesOf(widget[size]);
      expect(pieces.length).toBeLessThanOrEqual(150);
      expect(deepest(pieces)).toBeLessThanOrEqual(12);
    }
    expect(JSON.stringify(widget).length).toBeLessThan(64 * 1024);
    const stamped = MidasRecordSchema.stampType(MidasShellTypes, "widget:today", widget);
    expect(MidasRecordSchema.checkRecord(MidasShellTypes, "widget:today", stamped)).toBeNull();
  });

  it("is the same widget again only when nothing changed", () => {
    const widget = described();
    expect(Widget.sameWidget({ ...widget, $type: "midas.widget" }, widget)).toBe(true);
    expect(Widget.sameWidget(described({ accent: "#E5484D" }), widget)).toBe(false);
    expect(Widget.sameWidget(described({ todayModel: "fresh" }), widget)).toBe(false);
    expect(Widget.sameWidget(null, widget)).toBe(false);
  });
});

describe("To-Do widget: the page", () => {
  it("writes the widget on open and after Make It Yours changes, only when it changed", () => {
    const startBody = html.slice(html.indexOf("async function start() {"));
    expect(startBody.indexOf("await publishWidget();")).toBeGreaterThan(startBody.indexOf("await loadAll();"));
    const saveSettingsBody = html.slice(html.indexOf("async function saveSettings() {"), html.indexOf("async function publishWidget() {"));
    expect(saveSettingsBody).toContain("await publishWidget();");
    const publishBody = html.slice(html.indexOf("async function publishWidget() {"), html.indexOf("async function shellShowsHomeScreenSteps() {"));
    expect(publishBody).toContain("TodoWidget.sameWidget(existing, wanted)");
  });

  it("asks for the Add Widget steps with the shell's request, from a quiet ? shown only when the build has them", () => {
    expect(Widget.homeScreenRequest("2026-11-02T20:00:00.000Z")).toEqual({
      kind: "home-screen.widget", widget: "sidekick", status: "pending", createdAt: "2026-11-02T20:00:00.000Z"
    });
    const stamped = MidasRecordSchema.stampType(MidasShellTypes, "request:h1", Widget.homeScreenRequest("2026-11-02T20:00:00.000Z"));
    expect(MidasRecordSchema.checkRecord(MidasShellTypes, "request:h1", stamped)).toBeNull();
    expect(html).toContain("if (state.homeScreen && isRootView(viewName)) {");
    expect(html).toContain('data-help="add-widget">Add Widget');
    expect(html).toContain("JSON.stringify({ op: 'shell' })");
  });

  it("leaves the agent block and tools.js alone: the widget is not a tool", () => {
    expect(toolsSource).not.toContain("TodoWidget");
    expect(toolsSource).not.toContain("widget:today");
    expect(JSON.stringify(manifest.agent)).not.toContain("widget");
  });
});
