// The Sounds Sidekick's Home Screen widget (docs/WIDGETS.md, "Every Sidekick ships a widget",
// founder 2026-11-02; blueprint in docs/briefs/soundboard-sidekick.md, "Widget"): widget:sounds,
// named Sounds, small and medium, the count and the first names, "No Sounds" when the board is
// empty. Every colour light and dark (founder, 2026-10-27); for older builds the same widget with
// pairs only on the background, then a plain one. A widget cannot draw a GIF or play a sound, so
// it has no taps: tapping it opens Sounds. The shell's own checker and filler run on it in
// shell/MidasTests/SoundboardSidekickTests.swift; here the shape, the limits and the colours.
import { readFileSync } from "node:fs";
import vm from "node:vm";
import { describe, expect, it } from "vitest";

const html = readFileSync(new URL("../../sidekicks/soundboard/index.html", import.meta.url), "utf8");

function soundsLogicSource(pageHtml: string) {
  const start = pageHtml.indexOf("var SoundsLogic = (function createSoundsLogic() {");
  const end = pageHtml.indexOf("\n})();\n", start) + "\n})();\n".length;
  return pageHtml.slice(start, end);
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const Logic: any = vm.runInNewContext(soundsLogicSource(html) + "\n;SoundsLogic;", {});

type Piece = Record<string, unknown>;
type Widget = Record<string, unknown>;

// The pieces every shell knows (shell/Midas/SidekickWidgetDescription.swift)
const KNOWN_PIECES = ["vstack", "hstack", "grid", "list", "spacer", "divider", "text", "symbol", "bar", "ring", "dots", "chart", "timer", "tick", "button"];
const COLOUR_PATTERN = /^#[0-9A-Fa-f]{6}$/;

function widgets(): Array<{ key: string; value: Widget; fallback: Widget; plain: Widget }> {
  return JSON.parse(JSON.stringify(Logic.widgetRecords()));
}

function theWidget() {
  const all = widgets();
  expect(all.length).toBe(1);
  return all[0];
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

function collectPieces(piece: Piece, depth: number, found: Array<{ piece: Piece; depth: number }>) {
  found.push({ piece, depth });
  for (const child of childrenOf(piece)) {
    collectPieces(child, depth + 1, found);
  }
}

function piecesOf(widget: Widget) {
  const found: Array<{ piece: Piece; depth: number }> = [];
  for (const size of ["small", "medium", "large"]) {
    if (widget[size]) {
      collectPieces(widget[size] as Piece, 0, found);
    }
  }
  return found;
}

function pieceName(piece: Piece): string | undefined {
  for (const name of KNOWN_PIECES) {
    if (piece[name] !== undefined) {
      return name;
    }
  }
  return undefined;
}

function isPair(colour: unknown): boolean {
  if (colour === null || typeof colour !== "object") {
    return false;
  }
  const pair = colour as Record<string, unknown>;
  return COLOUR_PATTERN.test(String(pair.light)) && COLOUR_PATTERN.test(String(pair.dark));
}

describe("soundboard widget: what it shows", () => {
  it("is widget:sounds, named Sounds, in small and medium, version 1", () => {
    const widget = theWidget();
    expect(widget.key).toBe("widget:sounds");
    expect(widget.value.name).toBe("Sounds");
    expect(widget.value.version).toBe(1);
    expect(widget.value.small).toBeTruthy();
    expect(widget.value.medium).toBeTruthy();
  });

  it("reads the sound records and lists their names with the count, No Sounds when empty", () => {
    const widget = theWidget();
    for (const choice of [widget.value, widget.fallback, widget.plain]) {
      const sources = choice.sources as Record<string, Record<string, unknown>>;
      expect(sources.sounds.records).toBe("sound:");
      expect(sources.sounds.limit as number).toBeLessThanOrEqual(50);
      const pieces = piecesOf(choice);
      const lists = pieces.filter(isListPiece);
      expect(lists.length).toBe(2);
      for (const entry of lists) {
        expect(entry.piece.list).toBe("$sounds.items");
        expect(entry.piece.empty).toBe("No Sounds");
        expect((entry.piece.row as Piece).text).toBe("$item.name");
      }
      const countTexts = pieces.filter(isCountText);
      expect(countTexts.length).toBe(2);
    }
  });

  it("has no taps: it cannot play a sound, so tapping it opens Sounds", () => {
    const widget = theWidget();
    for (const entry of piecesOf(widget.value)) {
      expect(entry.piece.button).toBeUndefined();
      expect(entry.piece.tick).toBeUndefined();
      expect(entry.piece.action).toBeUndefined();
    }
  });
});

function isListPiece(entry: { piece: Piece }) {
  return entry.piece.list !== undefined;
}

function isCountText(entry: { piece: Piece }) {
  return entry.piece.text === "$sounds.count";
}

describe("soundboard widget: light and dark, and older builds", () => {
  it("gives every colour as a light and dark pair, Lemon by day", () => {
    const widget = theWidget().value;
    expect(widget.background).toEqual({ light: "#FFE600", dark: "#1A1A1A" });
    let coloured = 0;
    for (const entry of piecesOf(widget)) {
      if (entry.piece.color !== undefined) {
        coloured += 1;
        expect(isPair(entry.piece.color), JSON.stringify(entry.piece)).toBe(true);
      }
    }
    expect(coloured).toBeGreaterThan(4);
  });

  it("the fallback keeps the background pair and drops every other colour; the plain one has none", () => {
    const widget = theWidget();
    expect(widget.fallback.background).toEqual({ light: "#FFE600", dark: "#1A1A1A" });
    for (const entry of piecesOf(widget.fallback)) {
      expect(entry.piece.color).toBeUndefined();
    }
    expect(widget.plain.background).toBeUndefined();
    for (const entry of piecesOf(widget.plain)) {
      expect(entry.piece.color).toBeUndefined();
    }
  });

  it("stays inside the widget limits and uses only pieces every shell knows", () => {
    for (const choice of [theWidget().value, theWidget().fallback, theWidget().plain]) {
      const pieces = piecesOf(choice);
      expect(pieces.length).toBeLessThanOrEqual(150);
      for (const entry of pieces) {
        expect(entry.depth).toBeLessThan(12);
        expect(pieceName(entry.piece), JSON.stringify(entry.piece)).toBeDefined();
        if (typeof entry.piece.text === "string") {
          expect((entry.piece.text as string).length).toBeLessThanOrEqual(200);
        }
      }
      expect(JSON.stringify(choice).length).toBeLessThan(64 * 1024);
    }
  });

  it("is rewritten only when it changed: a stored copy with $type matches", () => {
    const widget = theWidget();
    const stored = { ...JSON.parse(JSON.stringify(widget.value)), $type: "midas.widget" };
    expect(Logic.sameWidget(stored, widget.value)).toBe(true);
    expect(Logic.sameWidget(stored, widget.fallback)).toBe(false);
    expect(Logic.sameWidget(null, widget.value)).toBe(false);
  });
});
