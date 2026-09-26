#!/usr/bin/env python3
"""Build and package Focus Desk. Nothing is uploaded or published by this tool."""

import argparse
import hashlib
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / "dist"
BUNDLE_ID = "com.dgilmano.focusdesk"
CHANNELS = {"direct": ("FocusDesk-Direct", "ReleaseDirect"),
            "app-store": ("FocusDesk-AppStore", "ReleaseAppStore")}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def run(*args, capture=False):
    args = [str(arg) for arg in args]
    print("+", " ".join(args), flush=True)
    return subprocess.run(args, cwd=ROOT, check=True,
                          stdout=subprocess.PIPE if capture else None).stdout


def read_plist(path):
    with Path(path).open("rb") as file:
        return plistlib.load(file)


def write_plist(path, value):
    with Path(path).open("wb") as file:
        plistlib.dump(value, file)


def versions():
    values = {}
    for line in (ROOT / "Config/Version.xcconfig").read_text().splitlines():
        key, separator, value = line.partition("=")
        if separator:
            values[key.strip()] = value.strip()
    version, build = values["MARKETING_VERSION"], values["CURRENT_PROJECT_VERSION"]
    validate_versions(version, build)
    return version, build


def validate_versions(version, build):
    require(re.fullmatch(r"\d+\.\d+\.\d+", version), "Version must be three numbers, e.g. 0.1.0.")
    require(re.fullmatch(r"[1-9]\d*", build), "Build number must be a positive integer.")


def validate_team(team):
    require(team and re.fullmatch(r"[A-Z0-9]{10}", team), "Supply a 10-character Apple team ID with --team.")


def validate_metadata(info, mode):
    expected = BUNDLE_ID + ".dev" if mode == "local" else BUNDLE_ID
    require(info.get("CFBundleIdentifier") == expected, "Unexpected bundle identifier; refusing this artifact.")
    require(info.get("CFBundlePackageType") == "APPL", "Not a macOS application bundle.")
    require(info.get("CFBundleExecutable") == "FocusDesk", "Unexpected application executable.")
    require(info.get("LSMinimumSystemVersion") == "14.0", "Unexpected minimum macOS version.")
    require(info.get("LSRequiresNativeExecution") is True, "Native execution must be required.")
    require(info.get("CFBundleIconFile"), "App icon is missing from Info.plist.")
    validate_versions(info.get("CFBundleShortVersionString", ""), info.get("CFBundleVersion", ""))


def validate_entitlements(entitlements, mode):
    require(entitlements.get("com.apple.security.app-sandbox") is True, "App Sandbox is required.")
    require(entitlements.get("com.apple.security.files.user-selected.read-write") is True,
            "User-selected file access is required for backup import/export.")
    allowed = {"com.apple.security.app-sandbox", "com.apple.security.files.user-selected.read-write",
               "com.apple.application-identifier", "com.apple.developer.team-identifier"}
    if mode == "local":
        allowed.add("com.apple.security.get-task-allow")
    require(not (set(entitlements) - allowed), "Unexpected entitlements; review before distribution.")


def signature_details(app):
    result = subprocess.run(["codesign", "--display", "--verbose=4", str(app)],
                            capture_output=True, check=True)
    return result.stderr.decode()


def validate_signature(details, mode):
    if mode == "local":
        require("Signature=adhoc" in details, "Local builds must use an ad-hoc signature.")
        return
    authorities = ("Authority=Developer ID Application:",) if mode == "direct" else (
        "Authority=Apple Distribution:", "Authority=3rd Party Mac Developer Application:")
    require(any(item in details for item in authorities), "Wrong distribution certificate (or unsigned app).")
    require("(runtime)" in details, "Hardened Runtime is required.")
    if mode == "direct":
        require("Timestamp=" in details, "Developer ID signature needs a secure timestamp.")


