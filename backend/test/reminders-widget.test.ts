// The Reminders Sidekick's Home Screen widget (founder, 2026-10-26: "Since now each sidekick can
// create its own widget, shouldn't we just use that?"; "+N more" instead of page arrows). The page
// writes widget:today in small, medium and large, made of the widget builder's pieces: "Today" and
// the count, a tick circle per reminder, the title and the time (red once late, a colour choice),
// "+N more", "All done". For an app build that refuses a colour choice it writes a plain stand-in
// with grey times. The shell's own checker runs on them in the shell's tests
// (RemindersSidekickWidgetTests); here the shape, the shell's record type and the widget limits.
import { readFileSync } from "node:fs";
import vm from "node:vm";
import { describe, expect, it } from "vitest";
import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import MidasShellTypes from "../../shell/sdk/shell-types.js";

const html = readFileSync(new URL("../../sidekicks/reminders/index.html", import.meta.url), "utf8");
const tools = readFileSync(new URL("../../sidekicks/reminders/tools.js", import.meta.url), "utf8");

function widgetBlockSource(pageHtml: string) {
  const start = pageHtml.indexOf("var RemindersWidget = (function createRemindersWidget() {");
  const end = pageHtml.indexOf("\n})();\n", start) + "\n})();\n".length;
  return pageHtml.slice(start, end);
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const RemindersWidget: any = vm.runInNewContext(widgetBlockSource(html) + "\n;RemindersWidget;", {});

type Piece = Record<string, unknown>;
type Widget = Record<string, unknown>;

// The pieces the shell knows (shell/Midas/SidekickWidgetDescription.swift)
const KNOWN_PIECES = ["vstack", "hstack", "grid", "list", "spacer", "divider", "text", "symbol", "bar", "ring", "dots", "chart", "timer", "tick", "button", "fill"];
const SIZES = ["small", "medium", "large"];
const LATE_COLOUR = { if: "$item.late", then: "red", else: "secondary" };

function widgetRecords(): Array<{ key: string; value: Widget; plain: Widget }> {
  return JSON.parse(JSON.stringify(RemindersWidget.widgetRecords()));
}

function todayWidget() {
  const records = widgetRecords();
  expect(records).toHaveLength(1);
  return records[0];
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

function walk(piece: Piece, depth: number, visit: (piece: Piece, depth: number) => void) {
  visit(piece, depth);
  for (const child of childrenOf(piece)) {
    walk(child, depth + 1, visit);
  }
}

function piecesOf(sizePiece: Piece) {
  const found: Array<{ piece: Piece; depth: number }> = [];
  function collect(piece: Piece, depth: number) {
    found.push({ piece, depth });
  }
  walk(sizePiece, 0, collect);
  return found;
}

function listOf(widget: Widget, size: string): Piece {
  for (const entry of piecesOf(widget[size] as Piece)) {
    if (typeof entry.piece.list === "string") {
      return entry.piece;
    }
  }
  throw new Error("no list in " + size);
}

function timeTextOf(widget: Widget, size: string): Piece {
  for (const entry of piecesOf(listOf(widget, size).row as Piece)) {
    if (entry.piece.text === "$item.time") {
      return entry.piece;
    }
  }
  throw new Error("no time in " + size);
}

function shellTypeProblem(key: string, value: Widget) {
  const stamped = MidasRecordSchema.stampType(MidasShellTypes, key, value);
  return MidasRecordSchema.checkRecord(MidasShellTypes, key, stamped);
}

describe("Reminders widget: what the page writes", () => {
  it("writes widget:today, named Today, in small, medium and large", () => {
    const widget = todayWidget();
    expect(widget.key).toBe("widget:today");
    expect(widget.value.name).toBe("Today");
    for (const size of SIZES) {
      expect(widget.value[size], size).toBeTruthy();
      expect(widget.plain[size], "plain " + size).toBeTruthy();
    }
    expect(widget.value.sources).toEqual({ today: { records: "reminder:", when: "today", limit: 50 } });
  });

  it("shows three rows in small and medium, eight in large, then +N more, and All done when empty", () => {
    const value = todayWidget().value;
    const limits: Record<string, number> = { small: 3, medium: 3, large: 8 };
    for (const size of SIZES) {
      const list = listOf(value, size);
      expect(list.list).toBe("$today.items");
      expect(list.limit, size).toBe(limits[size]);
      expect(list.more).toBe("+$more more");
      expect(list.empty).toBe("All done");
      expect(JSON.stringify(list.row)).toContain('"tick":"$item"');
      expect(JSON.stringify(list.row)).toContain('"text":"$item.title"');
    }
  });

  it("puts Today and the count in blue at the top of every size", () => {
    const value = todayWidget().value;
    for (const size of SIZES) {
      const header = (value[size] as Piece).vstack as Piece[];
      const line = JSON.stringify(header[0]);
      expect(line, size).toContain('"text":"Today"');
      expect(line, size).toContain('"text":"$today.open"');
      expect(line, size).toContain('"color":"#007AFF"');
    }
  });

  it("draws the time red once late, grey before; the plain stand-in is grey only", () => {
    const widget = todayWidget();
    for (const size of SIZES) {
      expect(timeTextOf(widget.value, size).color, size).toEqual(LATE_COLOUR);
      expect(timeTextOf(widget.value, size).if, "no time for an all-day reminder").toBe("$item.time");
      expect(timeTextOf(widget.plain, size).color, "plain " + size).toBe("secondary");
    }
  });

  it("the plain stand-in is the same widget apart from the colour choice", () => {
    const widget = todayWidget();
    const withoutChoice = JSON.stringify(widget.value).split(JSON.stringify(LATE_COLOUR)).join('"secondary"');
    expect(withoutChoice).toBe(JSON.stringify(widget.plain));
  });
});

describe("Reminders widget: within the shell's rules", () => {
  it("passes the shell's widget: record type, both versions", () => {
    const widget = todayWidget();
    expect(shellTypeProblem(widget.key, widget.value)).toBeNull();
    expect(shellTypeProblem(widget.key, widget.plain)).toBeNull();
  });

  it("uses only pieces the shell knows, within the piece and depth limits", () => {
    const widget = todayWidget();
    for (const version of [widget.value, widget.plain]) {
      let pieceCount = 0;
      for (const size of SIZES) {
        for (const entry of piecesOf(version[size] as Piece)) {
          pieceCount += 1;
          const names = Object.keys(entry.piece).filter((name) => KNOWN_PIECES.includes(name));
          expect(names, JSON.stringify(entry.piece)).toHaveLength(1);
          expect(entry.depth).toBeLessThanOrEqual(12);
        }
      }
      expect(pieceCount).toBeLessThanOrEqual(150);
    }
  });

  it("taps only tick reminders; nothing writes a record directly", () => {
    const text = JSON.stringify(todayWidget().value);
    expect(text).not.toContain('"action"');
    expect(text).not.toContain('"increment"');
    expect(text).not.toContain('"set"');
    expect(text).not.toContain('"toggle"');
  });

  it("compares a stored widget apart from the stamped $type", () => {
    const widget = todayWidget();
    const stored = { ...JSON.parse(JSON.stringify(widget.value)), $type: "midas.widget" };
    expect(RemindersWidget.sameWidget(stored, widget.value)).toBe(true);
    expect(RemindersWidget.sameWidget(stored, widget.plain)).toBe(false);
    expect(RemindersWidget.sameWidget(null, widget.value)).toBe(false);
    const reordered = JSON.parse(JSON.stringify({ name: widget.value.name, ...widget.value }));
    expect(RemindersWidget.sameWidget(reordered, widget.value)).toBe(true);
  });
});

describe("Reminders widget: the page writes it", () => {
  it("publishes when the page loads and falls back to the plain stand-in when refused", () => {
    const loadStart = html.indexOf("async function firstLoad() {");
    const loadEnd = html.indexOf("\n  }\n", loadStart);
    expect(html.slice(loadStart, loadEnd)).toContain("await publishWidgets();");
    expect(html).toContain("await store.set(widget.key, widget.value);");
    expect(html).toContain("await store.set(widget.key, widget.plain);");
  });

  it("is page code only: the voice tools carry RemindersLogic, not the widget", () => {
    expect(tools).not.toContain("createRemindersWidget");
  });
});
