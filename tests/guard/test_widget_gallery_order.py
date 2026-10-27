"""The iOS widget gallery lists Midas's widgets in WidgetBundle order. Sidekick comes first so the
"Add to Home Screen" sheet's steps land on it without a swipe (founder, 2026-10-25,
docs/mockups/widget-howto-demo-2026-10-25.html). Since 2026-10-26 (founder) the gallery lists only
Sidekick and Sidekicks: Reminders makes its widget with the widget builder."""
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
    def test_sidekick_is_the_first_widget_in_the_gallery(self):
        source = BUNDLE.read_text(encoding="utf-8")
        order = bundle_body_widget_order(source)
        self.assertEqual(sorted(order), sorted(HOME_SCREEN_WIDGETS), "every Home Screen widget is listed once")
        self.assertEqual(order[0], "SidekickWidget")


if __name__ == "__main__":
    unittest.main()
