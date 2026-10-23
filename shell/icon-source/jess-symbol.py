"""Draws jess's control symbol: the written "Jess" in Caveat Bold as a one-colour custom SF Symbol
(founder, 2026-10-23, option G8 of docs/mockups/jess-shortcuts-2026-10-23.html).

Control Center, the Lock Screen and the Action button (as a control) take a symbol, not a picture;
this is the same word as jess's home tile, set on the SF Symbols template's Regular-M guides (the
J's cap height on the cap line). Writes the symbol set into shell/Shared/Shared.xcassets, which is
compiled into the app and the widget extension.

Needs fontTools (pip install fonttools).
"""

from pathlib import Path

from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

HERE = Path(__file__).parent
SYMBOL_SET = HERE.parent / "Shared" / "Shared.xcassets" / "JessSymbol.symbolset"
LETTERS = ["J", "e", "s", "s"]
# SF Symbols template v3, Regular-M: baseline, cap line and where the glyph column starts.
BASELINE = 1126
CAPLINE = 1055.54
LEFT = 1391


def word_outline(glyph_set, scale):
    """The word's outline in template units (y down, baseline at BASELINE) and its ink box."""
    path_pen = SVGPathPen(glyph_set)
    bounds_pen = BoundsPen(glyph_set)
    advance = 0
    for name in LETTERS:
        # Font units are y up; the template is y down with the baseline at BASELINE.
        place = (scale, 0, 0, -scale, LEFT + advance * scale, BASELINE)
        glyph_set[name].draw(TransformPen(path_pen, place))
        glyph_set[name].draw(TransformPen(bounds_pen, place))
        advance += glyph_set[name].width
    return path_pen.getCommands(), bounds_pen.bounds


def symbol_svg(outline, ink_box):
    left, _, right, _ = ink_box
    lines = [
        ("Baseline-S", 696), ("Capline-S", 625.541), ("Baseline-M", BASELINE),
        ("Capline-M", CAPLINE), ("Baseline-L", 1556), ("Capline-L", 1485.54),
    ]
    guides = "".join(
        f'<line id="{name}" style="fill:none;stroke:#27AAE1;stroke-width:0.5;" x1="263" x2="3036" y1="{y}" y2="{y}"/>'
        for name, y in lines
    )
    margins = (
        f'<line id="left-margin-Regular-M" style="fill:none;stroke:#00AEEF;stroke-width:0.5;" x1="{left:.2f}" x2="{left:.2f}" y1="1030" y2="1150"/>'
        f'<line id="right-margin-Regular-M" style="fill:none;stroke:#00AEEF;stroke-width:0.5;" x1="{right:.2f}" x2="{right:.2f}" y1="1030" y2="1150"/>'
    )
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">\n'
        '<svg version="1.1" xmlns="http://www.w3.org/2000/svg" width="3300" height="2200">\n'
        '<g id="Notes"><text id="template-version" style="font-family:\'LucidaGrande\';font-size:13;" '
        'transform="matrix(1 0 0 1 2952.79 1933.8)">Template v.3.0</text></g>\n'
        f'<g id="Guides">{guides}{margins}</g>\n'
        f'<g id="Symbols"><g id="Regular-M"><path d="{outline}"/></g></g>\n'
        '</svg>\n'
    )


def main():
    font = TTFont(HERE / "Caveat-Bold.ttf")
    glyph_set = font.getGlyphSet()
    # The J's top sits on the cap line, as a capital does in SF Symbols.
    j_bounds = BoundsPen(glyph_set)
    glyph_set["J"].draw(j_bounds)
    scale = (BASELINE - CAPLINE) / j_bounds.bounds[3]
    outline, ink_box = word_outline(glyph_set, scale)
    SYMBOL_SET.mkdir(parents=True, exist_ok=True)
    (SYMBOL_SET / "JessSymbol.svg").write_text(symbol_svg(outline, ink_box))
    (SYMBOL_SET / "Contents.json").write_text(
        '{\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  },\n'
        '  "symbols" : [\n    {\n      "filename" : "JessSymbol.svg",\n      "idiom" : "universal"\n    }\n  ]\n}\n'
    )


if __name__ == "__main__":
    main()