def verify(app, mode):
    app = Path(app).resolve()
    info = read_plist(app / "Contents/Info.plist")
    validate_metadata(info, mode)
    architectures = run("xcrun", "lipo", "-archs", app / "Contents/MacOS/FocusDesk", capture=True).decode().split()
    require(architectures == ["arm64"], "Only arm64 is supported; no Intel slices may be shipped.")
    privacy = read_plist(app / "Contents/Resources/PrivacyInfo.xcprivacy")
    require(privacy == read_plist(ROOT / "Resources/PrivacyInfo.xcprivacy"), "Privacy manifest is missing or stale.")
    icon = info["CFBundleIconFile"]
    icon_path = app / "Contents/Resources" / icon
    require(icon_path.is_file() or icon_path.with_suffix(".icns").is_file(), "Compiled icon is missing.")
    require(not (app / "Contents/PlugIns").exists(), "Unreviewed embedded extensions found.")
    if mode != "unsigned":
        run("codesign", "--verify", "--deep", "--strict", app)
        entitlements = plistlib.loads(run("codesign", "--display", "--entitlements", "-", "--xml", app, capture=True))
        validate_entitlements(entitlements, mode)
        validate_signature(signature_details(app), mode)
    print(f"Verified {mode}: {app}")
    return info


def xcode_args(scheme):
    return ["xcodebuild", "-project", ROOT / "FocusDesk.xcodeproj", "-scheme", scheme,
            "-destination", "generic/platform=macOS", "-derivedDataPath", DIST / "DerivedData", "-quiet"]


def unused(path):
    require(not path.exists(), f"Output already exists: {path}. Keep it or move it before retrying.")
    path.parent.mkdir(parents=True, exist_ok=True)
    return path


def local(_args):
    run(*xcode_args("FocusDesk"), "-configuration", "Debug", "CODE_SIGN_IDENTITY=-",
        "CODE_SIGN_STYLE=Manual", "DEVELOPMENT_TEAM=", "PROVISIONING_PROFILE_SPECIFIER=", "build")
    app = DIST / "DerivedData/Build/Products/Debug/Focus Desk.app"
    verify(app, "local")
    print("Local testing only. Separate .dev workspace; not a public release.")


def archive(args):
    scheme, configuration = CHANNELS[args.channel]
    version, build = versions()
    suffix = "-unsigned" if args.unsigned else ""
    path = unused(DIST / "archives" / f"FocusDesk-{version}-{build}-{args.channel}{suffix}.xcarchive")
    signing = ["CODE_SIGNING_ALLOWED=NO"]
    if not args.unsigned:
        validate_team(args.team)
        signing = [f"DEVELOPMENT_TEAM={args.team}"]
    run(*xcode_args(scheme), "-configuration", configuration, "-archivePath", path, *signing, "archive")
    app = path / "Products/Applications/Focus Desk.app"
    verify(app, "unsigned" if args.unsigned else args.channel)
    require((path / "dSYMs/Focus Desk.app.dSYM").is_dir(), "Archive is missing crash-debugging symbols.")
    print(f"Archive: {path}")
    if args.unsigned:
        print("UNSIGNED validation artifact. Do not install or distribute this archive.")


def export_options(channel, team):
    validate_team(team)
    return {"method": "developer-id" if channel == "direct" else "app-store-connect",
            "destination": "export", "teamID": team, "signingStyle": "manual",
            "manageAppVersionAndBuildNumber": False, "uploadSymbols": False}


def export(args):
    path = Path(args.archive).resolve()
    require(path.suffix == ".xcarchive", "Expected an .xcarchive directory.")
    # Refuse unsigned archives rather than accidentally exporting a test build.
    verify(path / "Products/Applications/Focus Desk.app", args.channel)
    options = export_options(args.channel, args.team)
    if args.profile:
        options["provisioningProfiles"] = {BUNDLE_ID: args.profile}
    output = unused(DIST / "exports" / path.stem)
    with tempfile.TemporaryDirectory(prefix="focusdesk-export-") as folder:
        options_file = Path(folder) / "ExportOptions.plist"
        write_plist(options_file, options)
        run("xcodebuild", "-exportArchive", "-archivePath", path, "-exportPath", output,
            "-exportOptionsPlist", options_file)
    if args.channel == "direct":
        verify(output / "Focus Desk.app", "direct")
    print(f"Exported locally (not uploaded): {output}")


