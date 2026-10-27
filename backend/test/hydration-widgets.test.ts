// The Water Sidekick's Home Screen widget (docs/briefs/hydration-sidekick.md, sections 2.1 and
// 2.3; one widget since founder 2026-10-27, docs/PRODUCT.md "One Water widget": "in the water,
// there are still two options, like Water Today and Water Week, which should not be the case"):
// the page writes widget:today, named Water (small and medium the day, large adds the week chart),
// in the plan's syntax: {today} day keys (W1), a unit format on texts (W2), the streak source (W3), the sea
// fill and the widget background (W4). For a shell that refuses those, each has a plain stand-in
// made of today's pieces. The real shell checker runs on them in the shell's own tests; here the
// shape the plan fixes, the shell's record type and the widget limits (docs/WIDGETS.md).
process.env.TZ = "America/Los_Angeles";

import { readFileSync } from "node:fs";
import vm from "node:vm";
import { describe, expect, it } from "vitest";
import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import MidasShellTypes from "../../shell/sdk/shell-types.js";

const html = readFileSync(new URL("../../sidekicks/hydration/index.html", import.meta.url), "utf8");

function waterLogicSource(pageHtml: string) {
  const start = pageHtml.indexOf("var WaterLogic = (function createWaterLogic() {");
  const end = pageHtml.indexOf("\n})();\n", start) + "\n})();\n".length;
  return pageHtml.slice(start, end);
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const Logic: any = vm.runInNewContext(waterLogicSource(html) + "\n;WaterLogic;", {});

type Piece = Record<string, unknown>;
type Widget = Record<string, unknown>;

// The pieces every shell knows today (shell/Midas/SidekickWidgetDescription.swift)
const EXISTING_PIECES = ["vstack", "hstack", "grid", "list", "spacer", "divider", "text", "symbol", "bar", "ring", "dots", "chart", "timer", "tick", "button"];
const PROTECTED_PREFIXES = ["widget:", "request:", "reminder:"];
const TODAY_KEY = "water:{today}";

function settingsFor(unit: string) {
  return Logic.settingsFrom({ unit, goalMl: 2500 });
}

function widgetsFor(unit: string): Array<{ key: string; value: Widget; plain: Widget }> {
  return JSON.parse(JSON.stringify(Logic.widgetRecords(settingsFor(unit))));
}

function widgetByKey(unit: string, key: string) {
  for (const widget of widgetsFor(unit)) {
    if (widget.key === key) {
      return widget;
    }
  }
  throw new Error("no " + key);
}

function childrenOf(piece: Piece): Piece[] {
  const children: Piece[] = [];
  for (const name of ["vstack", "hstack", "grid"]) {
    if (Array.isArray(piece[name])) {
      children.push(...(piece[name] as Piece[]));
    }
  }
  if (piece.content && typeof piece.content === "object") {
    children.push(piece.content as Piece);
  }
  if (piece.row && typeof piece.row === "object") {
    children.push(piece.row as Piece);
  }
  return children;
}

// Every piece of a size, with its depth
function walk(piece: Piece, depth: number, visit: (piece: Piece, depth: number) => void) {
  visit(piece, depth);
  for (const child of childrenOf(piece)) {
    walk(child, depth + 1, visit);
  }
}

function piecesOf(widget: Widget) {
  const found: Array<{ piece: Piece; depth: number }> = [];
  function collect(piece: Piece, depth: number) {
    found.push({ piece, depth });
  }
  for (const size of ["small", "medium", "large"]) {
    if (widget[size]) {
      walk(widget[size] as Piece, 0, collect);
    }
  }
  return found;
}

function shellTypeProblem(key: string, value: Widget) {
  const stamped = MidasRecordSchema.stampType(MidasShellTypes, key, value);
  return MidasRecordSchema.checkRecord(MidasShellTypes, key, stamped);
}

function buttonsOf(widget: Widget) {
  const buttons: Piece[] = [];
  for (const entry of piecesOf(widget)) {
    if (typeof entry.piece.button === "string") {
      buttons.push(entry.piece);
    }
  }
  return buttons;
}

function textsWithBinding(widget: Widget, binding: string) {
  const texts: Piece[] = [];
  for (const entry of piecesOf(widget)) {
    if (typeof entry.piece.text === "string" && (entry.piece.text as string).includes(binding)) {
      texts.push(entry.piece);
    }
  }
  return texts;
}

describe("hydration widgets: the plan's syntax", () => {
  it("writes one widget, widget:today named Water, in small, medium and large", () => {
    const widgets = widgetsFor("ml");
    expect(widgets.length).toBe(1);
    expect(widgets[0].key).toBe("widget:today");
    const today = widgets[0].value;
    expect([Boolean(today.small), Boolean(today.medium), Boolean(today.large)]).toEqual([true, true, true]);
    expect(today.name).toBe("Water");
  });

  it("reads the day through {today} and the streak through the streak source (W1, W3)", () => {
    const today = widgetByKey("l", "widget:today").value;
    expect(today.sources).toEqual({
      day: { record: TODAY_KEY },
      settings: { record: "settings:main" },
      streak: { records: "water:", streak: { field: "ml", goal: "$settings.goalMl", dayGoalField: "goalMl" } },
      week: { records: "water:", sum: "ml", limit: 7 },
    });
  });

  it("puts every size on the sea fill, value the day's ml of the goal, on sand (W4)", () => {
    for (const entry of widgetsFor("oz")) {
      expect(entry.value.background, entry.key).toBe("#F4EEE3");
      for (const size of ["small", "medium", "large"]) {
        const sizePiece = entry.value[size] as Piece | undefined;
        if (!sizePiece) {
          continue;
        }
        expect(sizePiece.fill, entry.key + " " + size).toEqual({ value: "$day.ml", of: "$settings.goalMl" });
        expect(sizePiece.edge).toBe("wave");
        expect(sizePiece.color).toMatch(/^#[0-9A-F]{6}$/);
        expect(typeof sizePiece.content).toBe("object");
      }
    }
  });

  it("formats the amount and the goal in the person's unit, and leaves the streak unformatted (W2)", () => {
    for (const unit of ["ml", "l", "oz"]) {
      const today = widgetByKey(unit, "widget:today").value;
      const amountTexts = textsWithBinding(today, "$day.ml");
      expect(amountTexts.length).toBeGreaterThan(0);
      for (const text of amountTexts.concat(textsWithBinding(today, "$settings.goalMl"))) {
        expect(text.format, unit + " " + text.text).toBe(unit);
      }
      for (const text of textsWithBinding(today, "$streak.days")) {
        expect(text.format).toBeUndefined();
        expect(text.if).toBe("$streak.days");
      }
    }
  });

  it("shows 0 in the unit before today has a record", () => {
    const zeroTexts: string[] = [];
    for (const entry of piecesOf(widgetByKey("oz", "widget:today").value)) {
      if (entry.piece.unless === "$day.ml") {
        zeroTexts.push(entry.piece.text as string);
      }
    }
    expect(zeroTexts).toEqual(["0 oz", "0 oz", "0 oz"]);
  });

  it("logs the presets with increments on today's key, labelled in the unit", () => {
    const ounces = widgetByKey("oz", "widget:today").value;
    const labels: string[] = [];
    for (const button of buttonsOf(ounces)) {
      expect(button.action).toEqual({ increment: TODAY_KEY, field: "ml", by: expect.any(Number) });
      labels.push(button.button as string);
    }
    expect(labels).toEqual(["+8 oz", "+8 oz", "+16 oz", "+24 oz", "+8 oz", "+16 oz", "+24 oz"]);
    const litres = widgetByKey("l", "widget:today").value;
    const amounts: number[] = [];
    for (const button of buttonsOf(litres)) {
      amounts.push((button.action as { by: number }).by);
    }
    expect(amounts).toEqual([250, 250, 500, 750, 250, 500, 750]);
  });

  it("changes when the unit or the presets change, and not when the shell reorders keys", () => {
    const millilitres = widgetByKey("ml", "widget:today").value;
    const litres = widgetByKey("l", "widget:today").value;
    expect(Logic.sameWidget(millilitres, litres)).toBe(false);
    const customPresets = JSON.parse(JSON.stringify(Logic.widgetRecords(Logic.settingsFrom({ unit: "ml", presetsMl: [300, 500, 750] }))));
    expect(Logic.sameWidget(millilitres, customPresets[0].value)).toBe(false);
    const reordered: Widget = { $type: "midas.widget" };
    const names = Object.keys(millilitres);
    names.reverse();
    for (const name of names) {
      reordered[name] = millilitres[name];
    }
    expect(Logic.sameWidget(reordered, millilitres)).toBe(true);
    expect(Logic.sameWidget(null, millilitres)).toBe(false);
  });
});

describe("hydration widgets: limits and the shell's record type", () => {
  it("fits the midas.widget type and every widget limit, Tide and plain", () => {
    for (const unit of ["ml", "l", "oz"]) {
      for (const entry of widgetsFor(unit)) {
        for (const value of [entry.value, entry.plain]) {
          expect(shellTypeProblem(entry.key, value), entry.key).toBeNull();
          expect((value.name as string).length).toBeLessThanOrEqual(40);
          expect(Object.keys(value.sources as object).length).toBeLessThanOrEqual(8);
          expect(JSON.stringify(value).length).toBeLessThan(64 * 1024);
          const pieces = piecesOf(value);
          expect(pieces.length).toBeLessThanOrEqual(150);
          for (const found of pieces) {
            expect(found.depth).toBeLessThanOrEqual(12);
            for (const name of ["vstack", "hstack", "grid"]) {
              if (Array.isArray(found.piece[name])) {
                expect((found.piece[name] as unknown[]).length).toBeLessThanOrEqual(40);
              }
            }
            if (typeof found.piece.text === "string") {
              expect((found.piece.text as string).length).toBeLessThanOrEqual(200);
            }
          }
        }
      }
    }
  });

  it("never taps a protected record, and every button title fits", () => {
    for (const entry of widgetsFor("ml")) {
      for (const value of [entry.value, entry.plain]) {
        for (const button of buttonsOf(value)) {
          const title = button.button as string;
          expect(title.length).toBeGreaterThan(0);
          expect(title.length).toBeLessThanOrEqual(30);
          const target = (button.action as { increment: string }).increment;
          for (const prefix of PROTECTED_PREFIXES) {
            expect(target.startsWith(prefix)).toBe(false);
          }
        }
      }
    }
  });

  it("builds the plain stand-ins from today's pieces only: ring, text, buttons, chart", () => {
    for (const entry of widgetsFor("l")) {
      const plain = entry.plain;
      expect(plain.background).toBeUndefined();
      const names = new Set<string>();
      for (const found of piecesOf(plain)) {
        const pieceNames = Object.keys(found.piece).filter(isPieceName);
        expect(pieceNames.length, JSON.stringify(found.piece)).toBe(1);
        names.add(pieceNames[0]);
        expect(found.piece.format).toBeUndefined();
        expect(found.piece.fill).toBeUndefined();
      }
      expect(names.has("ring")).toBe(true);
      expect(names.has("button")).toBe(true);
      expect(names.has("text")).toBe(true);
      expect(JSON.stringify(plain.sources)).not.toContain("streak");
    }
  });
});

function isPieceName(name: string) {
  return EXISTING_PIECES.includes(name);
}
