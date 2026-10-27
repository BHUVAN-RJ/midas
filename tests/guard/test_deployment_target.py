"""The oldest iOS the app installs on (2026-10-26). project.yml sets deploymentTarget under
options:, the only place xcodegen reads it. Until 2026-10-26 it sat under configs:, where it is
ignored, so each build needed the iOS of the SDK it was built with: with Xcode 27, an iPhone on
iOS 26 could not install the TestFlight build."""
import re
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
PROJECT_YML = REPO_ROOT / "shell" / "project.yml"
OLDEST_IOS = "17.0"


def top_level_block(text, key):
    """The lines under a top-level YAML key, up to the next top-level key."""
    lines = text.splitlines()
    block = []
    inside = False
    for line in lines:
        is_top_level = bool(re.match(r"^[A-Za-z_]", line))
        if is_top_level:
            inside = line.startswith(key + ":")
            continue
        if inside:
            block.append(line)
    return "\n".join(block)


class DeploymentTargetTests(unittest.TestCase):
    def setUp(self):
        self.text = PROJECT_YML.read_text()

    def test_options_sets_the_oldest_ios(self):
        options = top_level_block(self.text, "options")
        match = re.search(r'^  deploymentTarget:\n    iOS: "([0-9.]+)"', options, re.MULTILINE)
        self.assertIsNotNone(match, "options: has no deploymentTarget iOS, so the SDK's iOS is the minimum")
        self.assertEqual(match.group(1), OLDEST_IOS)

    def test_configs_holds_no_deployment_target(self):
        configs = top_level_block(self.text, "configs")
        self.assertNotIn("deploymentTarget", configs, "xcodegen ignores deploymentTarget under configs:")


if __name__ == "__main__":
    unittest.main()
