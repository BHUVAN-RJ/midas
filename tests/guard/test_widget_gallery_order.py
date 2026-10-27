"""The iOS widget gallery lists Midas's widgets in WidgetBundle order. Since 2026-10-26 (founder) the
gallery lists only Sidekick and Sidekicks: Reminders makes its widget with the widget builder.
Sidekicks (the folder widget) comes first (founder, 2026-10-27, docs/PRODUCT.md "Gallery order":
"lets get the folder things of all sidekicks to the front (in the list it should be the first)"),
then Sidekick; this replaces "Sidekick first, no swipe" (founder, 2026-10-25)."""
import re
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
BUNDLE = REPO_ROOT / "shell" / "MidasWidgets" / "MidasWidgetsBundle.swift"
HOME_SCREEN_WIDGETS = ["SidekickWidget", "FolderWidget"]


def bundle_body_widget_order(source):
    """The Home Screen widgets named in the bundle's body, in the order they are listed."""
    body_start = source.index("var body: some Widget")
    body = source[body_start:]
    names = re.findall(r"^\s*(\w+Widget)\(\)", body, flags=re.MULTILINE)
    return [name for name in names if name in HOME_SCREEN_WIDGETS]


class WidgetGalleryOrderTests(unittest.TestCase):
    def test_the_sidekicks_folder_is_the_first_widget_in_the_gallery(self):
        source = BUNDLE.read_text(encoding="utf-8")
        order = bundle_body_widget_order(source)
        self.assertEqual(sorted(order), sorted(HOME_SCREEN_WIDGETS), "every Home Screen widget is listed once")
        self.assertEqual(order, ["FolderWidget", "SidekickWidget"])


if __name__ == "__main__":
    unittest.main()
