// Light and dark for every widget (founder, 2026-10-27, docs/PRODUCT.md "Widget builder: light and
// dark for every widget"; seen on build 20 in dark mode: Water's light sand and sea with white
// text). Every widget a Sidekick page writes gives each explicit colour as { light, dark }: Water
// its own night Tide, Reminders iOS's dark blue and red. For an app build before 2026-10-27, which
// refuses pairs anywhere but the background and a fill, each page also has a fallback with pairs
// only there, then its plain stand-in. The rule reaches every repair agent through {{WIDGETS}}.
// The shell side (checker, filler, ink, the drawing) is checked in SidekickWidgetLightDarkTests.
process.env.TZ = "America/Los_Angeles";

import { readFileSync } from "node:fs";
import { join } from "node:path";
import vm from "node:vm";
import { describe, expect, it } from "vitest";
import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import MidasShellTypes from "../../shell/sdk/shell-types.js";
import { buildSystemPrompt } from "../../runner/lib/prompt.mjs";

const REPO_ROOT = join(__dirname, "..", "..");
const waterHtml = readFileSync(join(REPO_ROOT, "sidekicks", "hydration", "index.html"), "utf8");
const waterTools = readFileSync(join(REPO_ROOT, "sidekicks", "hydration", "tools.js"), "utf8");
const remindersHtml = readFileSync(join(REPO_ROOT, "sidekicks", "reminders", "index.html"), "utf8");
const widgetsDoc = readFileSync(join(REPO_ROOT, "docs", "WIDGETS.md"), "utf8");

type Piece = Record<string, unknown>;
type Widget = Record<string, unknown>;
type WidgetEntry = { key: string; value: Widget; fallback: Widget; plain: Widget };

const SIZES = ["small", "medium", "large"];
const RULE_HEADING = "## Light and dark (founder, 2026-10-27)";
const RULE_LINE = "**Rule for every new or repaired widget: give light and dark.**";

function blockBetween(source: string, startText: string) {
  const start = source.indexOf(startText);
  const end = source.indexOf("\n})();\n", start) + "\n})();\n".length;
  return source.slice(start, end);
}

const waterLogicSource = blockBetween(waterHtml, "var WaterLogic = (function createWaterLogic() {");
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const WaterLogic: any = vm.runInNewContext(waterLogicSource + "\n;WaterLogic;", {});
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const RemindersWidget: any = vm.runInNewContext(blockBetween(remindersHtml, "var RemindersWidget = (function createRemindersWidget() {") + "\n;RemindersWidget;", {});

function waterEntry(unit: string): WidgetEntry {
  const settings = WaterLogic.settingsFrom({ unit, goalMl: 2500 });
  const entries = JSON.parse(JSON.stringify(WaterLogic.widgetRecords(settings)));
  expect(entries).toHaveLength(1);
  return entries[0];
}

function remindersEntry(): WidgetEntry {
  const entries = JSON.parse(JSON.stringify(RemindersWidget.widgetRecords()));
  expect(entries).toHaveLength(1);
  return entries[0];
}

function childrenOf(piece: Piece): Piece[] {
  const children: Piece[] = [];
  for (const name of ["vstack", "hstack", "grid"]) {
    if (Array.isArray(piece[name])) {
      children.push(...(piece[name] as Piece[]));
    }
  }
  for (const name of ["content", "row"]) {
    if (piece[name] && typeof piece[name] === "object") {
      children.push(piece[name] as Piece);
    }
  }
  return children;
}

function piecesOf(widget: Widget): Piece[] {
  const found: Piece[] = [];
  const waiting: Piece[] = [];
  for (const size of SIZES) {
    if (widget[size]) {
      waiting.push(widget[size] as Piece);
    }
  }
  while (waiting.length > 0) {
    const piece = waiting.shift() as Piece;
    found.push(piece);
    waiting.push(...childrenOf(piece));
  }
  return found;
}

function isPair(colour: unknown): colour is { light: string; dark: string } {
  if (colour === null || typeof colour !== "object") {
    return false;
  }
  const fields = colour as Record<string, unknown>;
  return typeof fields.light === "string" && typeof fields.dark === "string";
}

function isHex(colour: unknown) {
  return typeof colour === "string" && /^#[0-9A-Fa-f]{6}$/.test(colour);
}

// Every explicit colour a widget names: the background, each piece's colour, a choice's branches
function explicitColours(widget: Widget): unknown[] {
  const colours: unknown[] = [];
  if (widget.background !== undefined) {
    colours.push(widget.background);
  }
  for (const piece of piecesOf(widget)) {
    const colour = piece.color as Record<string, unknown> | string | undefined;
    if (colour === undefined) {
      continue;
    }
    if (typeof colour === "object" && "if" in colour) {
      colours.push(colour.then);
      if (colour.else !== undefined) {
        colours.push(colour.else);
      }
      continue;
    }
    colours.push(colour);
  }
  return colours;
}

