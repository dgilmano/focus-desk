# Personal updates

## Current scope

Focus Desk is being prepared for daily use by its owner first. Mac App Store submission is deferred. The personal channel uses the production bundle ID, App Sandbox and Sparkle 2.10.0. It is Apple Silicon only, macOS 14+.

The app is **ad-hoc signed, not Developer ID signed or notarized**. Ed25519 signatures authenticate updates but do not replace Apple's distribution certificates. Do not distribute this as a general public release or tell people to disable Gatekeeper. Build the initial installation locally; future updates arrive as GitHub prerelease archives.

## Use

1. Export a backup from the previous development app before transitioning. The production sandbox is separate; do not delete the old database.
2. Build `python3 scripts/release.py personal`, then install `dist/DerivedData/Build/Products/ReleasePersonal/Focus Desk.app` in Applications. Do not overwrite a running copy. Restore the exported backup through Data & Backups when moving from an unsandboxed or `.dev` build.
3. Use **Focus Desk > Check for Updates...** in the macOS menu bar. If a newer published build exists, Sparkle shows its release notes and offers download, installation and relaunch.

Checking and installation are user-initiated. The app does not silently replace itself while you work. A successful save, activity pause and recovery backup are required at update-related termination. Failed saving/backup creation keeps the app open. Task data, Journal and Day map remain in the same sandbox across updates.

Both the feed and archive must pass Ed25519 verification; there is no unsigned-feed fallback. The feed is fixed in the app's signed bundle, not editable through preferences. Release builds require HTTPS. `FOCUS_DESK_UPDATE_TESTING` permits only loopback HTTP for isolated local testing and must never be distributed.

## Publishing the next update

Prerequisites: Xcode, Python 3, GitHub CLI with write access to `dgilmano/focus-desk`, and the original Sparkle key in this Mac's login Keychain under account `com.dgilmano.focusdesk.updates`. The private key is never read into repository files or uploaded to GitHub. Keep a secure recovery plan for this key; losing it may require a manual reinstall. Do not regenerate it for each version. A system prompt requesting access to this key must be reviewed by the owner.

1. Finish the feature, run tests, update `Config/Version.xcconfig` and write release notes. Every published `CURRENT_PROJECT_VERSION` must strictly increase. Never reuse published version/build artifacts.
2. Commit and push source changes. Require green macOS validation and test the new UI on a separate workspace. Publishing only runs from the exact clean source commit used for preparation.
3. Prepare the update locally:

```sh
swift test --arch arm64
python3 -m unittest discover -s scripts/tests -v
python3 -m scripts.updates prepare --notes updates/notes/0.2.0.md
```

This builds/verifies the app, checks that the Keychain public key matches the embedded key, creates a ZIP, signs the feed/archive using Sparkle's pinned tools, verifies both signatures, and records the commit, Xcode version and hashes in `dist/updates/personal-vVERSION-BUILD/release.json`. Existing output folders are not overwritten. The tooling download is independently SHA-256 pinned.

4. Publish the prepared folder explicitly (substitute the current version/build):

```sh
python3 -m scripts.updates publish dist/updates/personal-v0.2.0-2
```

The publisher first creates a draft GitHub prerelease, uploads the ZIP, checksum and build receipt, then publishes it. It never overwrites an existing release/tag. A failed upload leaves a draft; inspect it and complete/recover it deliberately instead of blindly republishing. The publisher does not change Git authentication or store credentials.

5. Only after successful publication, the publisher copies the signed feed into `updates/personal/appcast.xml`. Commit and push this exact file to main to activate the update. Do not hand-edit signed XML. The embedded release notes are also covered by its signature.
6. Fetch the public feed and verify its signature. Test Check for Updates from the installed previous version, then confirm the new version, task data and recovery backup after relaunch. Keep the artifacts, matching dSYM and release receipt locally.

Changes to source alone do not produce an update. A reviewed, versioned release must be published. CI validates builds but has neither the private key nor permission to publish.

## Channels and privacy

- Personal: `updates/personal/appcast.xml`, ad-hoc application, signed feed/ZIP, GitHub prereleases.
- Developer ID: separate future stable feed and Apple signing/notarization. The personal publisher refuses this channel. Test signing and sandbox-container transition before switching.
- App Store: separate target without Sparkle or external update permissions; updates through the App Store only.

Requests go to GitHub's raw-content and release-download services. GitHub receives normal connection metadata such as IP address and the updater's HTTP user agent. No task text, Journal, tags, activity history or backups are sent. Sparkle system-profile submission and background downloads/checks are disabled. Cloud sign-in remains an unrelated placeholder, not working sync.

## Verification

Implementation checkpoint, 26 September 2026: 49 Swift tests and 18 packaging/update tests pass locally. The personal application and both unsigned distribution archives build; the App Store archive contains no Sparkle. The first personal feed/release is **not published yet**. Signing the test feed and exercising installation/relaunch are pending because this Mac was locked. Do not treat the update channel as activated until those checks and first publication are completed. No working task database was used for these tests.

Unit tests cover mandatory signatures, HTTPS/loopback separation, scoped updater permissions, build monotonicity, feed/archive metadata consistency, data saving and refusal to install without a recovery copy. The App Store archive is checked for absence of Sparkle even when unsigned.

For an end-to-end smoke test, build two personal configurations using bundle ID `com.dgilmano.focusdesk.update-test`, distribution `update-test`, both `FOCUS_DESK_UPDATES` and `FOCUS_DESK_UPDATE_TESTING` compile/Info.plist definitions, and a `http://127.0.0.1:PORT/appcast.xml` feed. Install the older build in a test directory, sign the newer ZIP/feed, serve it only on loopback, create demonstration data, and exercise Check for Updates. Never point test builds at production data or publish the test archives.

Primary documentation: [Sparkle setup](https://sparkle-project.org/documentation/), [sandboxing](https://sparkle-project.org/documentation/sandboxing/), [publishing](https://sparkle-project.org/documentation/publishing/).
