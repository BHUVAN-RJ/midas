"""Draws Make's home tile: the written word "Make" in Caveat Bold, set exactly as the jess tile
sets "Jess" (330 px on a 1024 px canvas, centred on the word's ink; ink on paper, dark variant
paper on ink). Pick K1 of docs/mockups/make-2026-10-23.html, the default until the founder picks
the tile (K5-K7 open).

To swap the tile for another pick, change WORD (or the drawing in draw_tile) and run it again; the
asset name, `MakeTile`, stays the same (`MakeTileIcon` in shell/Midas/SidekickHomeGrid.swift).

Writes the PNGs straight into ../Midas/Assets.xcassets/MakeTile.imageset/. Needs Pillow.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).parent
ASSET = HERE.parent / "Midas" / "Assets.xcassets" / "MakeTile.imageset"
CANVAS = 1024
FONT_SIZE = 330
WORD = "Make"
LOOKS = {
    "MakeTile.png": {"paper": "#FFFFFF", "ink": "#111111"},
    "MakeTile-dark.png": {"paper": "#111111", "ink": "#FFFFFF"},
}


def draw_tile(font, look):
    image = Image.new("RGB", (CANVAS, CANVAS), look["paper"])
    draw = ImageDraw.Draw(image)
    left, top, right, bottom = draw.textbbox((0, 0), WORD, font=font)
    # Centre the ink box on the canvas, as jess-tile.py does.
    x = CANVAS / 2 - (left + right) / 2
    y = CANVAS / 2 - (top + bottom) / 2
    draw.text((x, y), WORD, font=font, fill=look["ink"])
    return image


def main():
    font = ImageFont.truetype(str(HERE / "Caveat-Bold.ttf"), FONT_SIZE)
    for file_name, look in LOOKS.items():
        draw_tile(font, look).save(ASSET / file_name)


if __name__ == "__main__":
    main()