const COLOUR_NAMES = ["primary", "secondary", "accent", "red", "orange", "yellow", "green", "cyan", "blue", "indigo", "pink", "purple", "brown", "gray", "mint"];

function isSingleExplicitColour(colour: unknown) {
  return isHex(colour) || (typeof colour === "string" && COLOUR_NAMES.includes(colour) && !["primary", "secondary"].includes(colour));
}

function hueOf(hex: string) {
  const red = parseInt(hex.slice(1, 3), 16) / 255;
  const green = parseInt(hex.slice(3, 5), 16) / 255;
  const blue = parseInt(hex.slice(5, 7), 16) / 255;
  const highest = Math.max(red, green, blue);
  const lowest = Math.min(red, green, blue);
  const spread = highest - lowest;
  if (spread === 0) {
    return null;
  }
  let hue;
  if (highest === red) {
    hue = ((green - blue) / spread) % 6;
  } else if (highest === green) {
    hue = (blue - red) / spread + 2;
  } else {
    hue = (red - green) / spread + 4;
  }
  hue *= 60;
  return hue < 0 ? hue + 360 : hue;
}

// The page's night Tide tokens, from its @media (prefers-color-scheme: dark) block
function nightToken(name: string) {
  const darkStart = waterHtml.indexOf("@media (prefers-color-scheme: dark)");
  const darkBlock = waterHtml.slice(darkStart, waterHtml.indexOf("\n}\n", darkStart));
  const match = darkBlock.match(new RegExp("--" + name + ":\\s*(#[0-9A-Fa-f]{6})"));
  if (!match) {
    throw new Error("no night --" + name);
  }
  return match[1].toUpperCase();
}

function shellTypeProblem(key: string, value: Widget) {
  const stamped = MidasRecordSchema.stampType(MidasShellTypes, key, value);
  return MidasRecordSchema.checkRecord(MidasShellTypes, key, stamped);
}

describe("Water's widget in light and dark", () => {
  it("gives every explicit colour as { light, dark }, in every unit", () => {
    for (const unit of ["ml", "l", "oz"]) {
      const colours = explicitColours(waterEntry(unit).value);
      expect(colours.length).toBeGreaterThan(10);
      for (const colour of colours) {
        expect(isPair(colour), unit + " " + JSON.stringify(colour)).toBe(true);
        const pair = colour as { light: string; dark: string };
        expect(isHex(pair.light) && isHex(pair.dark), JSON.stringify(pair)).toBe(true);
      }
    }
  });

  it("is the page's own night Tide in dark: sand, sea, ink and accent", () => {
    const value = waterEntry("l").value;
    expect(value.background).toEqual({ light: "#F4EEE3", dark: nightToken("sand") });
    for (const size of SIZES) {
      const sizePiece = value[size] as Piece;
      expect(sizePiece.fill, size).toEqual({ value: "$day.ml", of: "$settings.goalMl" });
      expect(sizePiece.color, size).toEqual({ light: "#9CCFD3", dark: nightToken("sea-top") });
    }
    const amountTexts = piecesOf(value).filter(isAmountText);
    expect(amountTexts.length).toBe(6);
    for (const text of amountTexts) {
      expect((text.color as { dark: string }).dark).toBe(nightToken("ink"));
    }
    const buttonsAndChart = piecesOf(value).filter(isButtonOrChart);
    expect(buttonsAndChart.length).toBe(1 + 3 + 3 + 1);
    for (const piece of buttonsAndChart) {
      expect(piece.color, JSON.stringify(piece)).toEqual({ light: "#2F7E87", dark: nightToken("accent") });
    }
  });

  it("never derives purple: no dark colour has a purple hue", () => {
    for (const colour of explicitColours(waterEntry("ml").value)) {
      const hue = hueOf((colour as { dark: string }).dark);
      if (hue !== null) {
        expect(hue < 260 || hue > 320, JSON.stringify(colour)).toBe(true);
      }
    }
  });

  it("has a fallback for builds before 2026-10-27: pairs only on the background and the sea", () => {
    const entry = waterEntry("l");
    expect(entry.fallback.background).toEqual(entry.value.background);
    for (const size of SIZES) {
      expect((entry.fallback[size] as Piece).color).toEqual((entry.value[size] as Piece).color);
    }
    for (const piece of piecesOf(entry.fallback)) {
      if (piece.fill === undefined) {
        expect(typeof piece.color === "object", JSON.stringify(piece)).toBe(false);
      }
    }
    // The same widget apart from the colours: same pieces, texts and taps
    expect(JSON.stringify(withoutColours(entry.fallback))).toBe(JSON.stringify(withoutColours(entry.value)));
  });

  it("keeps the plain stand-in without any pair, on the system background", () => {
    const plain = waterEntry("oz").plain;
    expect(plain.background).toBeUndefined();
    for (const colour of explicitColours(plain)) {
      expect(isPair(colour), JSON.stringify(colour)).toBe(false);
    }
  });

  it("fits the shell's widget: type in all three versions", () => {
    const entry = waterEntry("ml");
    for (const version of [entry.value, entry.fallback, entry.plain]) {
      expect(shellTypeProblem(entry.key, version)).toBeNull();
    }
    expect(typeof entry.value.tint, "tint stays one colour (the server's widget type)").toBe("string");
  });

  it("writes light and dark first, then the fallback, then the plain stand-in", () => {
    const valueAt = waterHtml.indexOf("await store.set(widget.key, widget.value);");
    const fallbackAt = waterHtml.indexOf("await store.set(widget.key, widget.fallback);");
    const plainAt = waterHtml.indexOf("await store.set(widget.key, widget.plain);");
    expect(valueAt).toBeGreaterThan(-1);
    expect(fallbackAt).toBeGreaterThan(valueAt);
    expect(plainAt).toBeGreaterThan(fallbackAt);
  });

  it("carries the same WaterLogic in tools.js as on the page", () => {
    expect(waterTools).toContain(waterLogicSource);
  });
});

