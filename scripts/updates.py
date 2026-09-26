#!/usr/bin/env python3
"""Prepare locally signed personal updates; publish only with an explicit command."""

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

from scripts import release

REPOSITORY = "dgilmano/focus-desk"
FEED = release.ROOT / "updates/personal/appcast.xml"
FEED_URL = f"https://raw.githubusercontent.com/{REPOSITORY}/main/updates/personal/appcast.xml"
ACCOUNT = "com.dgilmano.focusdesk.updates"
SPARKLE = "2.10.0"
TOOLS = release.ROOT / f".build/Sparkle-{SPARKLE}"
TOOLS_SHA256 = "c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"
NS = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}


def digest(path):
    with Path(path).open("rb") as file:
        result = hashlib.sha256()
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            result.update(chunk)
        return result.hexdigest()


def tools():
    archive = TOOLS.parent / f"Sparkle-{SPARKLE}.tar.xz"
    # The exact official release is pinned independently of SwiftPM's binary checksum.
    if not archive.exists():
        archive.parent.mkdir(parents=True, exist_ok=True)
        url = f"https://github.com/sparkle-project/Sparkle/releases/download/{SPARKLE}/Sparkle-{SPARKLE}.tar.xz"
        with urllib.request.urlopen(url, timeout=120) as response, archive.open("xb") as output:
            shutil.copyfileobj(response, output)
    release.require(digest(archive) == TOOLS_SHA256, "Sparkle tools checksum mismatch; refusing to execute.")
    if not (TOOLS / "bin/generate_appcast").exists():
        TOOLS.mkdir(exist_ok=True)
        release.run("tar", "-xf", archive, "-C", TOOLS)
    return TOOLS / "bin"


def clean_commit():
    status = release.run("git", "status", "--porcelain", capture=True).decode().strip()
    release.require(not status, "Commit source changes before preparing or publishing an update.")
    return release.run("git", "rev-parse", "HEAD", capture=True).decode().strip()


def tag_for(version, build):
    release.validate_versions(version, build)
    return f"personal-v{version}-{build}"


def feed_item(path):
    release.require(path.stat().st_size < 1024 * 1024, "Unexpectedly large update feed.")
    items = ET.parse(path).getroot().findall("./channel/item")
    release.require(len(items) == 1, "Personal feed must contain exactly one current release.")
    return items[0]


def validate_feed(path, archive, version, build):
    item = feed_item(path)
    release.require(item.findtext("sparkle:version", namespaces=NS) == build, "Feed build mismatch.")
    release.require(item.findtext("sparkle:shortVersionString", namespaces=NS) == version, "Feed version mismatch.")
    enclosure = item.find("enclosure")
    release.require(enclosure is not None, "Missing update archive.")
    expected = f"https://github.com/{REPOSITORY}/releases/download/{tag_for(version, build)}/{archive.name}"
    release.require(enclosure.get("url") == expected, "Unexpected update download URL.")
    release.require(enclosure.get("length") == str(archive.stat().st_size), "Update size mismatch.")
    signature = enclosure.get("{" + NS["sparkle"] + "}edSignature", "")
    release.require(bool(signature), "Missing archive signature.")
    return signature


def require_new_build(build):
    if FEED.exists():
        previous = feed_item(FEED).findtext("sparkle:version", namespaces=NS)
        release.require(previous and int(build) > int(previous), "Increase the build number; never republish or downgrade.")


