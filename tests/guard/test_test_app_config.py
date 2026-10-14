"""Midas Test (founder, 2026-10-14): a second app on the same phone, so the everyday Midas stays the
same while updates are tried quickly. The Test configuration must differ from the everyday app in
bundle ID, App Group and name, talk to staging, and keep production-mode passkey domains; the
everyday app's own settings must not change."""
import plistlib
import re
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SHELL = REPO_ROOT / "shell"
PROJECT_YML = SHELL / "project.yml"
STAGING_DOMAIN = "midas-api-staging.midas-backend.workers.dev"
LIVE_DOMAIN = "midas-api.midas-backend.workers.dev"


def project_text():
    """project.yml with comments removed."""
    lines = []
    for line in PROJECT_YML.read_text().splitlines():
        code = line.split("#", 1)[0]
        lines.append(code)
    return "\n".join(lines)


def entitlements(relative_path):
    with open(SHELL / relative_path, "rb") as entitlements_file:
        return plistlib.load(entitlements_file)


class TestAppConfigTests(unittest.TestCase):
    def test_test_configuration_and_scheme_exist(self):
        text = project_text()
        self.assertRegex(text, r"\n\s+Test: debug\n")
        self.assertRegex(text, r"\n  Midas Test:\n")
        self.assertRegex(text, r"run:\n\s+config: Test")

    def test_test_app_has_its_own_identity(self):
        text = project_text()
        self.assertIn("PRODUCT_BUNDLE_IDENTIFIER: com.bhuvanrj.midas.test\n", text + "\n")
        self.assertIn("PRODUCT_BUNDLE_IDENTIFIER: com.bhuvanrj.midas.test.widgets", text)
        self.assertIn("MIDAS_APP_GROUP: group.com.bhuvanrj.midas.test", text)
        self.assertIn("MIDAS_DISPLAY_NAME: Midas Test", text)

    def test_everyday_app_identity_is_unchanged(self):
        text = project_text()
        self.assertIn("PRODUCT_BUNDLE_IDENTIFIER: com.bhuvanrj.midas\n", text)
        self.assertIn("PRODUCT_BUNDLE_IDENTIFIER: com.bhuvanrj.midas.widgets\n", text)
        self.assertIn("MIDAS_APP_GROUP: group.com.bhuvanrj.midas\n", text)
        self.assertIn("MIDAS_DISPLAY_NAME: Midas\n", text)

    def test_test_app_talks_to_staging(self):
        text = project_text()
        test_block = re.search(r"Test:\n\s+MIDAS_PLATFORM_HOST: (\S+)", text)
        self.assertIsNotNone(test_block)
        self.assertEqual(test_block.group(1), STAGING_DOMAIN)

    def test_test_entitlements_use_the_test_group_and_production_passkeys(self):
        app = entitlements("Midas/Midas-Test.entitlements")
        widgets = entitlements("MidasWidgets/MidasWidgets-Test.entitlements")
        self.assertEqual(app["com.apple.security.application-groups"], ["group.com.bhuvanrj.midas.test"])
        self.assertEqual(widgets["com.apple.security.application-groups"], ["group.com.bhuvanrj.midas.test"])
        domains = app["com.apple.developer.associated-domains"]
        self.assertEqual(sorted(domains), sorted([f"webcredentials:{LIVE_DOMAIN}", f"webcredentials:{STAGING_DOMAIN}"]))
        for domain in domains:
            self.assertNotIn("mode=", domain)

    def test_everyday_entitlements_keep_the_everyday_group(self):
        app = entitlements("Midas/Midas.entitlements")
        widgets = entitlements("MidasWidgets/MidasWidgets.entitlements")
        self.assertEqual(app["com.apple.security.application-groups"], ["group.com.bhuvanrj.midas"])
        self.assertEqual(widgets["com.apple.security.application-groups"], ["group.com.bhuvanrj.midas"])


if __name__ == "__main__":
    unittest.main()