describe("Reminders' widget in light and dark", () => {
  it("gives Today, the count and the late red as { light, dark }", () => {
    const value = remindersEntry().value;
    let pairs = 0;
    for (const colour of explicitColours(value)) {
      expect(isSingleExplicitColour(colour), JSON.stringify(colour)).toBe(false);
      if (isPair(colour)) {
        pairs += 1;
        expect([{ light: "#007AFF", dark: "#0A84FF" }, { light: "#FF3B30", dark: "#FF453A" }]).toContainEqual(colour);
      }
    }
    expect(pairs).toBe(3 * 2 + 3);
  });

  it("falls back to the widget from before 2026-10-27, then to grey times", () => {
    const entry = remindersEntry();
    const fallbackText = JSON.stringify(entry.fallback);
    expect(fallbackText).toContain('"color":"#007AFF"');
    expect(fallbackText).toContain('{"if":"$item.late","then":"red","else":"secondary"}');
    expect(fallbackText).not.toContain('"light"');
    const withoutChoice = fallbackText.split('{"if":"$item.late","then":"red","else":"secondary"}').join('"secondary"');
    expect(withoutChoice).toBe(JSON.stringify(entry.plain));
    expect(JSON.stringify(withoutColours(entry.fallback))).toBe(JSON.stringify(withoutColours(entry.value)));
    for (const version of [entry.value, entry.fallback, entry.plain]) {
      expect(shellTypeProblem(entry.key, version)).toBeNull();
    }
  });

  it("writes light and dark first, then the fallback, then the plain stand-in", () => {
    const valueAt = remindersHtml.indexOf("await store.set(widget.key, widget.value);");
    const fallbackAt = remindersHtml.indexOf("await store.set(widget.key, widget.fallback);");
    const plainAt = remindersHtml.indexOf("await store.set(widget.key, widget.plain);");
    expect(valueAt).toBeGreaterThan(-1);
    expect(fallbackAt).toBeGreaterThan(valueAt);
    expect(plainAt).toBeGreaterThan(fallbackAt);
  });
});

describe("the light and dark rule for widget makers", () => {
  it("is in docs/WIDGETS.md", () => {
    const ruleStart = widgetsDoc.indexOf(RULE_HEADING);
    expect(ruleStart).toBeGreaterThan(-1);
    const rule = widgetsDoc.slice(ruleStart, widgetsDoc.indexOf("\n## ", ruleStart + 1));
    expect(rule).toContain(RULE_LINE);
    expect(rule).toContain("never purple");
    expect(rule).toContain("{ light, dark }");
  });

  for (const sidekickId of ["hydration", "reminders"]) {
    it(`reaches the ${sidekickId} repair agent`, () => {
      const manifestText = readFileSync(join(REPO_ROOT, "sidekicks", sidekickId, "manifest.json"), "utf8");
      const job = { sidekickId, kind: "change", id: "r-91", createdAt: "2026-10-27T20:00:00.000Z", transcript: "the widget is unreadable at night" };
      const prompt = buildSystemPrompt({ job, reportFiles: ["transcript.txt"], manifestText, checkoutRoot: REPO_ROOT, intelToolPath: "/r/intel.mjs", checkToolPath: "/r/check.mjs" });
      expect(prompt).toContain(RULE_HEADING);
      expect(prompt).toContain(RULE_LINE);
      expect(prompt).not.toMatch(/\{\{[A-Z_0-9]+\}\}/);
    });
  }
});

function isAmountText(piece: Piece) {
  return typeof piece.text === "string" && (piece.if === "$day.ml" || piece.unless === "$day.ml");
}

function isButtonOrChart(piece: Piece) {
  return typeof piece.button === "string" || typeof piece.chart === "string";
}

// A widget with every piece's colour taken out, to compare two versions' pieces
function withoutColours(widget: Widget): Widget {
  const copy = JSON.parse(JSON.stringify(widget));
  delete copy.background;
  for (const piece of piecesOf(copy)) {
    delete piece.color;
  }
  return copy;
}
