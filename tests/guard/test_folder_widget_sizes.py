"""The Sidekicks (folder) widget comes in small only (founder, 2026-10-26: medium and large
removed, docs/mockups/widget-inventory-2026-10-26.html). iOS offers the sizes listed in
supportedFamilies, so that list is the gallery's."""
import re
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
FOLDER_WIDGET = REPO_ROOT / "shell" / "MidasWidgets" / "FolderWidget.swift"


def supported_families(source):
    """The families named in the widget's .supportedFamilies([...]) call."""
    match = re.search(r"\.supportedFamilies\(\[([^\]]*)\]\)", source)
    if match is None:
        return None
    families = re.findall(r"\.(system\w+)", match.group(1))
    return families


class FolderWidgetSizesTests(unittest.TestCase):
    def test_the_folder_widget_is_small_only(self):
        source = FOLDER_WIDGET.read_text(encoding="utf-8")
        self.assertEqual(supported_families(source), ["systemSmall"])


if __name__ == "__main__":
    unittest.main()
