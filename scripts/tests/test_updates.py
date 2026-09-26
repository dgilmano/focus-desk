import base64
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
from unittest.mock import patch

from scripts import release, updates


class UpdateTests(unittest.TestCase):
    def metadata(self):
        return {"SUFeedURL": updates.FEED_URL,
                "SUPublicEDKey": base64.b64encode(bytes(32)).decode(),
                "SUVerifyUpdateBeforeExtraction": True, "SURequireSignedFeed": True,
                "SUEnableInstallerLauncherService": True, "SUSignedFeedFailureExpirationInterval": 0,
                "SUEnableAutomaticChecks": False, "SUAllowsAutomaticUpdates": False,
                "SUAutomaticallyUpdate": False, "SUSendProfileInfo": False}

    def test_secure_manual_configuration_is_required(self):
        release.validate_update_metadata(self.metadata())
        for key, value in self.metadata().items():
            with self.subTest(key=key), self.assertRaises((ValueError, TypeError)):
                settings = self.metadata()
                settings.pop(key)
                release.validate_update_metadata(settings)
            if isinstance(value, bool):
                with self.subTest(key=key), self.assertRaises(ValueError):
                    release.validate_update_metadata({**self.metadata(), key: not value})

    def test_local_feed_and_transport_exceptions_never_ship(self):
        for url in ["http://127.0.0.1/feed", "http://example.com/feed", "file:///tmp/feed",
                    "https://user:password@example.com/feed", "https://example.com/feed#fragment"]:
            with self.subTest(url=url), self.assertRaises(ValueError):
                release.validate_update_metadata({**self.metadata(), "SUFeedURL": url})
        release.validate_update_metadata({**self.metadata(), "SUFeedURL": "http://127.0.0.1:8765/feed"}, allow_local=True)
        with self.assertRaises(ValueError):
            release.validate_update_metadata({**self.metadata(), "NSAppTransportSecurity": {}})

    def test_feed_must_match_archive_version_size_and_destination(self):
        with tempfile.TemporaryDirectory() as folder:
            folder = Path(folder)
            archive = folder / "app.zip"
            archive.write_bytes(b"signed-test-archive")
            feed = folder / "appcast.xml"
            rss = ET.Element("rss")
            item = ET.SubElement(ET.SubElement(rss, "channel"), "item")
            ns = "{" + updates.NS["sparkle"] + "}"
            ET.SubElement(item, ns + "version").text = "2"
            ET.SubElement(item, ns + "shortVersionString").text = "0.2.0"
            enclosure = ET.SubElement(item, "enclosure", {
                "url": f"https://github.com/{updates.REPOSITORY}/releases/download/personal-v0.2.0-2/app.zip",
                "length": str(archive.stat().st_size), ns + "edSignature": "test-signature"})
            ET.ElementTree(rss).write(feed)
            self.assertEqual(updates.validate_feed(feed, archive, "0.2.0", "2"), "test-signature")
            with self.assertRaises(ValueError):
                updates.validate_feed(feed, archive, "0.2.0", "3")
            for key, value in [("url", "http://127.0.0.1/app.zip"), ("length", "0"), (ns + "edSignature", "")]:
                original = enclosure.get(key)
                enclosure.set(key, value)
                ET.ElementTree(rss).write(feed)
                with self.assertRaises(ValueError):
                    updates.validate_feed(feed, archive, "0.2.0", "2")
                enclosure.set(key, original)
            ET.ElementTree(rss).write(feed)
            with patch.object(updates, "FEED", feed):
                updates.require_new_build("3")
                for build in ["1", "2"]:
                    with self.assertRaises(ValueError):
                        updates.require_new_build(build)

    def test_release_tag_cannot_contain_arbitrary_paths(self):
        self.assertEqual(updates.tag_for("0.2.0", "2"), "personal-v0.2.0-2")
        for version, build in [("../test", "2"), ("0.2.0", "../test")]:
            with self.assertRaises(ValueError):
                updates.tag_for(version, build)

    def test_prepare_and_publish_refuse_dirty_sources(self):
        with patch.object(release, "run", return_value=b" M Sources/App.swift\n"), self.assertRaises(ValueError):
            updates.clean_commit()


if __name__ == "__main__":
    unittest.main()
