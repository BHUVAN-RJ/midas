"""The shell app icon must satisfy App Store Connect (2026-10-11 decision: handwritten "Midas",
black on white). Checks the files TestFlight rejects a build for: a 1024x1024 PNG with no alpha
channel in the "Any Appearance" slot, plus the dark and tinted variants the catalog declares."""
import json
import struct
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
ICON_SET = REPO_ROOT / "shell" / "Midas" / "Assets.xcassets" / "AppIcon.appiconset"
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
RGB_COLOUR_TYPE = 2
RGBA_COLOUR_TYPE = 6


def read_png_header(path):
    """Returns (width, height, colour_type) from the IHDR chunk."""
    data = path.read_bytes()
    if data[:8] != PNG_SIGNATURE:
        raise AssertionError(f"{path.name} is not a PNG")
    width, height = struct.unpack(">II", data[16:24])
    colour_type = data[25]
    return width, height, colour_type


class AppIconTests(unittest.TestCase):
    def setUp(self):
        self.contents = json.loads((ICON_SET / "Contents.json").read_text())

    def test_any_appearance_icon_is_1024_png_without_alpha(self):
        any_entries = [image for image in self.contents["images"] if "appearances" not in image]
        self.assertEqual(len(any_entries), 1, "exactly one Any Appearance icon")
        entry = any_entries[0]
        self.assertEqual(entry["size"], "1024x1024")
        self.assertEqual(entry["platform"], "ios")
        width, height, colour_type = read_png_header(ICON_SET / entry["filename"])
        self.assertEqual((width, height), (1024, 1024))
        self.assertNotEqual(colour_type, RGBA_COLOUR_TYPE, "App Store icon must not have an alpha channel")
        self.assertEqual(colour_type, RGB_COLOUR_TYPE)

    def test_dark_and_tinted_variants_exist_at_1024(self):
        declared = {}
        for image in self.contents["images"]:
            for appearance in image.get("appearances", []):
                declared[appearance["value"]] = image
        self.assertEqual(set(declared), {"dark", "tinted"})
        for value, image in declared.items():
            with self.subTest(appearance=value):
                self.assertEqual(image["size"], "1024x1024")
                width, height, _ = read_png_header(ICON_SET / image["filename"])
                self.assertEqual((width, height), (1024, 1024))

    def test_every_declared_file_exists_and_no_stray_files(self):
        declared_files = {image["filename"] for image in self.contents["images"]}
        on_disk = {path.name for path in ICON_SET.iterdir() if path.suffix == ".png"}
        self.assertEqual(declared_files, on_disk)


if __name__ == "__main__":
    unittest.main()
