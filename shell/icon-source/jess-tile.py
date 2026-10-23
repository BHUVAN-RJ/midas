"""Draws jess's home tile: the written word "Jess" in Caveat Bold, exactly as the Midas icon sets
"Midas" (founder, 2026-10-22, option V1 of docs/mockups/jess-look-2026-10-22-r4.html).

The letters are the font's own glyphs (J, e, s, s), taken as outlines so the tile does not depend on
font rendering. Same size as the Midas icon (330 px on a 1024 px canvas), centred on the word's ink.
Writes jess-tile-light.svg and jess-tile-dark.svg next to this file; README.md turns them into PNGs.

Needs fontTools (pip install fonttools).
"""

from pathlib import Path

from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

HERE = Path(__file__).parent
CANVAS = 1024
FONT_SIZE = 330
LETTERS = ["J", "e", "s", "s"]
LOOKS = {
    "light": {"paper": "#FFFFFF", "ink": "#111111"},
    "dark": {"paper": "#111111", "ink": "#FFFFFF"},
}


def word_outline(glyph_set):
    """The word's outline in font units (y down) and its ink box."""
    path_pen = SVGPathPen(glyph_set)
    bounds_pen = BoundsPen(glyph_set)
    advance = 0
    for name in LETTERS:
        # Flip y so the outline reads top-down like SVG.
        flip = (1, 0, 0, -1, advance, 0)
        glyph_set[name].draw(TransformPen(path_pen, flip))
        glyph_set[name].draw(TransformPen(bounds_pen, flip))
        advance += glyph_set[name].width
    return path_pen.getCommands(), bounds_pen.bounds


def tile_svg(outline, ink_box, look):
    scale = FONT_SIZE / 1000
    left, top, right, bottom = ink_box
    # Centre the ink box on the canvas, as the jess-look mockups do.
    shift_x = CANVAS / 2 - (left + right) / 2 * scale
    shift_y = CANVAS / 2 - (top + bottom) / 2 * scale
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS}" height="{CANVAS}" '
        f'viewBox="0 0 {CANVAS} {CANVAS}">'
        f'<rect width="{CANVAS}" height="{CANVAS}" fill="{look["paper"]}"/>'
        f'<path transform="translate({shift_x:.2f} {shift_y:.2f}) scale({scale})" '
        f'd="{outline}" fill="{look["ink"]}"/></svg>\n'
    )


def main():
    glyph_set = TTFont(HERE / "Caveat-Bold.ttf").getGlyphSet()
    outline, ink_box = word_outline(glyph_set)
    for name, look in LOOKS.items():
        (HERE / f"jess-tile-{name}.svg").write_text(tile_svg(outline, ink_box, look))


if __name__ == "__main__":
    main()