def checksum(path):
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    result = path.with_suffix(path.suffix + ".sha256")
    result.write_text(f"{digest.hexdigest()}  {path.name}\n")
    return result


def dmg(args):
    mode = "local" if args.local_only else "direct"
    app = Path(args.app).resolve()
    info = verify(app, mode)
    if not args.local_only:
        require(args.identity and args.identity.startswith("Developer ID Application:"),
                "Supply --identity 'Developer ID Application: Name (TEAMID)' for the disk image.")
    version, build = info["CFBundleShortVersionString"], info["CFBundleVersion"]
    suffix = "-local-test-only" if args.local_only else ""
    output = unused(DIST / "installers" / f"FocusDesk-{version}-{build}-arm64{suffix}.dmg")
    with tempfile.TemporaryDirectory(prefix="focusdesk-dmg-") as folder:
        stage = Path(folder) / "image"
        stage.mkdir()
        run("ditto", app, stage / app.name)
        (stage / "Applications").symlink_to("/Applications")
        shutil.copyfile(ROOT / "LICENSE", stage / "LICENSE.txt")
        if args.local_only:
            (stage / "LOCAL-TEST-ONLY.txt").write_text(
                "Focus Desk local test build. Not notarized, not a public release.\n"
                "Uses a separate development workspace; does not open your production tasks.\n")
        run("hdiutil", "create", "-volname", "Focus Desk Test" if args.local_only else "Focus Desk",
            "-srcfolder", stage, "-format", "UDZO", "-fs", "HFS+", output)
    if not args.local_only:
        run("codesign", "--sign", args.identity, "--timestamp", output)
        run("codesign", "--verify", "--strict", output)
        app_team = re.search(r"^TeamIdentifier=(.+)$", signature_details(app), re.MULTILINE)
        image_team = re.search(r"^TeamIdentifier=(.+)$", signature_details(output), re.MULTILINE)
        require(app_team and image_team and app_team[1] == image_team[1], "App and image must have the same signing team.")
    checksum(output)
    print(f"Disk image: {output}")
    print("Local test only." if args.local_only else "Not ready to publish: notarize, staple, then re-create the checksum.")


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    commands = result.add_subparsers(dest="command", required=True)
    commands.add_parser("local", help="Build an isolated, ad-hoc signed developer app").set_defaults(action=local)
    item = commands.add_parser("archive", help="Create an ARM64 distribution archive")
    item.add_argument("--channel", choices=CHANNELS, required=True)
    item.add_argument("--unsigned", action="store_true", help="Structural validation only; not installable")
    item.add_argument("--team")
    item.set_defaults(action=archive)
    item = commands.add_parser("export", help="Export a signed archive locally; never upload")
    item.add_argument("--archive", required=True)
    item.add_argument("--channel", choices=CHANNELS, required=True)
    item.add_argument("--team", required=True)
    item.add_argument("--profile", help="App Store provisioning profile name or UUID")
    item.set_defaults(action=export)
    item = commands.add_parser("dmg", help="Package an app with an Applications shortcut")
    item.add_argument("--app", required=True)
    item.add_argument("--local-only", action="store_true")
    item.add_argument("--identity")
    item.set_defaults(action=dmg)
    item = commands.add_parser("verify", help="Check architecture, metadata, resources and signatures")
    item.add_argument("--app", required=True)
    item.add_argument("--mode", choices=["local", "unsigned", *CHANNELS], required=True)
    item.set_defaults(action=lambda args: verify(args.app, args.mode))
    item = commands.add_parser("checksum", help="Refresh SHA-256 after stapling the final DMG")
    item.add_argument("artifact")
    item.set_defaults(action=lambda args: print(checksum(Path(args.artifact).resolve())))
    return result


if __name__ == "__main__":
    try:
        arguments = parser().parse_args()
        arguments.action(arguments)
    except (ValueError, OSError, subprocess.CalledProcessError, plistlib.InvalidFileException) as error:
        print(f"Release preparation failed: {error}", file=sys.stderr)
        sys.exit(1)
