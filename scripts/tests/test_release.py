import hashlib
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts import release


class ReleaseTests(unittest.TestCase):
    def metadata(self, mode="unsigned"):
        return {"CFBundleIdentifier": release.BUNDLE_ID + (".dev" if mode == "local" else ""),
                "CFBundlePackageType": "APPL", "CFBundleExecutable": "FocusDesk",
                "CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1",
                "LSMinimumSystemVersion": "14.0", "LSRequiresNativeExecution": True,
                "CFBundleIconFile": "AppIcon.icns"}

    def entitlements(self):
        return release.read_plist(release.ROOT / "Config/FocusDesk.entitlements")

    def test_local_and_production_workspaces_are_distinct(self):
        release.validate_metadata(self.metadata("local"), "local")
        release.validate_metadata(self.metadata(), "direct")
        release.validate_metadata(self.metadata(), "app-store")
        with self.assertRaises(ValueError):
            release.validate_metadata(self.metadata("local"), "direct")
        with self.assertRaises(ValueError):
            release.validate_metadata(self.metadata(), "local")

    def test_missing_icon_and_unresolved_version_are_rejected(self):
        for key, value in [("CFBundleIconFile", None), ("CFBundleVersion", "$(CURRENT_PROJECT_VERSION)"),
                           ("LSRequiresNativeExecution", False), ("LSMinimumSystemVersion", "13.0")]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                release.validate_metadata({**self.metadata(), key: value}, "unsigned")

    def test_version_numbers(self):
        release.validate_versions(*release.versions())
        for version, build in [("beta", "1"), ("1.0", "1"), ("1.0.0", "0"), ("1.0.0", "../../out")]:
            with self.subTest(version=version, build=build), self.assertRaises(ValueError):
                release.validate_versions(version, build)

    def test_entitlements_are_minimal_for_both_channels(self):
        for mode in ["local", "direct", "app-store"]:
            release.validate_entitlements(self.entitlements(), mode)
        for extra in ["com.apple.security.network.client", "com.apple.security.cs.disable-library-validation",
                      "com.apple.security.get-task-allow", "com.apple.security.application-groups"]:
            with self.subTest(extra=extra), self.assertRaises(ValueError):
                release.validate_entitlements({**self.entitlements(), extra: True}, "direct")

    def test_sandbox_cannot_be_disabled(self):
        for mode in ["local", "direct", "app-store"]:
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                release.validate_entitlements({"com.apple.security.app-sandbox": False}, mode)

    def test_ad_hoc_signature_is_never_a_distribution_signature(self):
        release.validate_signature("Signature=adhoc\n", "local")
        for mode in ["direct", "app-store"]:
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                release.validate_signature("Signature=adhoc\n", mode)

    def test_direct_signature_requires_runtime_and_timestamp(self):
        details = "Authority=Developer ID Application: Test (ABCDEFGHIJ)\nflags=0x10000(runtime)\nTimestamp=test\n"
        release.validate_signature(details, "direct")
        for invalid in [details.replace("(runtime)", ""), details.replace("Timestamp=", "Signed Time=")]:
            with self.assertRaises(ValueError):
                release.validate_signature(invalid, "direct")
        with self.assertRaises(ValueError):
            release.validate_signature(details, "app-store")

    def test_export_never_uploads_or_changes_version(self):
        for channel, method in [("direct", "developer-id"), ("app-store", "app-store-connect")]:
            options = release.export_options(channel, "ABCDEFGHIJ")
            self.assertEqual(options["method"], method)
            self.assertEqual(options["destination"], "export")
            self.assertFalse(options["manageAppVersionAndBuildNumber"])
            self.assertFalse(options["uploadSymbols"])
            self.assertNotIn("provisioningProfiles", options)
        with self.assertRaises(ValueError):
            release.export_options("direct", "")

    def test_archive_outputs_are_not_overwritten(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "saved.xcarchive"
            path.mkdir()
            with self.assertRaises(ValueError):
                release.unused(path)
            self.assertTrue(path.is_dir())

    def test_checksum_changes_after_artifact_changes(self):
        with tempfile.TemporaryDirectory() as folder:
            artifact = Path(folder) / "FocusDesk.dmg"
            artifact.write_bytes(b"before stapling")
            before = release.checksum(artifact).read_text()
            artifact.write_bytes(b"after stapling")
            after = release.checksum(artifact).read_text()
            self.assertNotEqual(before, after)
            self.assertEqual(after, hashlib.sha256(b"after stapling").hexdigest() + "  FocusDesk.dmg\n")

    def test_unsigned_validation_still_checks_architecture_and_resources(self):
        with tempfile.TemporaryDirectory() as folder:
            app = Path(folder) / "Focus Desk.app"
            resources = app / "Contents/Resources"
            resources.mkdir(parents=True)
            release.write_plist(app / "Contents/Info.plist", self.metadata())
            release.write_plist(resources / "PrivacyInfo.xcprivacy",
                                release.read_plist(release.ROOT / "Resources/PrivacyInfo.xcprivacy"))
            (resources / "AppIcon.icns").write_bytes(b"test-icon")
            with patch.object(release, "run", return_value=b"arm64\n"):
                release.verify(app, "unsigned")
            with patch.object(release, "run", return_value=b"x86_64 arm64\n"), self.assertRaises(ValueError):
                release.verify(app, "unsigned")
            (resources / "PrivacyInfo.xcprivacy").unlink()
            with patch.object(release, "run", return_value=b"arm64\n"), self.assertRaises(FileNotFoundError):
                release.verify(app, "unsigned")

    def test_privacy_manifest_matches_current_offline_product(self):
        manifest = release.read_plist(release.ROOT / "Resources/PrivacyInfo.xcprivacy")
        self.assertFalse(manifest["NSPrivacyTracking"])
        self.assertEqual(manifest["NSPrivacyCollectedDataTypes"], [])
        reasons = {api["NSPrivacyAccessedAPIType"]: api["NSPrivacyAccessedAPITypeReasons"]
                   for api in manifest["NSPrivacyAccessedAPITypes"]}
        self.assertEqual(reasons["NSPrivacyAccessedAPICategoryUserDefaults"], ["CA92.1"])
        self.assertEqual(reasons["NSPrivacyAccessedAPICategoryFileTimestamp"], ["C617.1", "3B52.1"])


if __name__ == "__main__":
    unittest.main()
