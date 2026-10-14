"""The shell's release settings for TestFlight (founder, 2026-10-11): the version stays 0.x until
the founder calls a 1.0; the version and build number in Info.plist come from project.yml, so
raising CURRENT_PROJECT_VERSION gives each upload a new build number; and passkeys use production
mode only (no ?mode=developer), since Apple's CDN serves the AASA for both servers."""
import plistlib
import re
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SHELL = REPO_ROOT / "shell"
PROJECT_YML = SHELL / "project.yml"
INFO_PLIST = SHELL / "Midas" / "Info.plist"
WIDGET_INFO_PLIST = SHELL / "MidasWidgets" / "Info.plist"
RELEASE_ENTITLEMENTS = SHELL / "Midas" / "Midas.entitlements"
# Every signed target and its one production entitlements file, in project.yml order
# (the widget extension was added by the founder plan of 2026-10-11, docs/briefs/widget-extension.md).
TARGET_ENTITLEMENTS = {
    "Midas": "Midas.entitlements",
    "MidasWidgets": "MidasWidgets.entitlements",
}
# Midas Test (founder, 2026-10-14, docs/PRODUCT.md section 6 "Shell"): each target's one extra
# entitlements file, used only by the Test build configuration.
TEST_TARGET_ENTITLEMENTS = {
    "Midas": "Midas-Test.entitlements",
    "MidasWidgets": "MidasWidgets-Test.entitlements",
}
LIVE_DOMAIN = "midas-api.midas-backend.workers.dev"
STAGING_DOMAIN = "midas-api-staging.midas-backend.workers.dev"


def project_setting(name):
    """Returns every value assigned to `name` in project.yml, comments ignored."""
    values = []
    for line in PROJECT_YML.read_text().splitlines():
        code = line.split("#", 1)[0]
        match = re.match(rf"\s*{name}:\s*(.+?)\s*$", code)
        if match:
            values.append(match.group(1).strip('"'))
    return values


def entitlements_assignments():
    """Returns (enclosing keys, value) for every CODE_SIGN_ENTITLEMENTS in project.yml, comments
    ignored, e.g. (("targets", "Midas", "settings", "configs", "Test"), "Midas/Midas-Test.entitlements")."""
    assignments = []
    # The enclosing YAML keys of the current line, as (indent, key), found by indentation.
    enclosing_keys = []
    for line in PROJECT_YML.read_text().splitlines():
        code = line.split("#", 1)[0].rstrip()
        match = re.match(r"(\s*)([^\s:][^:]*):\s*(.*)$", code)
        if not match:
            continue
        indent = len(match.group(1))
        key = match.group(2)
        while enclosing_keys and enclosing_keys[-1][0] >= indent:
            enclosing_keys.pop()
        if key == "CODE_SIGN_ENTITLEMENTS":
            key_path = tuple(enclosing_key for _, enclosing_key in enclosing_keys)
            assignments.append((key_path, match.group(3).strip('"')))
        enclosing_keys.append((indent, key))
    return assignments


class ReleaseConfigTests(unittest.TestCase):
    def test_marketing_version_is_zero_point_something(self):
        versions = project_setting("MARKETING_VERSION")
        self.assertEqual(len(versions), 1, "one MARKETING_VERSION in project.yml")
        self.assertRegex(versions[0], r"^0\.\d+(\.\d+)?$")

    def test_build_number_is_a_positive_integer(self):
        builds = project_setting("CURRENT_PROJECT_VERSION")
        self.assertEqual(len(builds), 1, "one CURRENT_PROJECT_VERSION in project.yml")
        self.assertRegex(builds[0], r"^[1-9]\d*$")

    def test_info_plist_takes_version_and_build_from_project_settings(self):
        # The app and the widget extension must carry the same version and build, or the App
        # Store upload fails; both read them from the one project setting.
        for plist_path in (INFO_PLIST, WIDGET_INFO_PLIST):
            with plist_path.open("rb") as plist_file:
                info = plistlib.load(plist_file)
            self.assertEqual(info["CFBundleShortVersionString"], "$(MARKETING_VERSION)", plist_path)
            self.assertEqual(info["CFBundleVersion"], "$(CURRENT_PROJECT_VERSION)", plist_path)
        # project.yml regenerates both Info.plists, so it must carry the same two lines per target.
        target_count = len(TARGET_ENTITLEMENTS)
        self.assertEqual(
            project_setting("CFBundleShortVersionString"), ["$(MARKETING_VERSION)"] * target_count)
        self.assertEqual(
            project_setting("CFBundleVersion"), ["$(CURRENT_PROJECT_VERSION)"] * target_count)

    def test_every_build_uses_the_one_production_entitlements_file(self):
        # Debug and Release (the everyday app) take the production file from each target's base
        # settings and must not override it; only the Test configuration (Midas Test, founder
        # 2026-10-14) overrides it, and only with that target's -Test file. Nothing else sets it.
        expected_assignments = []
        for target, file_name in TARGET_ENTITLEMENTS.items():
            expected_assignments.append(
                (("targets", target, "settings", "base"), f"{target}/{file_name}"))
            expected_assignments.append(
                (("targets", target, "settings", "configs", "Test"),
                 f"{target}/{TEST_TARGET_ENTITLEMENTS[target]}"))
        self.assertEqual(entitlements_assignments(), expected_assignments)
        for target, file_name in TARGET_ENTITLEMENTS.items():
            entitlement_files = sorted(path.name for path in (SHELL / target).glob("*.entitlements"))
            expected_files = sorted([file_name, TEST_TARGET_ENTITLEMENTS[target]])
            self.assertEqual(entitlement_files, expected_files, target)

    def test_passkey_domains_are_production_mode_for_both_servers(self):
        with RELEASE_ENTITLEMENTS.open("rb") as entitlements_file:
            entitlements = plistlib.load(entitlements_file)
        domains = entitlements["com.apple.developer.associated-domains"]
        self.assertEqual(sorted(domains), sorted([
            f"webcredentials:{LIVE_DOMAIN}",
            f"webcredentials:{STAGING_DOMAIN}",
        ]))
        for domain in domains:
            self.assertNotIn("mode=", domain)


if __name__ == "__main__":
    unittest.main()