def prepare(args):
    commit = clean_commit()
    version, build = release.versions()
    require_new_build(build)
    notes = Path(args.notes).resolve()
    release.require(notes.is_file() and notes.stat().st_size < 128 * 1024, "Supply a small release notes file.")
    bin_dir = tools()
    release.personal(None)
    app = release.DIST / "DerivedData/Build/Products/ReleasePersonal/Focus Desk.app"
    info = release.verify(app, "personal")
    release.require(info["SUFeedURL"] == FEED_URL, "Not the personal production feed.")
    public_key = release.run(bin_dir / "generate_keys", "--account", ACCOUNT, "-p", capture=True).decode().strip()
    release.require(public_key == info["SUPublicEDKey"], "Keychain signing key does not match the application's public key.")
    folder = release.unused(release.DIST / "updates" / tag_for(version, build))
    folder.mkdir()
    archive = folder / f"FocusDesk-{version}-{build}-arm64-personal.zip"
    release.run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, archive)
    shutil.copy2(notes, archive.with_suffix(".md"))
    release.run(bin_dir / "generate_appcast", "--account", ACCOUNT, "--maximum-deltas", "0",
                "--maximum-versions", "1", "--embed-release-notes", "--download-url-prefix",
                f"https://github.com/{REPOSITORY}/releases/download/{tag_for(version, build)}/", folder)
    feed = folder / "appcast.xml"
    signature = validate_feed(feed, archive, version, build)
    release.run(bin_dir / "sign_update", "--account", ACCOUNT, "--verify", archive, signature)
    release.run(bin_dir / "sign_update", "--account", ACCOUNT, "--verify", feed)
    release.require(clean_commit() == commit, "Source changed during preparation.")
    receipt = {"version": version, "build": build, "commit": commit, "archive": archive.name,
               "archiveSHA256": digest(archive), "feedSHA256": digest(feed),
               "xcode": release.run("xcodebuild", "-version", capture=True).decode().strip()}
    (folder / "release.json").write_text(json.dumps(receipt, indent=2) + "\n")
    release.checksum(archive)
    print(f"Prepared, not published: {folder}")


def publish(args):
    folder = Path(args.folder).resolve()
    receipt = json.loads((folder / "release.json").read_text())
    release.require(clean_commit() == receipt["commit"], "Publish from the exact prepared source commit.")
    version, build = receipt["version"], receipt["build"]
    tag = tag_for(version, build)
    require_new_build(build)
    name = receipt["archive"]
    release.require(Path(name).name == name and name.endswith(".zip"), "Invalid archive filename.")
    archive, feed = folder / name, folder / "appcast.xml"
    release.require(digest(archive) == receipt["archiveSHA256"] and digest(feed) == receipt["feedSHA256"],
                    "Prepared artifacts changed; refusing publication.")
    signature = validate_feed(feed, archive, version, build)
    bin_dir = tools()
    release.run(bin_dir / "sign_update", "--account", ACCOUNT, "--verify", archive, signature)
    release.run(bin_dir / "sign_update", "--account", ACCOUNT, "--verify", feed)
    gh = shutil.which("gh")
    release.require(gh, "Install GitHub CLI and authenticate to publish.")
    # Keep the release private as a draft until every artifact has uploaded successfully.
    release.run(gh, "release", "create", tag, "--repo", REPOSITORY, "--draft", "--prerelease",
                "--target", receipt["commit"], "--title", f"Focus Desk {version} ({build}) - Personal",
                "--notes-file", archive.with_suffix(".md"))
    release.run(gh, "release", "upload", tag, archive, release.checksum(archive), folder / "release.json",
                "--repo", REPOSITORY)
    release.run(gh, "release", "edit", tag, "--repo", REPOSITORY, "--draft=false", "--latest=false")
    # Only point clients to the release after it is public. Commit this exact signed file last.
    FEED.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(feed, FEED)
    print(f"Published https://github.com/{REPOSITORY}/releases/tag/{tag}")
    print("Commit and push updates/personal/appcast.xml to activate this release. Do not edit the signed XML.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    preparation = commands.add_parser("prepare")
    preparation.add_argument("--notes", required=True)
    preparation.set_defaults(action=prepare)
    publication = commands.add_parser("publish")
    publication.add_argument("folder")
    publication.set_defaults(action=publish)
    args = parser.parse_args()
    try:
        args.action(args)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"Update preparation stopped: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
