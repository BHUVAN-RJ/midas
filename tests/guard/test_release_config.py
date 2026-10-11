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
RELEASE_ENTITLEMENTS = SHELL / "Midas" / "Midas.entitlements"
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
        with INFO_PLIST.open("rb") as plist_file:
            info = plistlib.load(plist_file)
        self.assertEqual(info["CFBundleShortVersionString"], "$(MARKETING_VERSION)")
        self.assertEqual(info["CFBundleVersion"], "$(CURRENT_PROJECT_VERSION)")
        # project.yml regenerates Info.plist, so it must carry the same two lines.
        self.assertEqual(project_setting("CFBundleShortVersionString"), ["$(MARKETING_VERSION)"])
        self.assertEqual(project_setting("CFBundleVersion"), ["$(CURRENT_PROJECT_VERSION)"])

    def test_every_build_uses_the_one_production_entitlements_file(self):
        self.assertEqual(project_setting("CODE_SIGN_ENTITLEMENTS"), ["Midas/Midas.entitlements"])
        entitlement_files = sorted(path.name for path in (SHELL / "Midas").glob("*.entitlements"))
        self.assertEqual(entitlement_files, ["Midas.entitlements"])

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
