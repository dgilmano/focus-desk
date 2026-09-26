# macOS build and release

## Scope

Focus Desk supports **Apple Silicon and macOS 14+**. Intel is deliberately excluded. A successful local build or unsigned archive is not a signed public release and does not imply App Store approval.

The checked-in Xcode project builds the same source as the dependency-free Swift package. `FocusDeskCore` is statically linked; there are no external SDKs or frameworks to redistribute. Synchronized source folders require Xcode 16+. Tests run through Swift Package Manager.

| Scheme | Configuration | Bundle ID | Purpose |
| --- | --- | --- | --- |
| FocusDesk | Debug | com.dgilmano.focusdesk.dev | Isolated local development, ad-hoc signature |
| FocusDesk-Direct | ReleaseDirect | com.dgilmano.focusdesk | GitHub download, Developer ID signature |
| FocusDesk-AppStore | ReleaseAppStore | com.dgilmano.focusdesk | Mac App Store distribution |

Register the production bundle ID with the eventual Apple team before the first public release. Once users install the app, keep its bundle ID and signing team stable. Debug intentionally has its own data and preferences.

Both production configurations enable **App Sandbox** and **Hardened Runtime**. The only requested data access is read/write access to files explicitly selected by the user, for backup import/export. No full-disk access, outgoing network entitlement, unsigned-code exceptions or App Groups are enabled. Release builds cannot load the debug preview or environment-configured remote clock.

## Local build and checks

```sh
swift test --arch arm64
python3 -m unittest discover -s scripts/tests -v
python3 scripts/release.py local
python3 scripts/release.py archive --channel direct --unsigned
python3 scripts/release.py archive --channel app-store --unsigned
python3 scripts/release.py dmg --app "dist/DerivedData/Build/Products/Debug/Focus Desk.app" --local-only
```

The local app is ad-hoc signed, not Developer ID signed or notarized. Its DMG is explicitly named `-local-test-only.dmg`, contains an Applications shortcut and a local-only notice, and is **not for public distribution**. Do not tell users to disable Gatekeeper to run it.

Archives and installers are retained under `dist/`, which is ignored by Git. Existing archives/installers are never silently overwritten. Move an old artifact aside or increment the build before repeating its command. Do not run multiple Xcode builds against the same `dist/DerivedData` at once.

The validation workflow runs on a GitHub-hosted ARM64 Mac. It runs tests, builds the local app, checks both unsigned archives and creates/verifies a local DMG. It needs no signing credentials, does not upload artifacts, and cannot publish releases.

If Xcode fails before reading the project, finish its initial component installation. `xcodebuild -checkFirstLaunchStatus` checks this. Apple's documented repair is `xcodebuild -runFirstLaunch`; review any license or administrator prompt yourself. Never work around missing components by modifying Apple's frameworks.

## Apple account and signing

1. Enroll at [Apple Developer Program](https://developer.apple.com/programs/enroll/) using an Apple Account with two-factor authentication. Membership is USD 99 per year, or local pricing where available. Individual enrollment publishes your legal name as the seller; organization enrollment requires a legal entity and usually a D-U-N-S number. The account owner accepts the agreements and pays personally.
2. After activation, add the account in Xcode Settings > Accounts and select the paid team. Register `com.dgilmano.focusdesk` for the Mac application.
3. For GitHub, create a **Developer ID Application** certificate with its private key on your Mac. A Developer ID Installer certificate is not needed for a drag-to-Applications DMG.
4. For the Mac App Store, configure an **Apple Distribution** application certificate, a matching Mac App Store provisioning profile and a **Mac Installer Distribution** certificate for the installer exported by Xcode. Exact available certificate labels depend on the account and Xcode. Use the matching Mac distribution identities offered by Apple, not Developer ID.
5. Optionally copy `Config/Signing.example.xcconfig` to the ignored `Config/Signing.local.xcconfig`, then enter the team ID and App Store profile name. Do not commit private keys, passwords, `.p12` files or provisioning profiles. The packaging commands also accept `--team` explicitly.

Signing and App Store export cannot be verified without those certificates/profiles. A free Personal Team is not a replacement for Developer ID or App Store membership.

## GitHub distribution

Run these steps only after setting up signing and completing the release checklist. Replace the team, identity, paths and version with actual values.

```sh
python3 scripts/release.py archive --channel direct --team ABCDE12345
python3 scripts/release.py export --channel direct --team ABCDE12345 \
  --archive dist/archives/FocusDesk-0.1.0-1-direct.xcarchive
python3 scripts/release.py dmg \
  --app "dist/exports/FocusDesk-0.1.0-1-direct/Focus Desk.app" \
  --identity "Developer ID Application: Your Name (ABCDE12345)"
```

The DMG command refuses unsigned, ad-hoc, wrong-bundle or non-ARM64 apps and requires sandbox, hardened runtime and a timestamped Developer ID signature. It checks that the app and disk image use the same signing team. This is still not the end of distribution preparation.

Configure a `notarytool` Keychain profile interactively following Apple's documentation; never put its password in the repo or chat. Submit only a release artifact you intend to send to Apple:

```sh
xcrun notarytool submit dist/installers/FocusDesk-0.1.0-1-arm64.dmg \
  --keychain-profile FocusDesk-Notary --wait
```

Continue **only if the result is Accepted**. If it fails, inspect the submission log; do not weaken signing or instruct users to bypass system security.

```sh
xcrun stapler staple dist/installers/FocusDesk-0.1.0-1-arm64.dmg
xcrun stapler validate dist/installers/FocusDesk-0.1.0-1-arm64.dmg
spctl --assess --type open --context context:primary-signature --verbose=2 \
  dist/installers/FocusDesk-0.1.0-1-arm64.dmg
python3 scripts/release.py checksum dist/installers/FocusDesk-0.1.0-1-arm64.dmg
```

Recompute SHA-256 **after** stapling because it changes the file. Test a browser-downloaded DMG on another Mac/user account with normal Gatekeeper settings. Drag the application to Applications and launch it. Only then attach the final DMG and checksum to a GitHub release. Retain the matching `.xcarchive` and dSYM for crash reports; never commit them to source control. The current scripts do not publish releases or implement automatic application updates.

## Mac App Store

```sh
python3 scripts/release.py archive --channel app-store --team ABCDE12345
python3 scripts/release.py export --channel app-store --team ABCDE12345 \
  --profile "Focus Desk App Store" \
  --archive dist/archives/FocusDesk-0.1.0-1-app-store.xcarchive
```

Export is local, not an upload. Alternatively, open the signed archive in Xcode Organizer, validate it, and review the distribution settings there. Check the exported installer signature with `pkgutil --check-signature` before submitting through Apple's tools. App Store distribution uses App Review rather than a separate Developer ID notarization submission. Keep the same sandbox and production identifier as the direct channel, and explicitly test replacing one channel with the other after making a backup.

## Data transition

Old Swift package/developer builds are unsandboxed. The new signed application's container is a different location; an initially empty workspace does **not** mean old tasks were deleted.

1. In the old app, use Focus Desk > Data & Backups > Export Backup. Keep an additional copy somewhere protected.
2. Quit the old app. Launch the new app and choose Restore Backup using the exported JSON file.
3. Verify active/completed tasks, tags, Journal, drafts and Day map history. Keep the old database and export until satisfied.

Do not add automatic file copying or sandbox exceptions to conceal this transition. The development app uses `.dev` and never opens the production container automatically. Preferences/account UI settings are not included in data backups.

## Privacy and resources

`Resources/PrivacyInfo.xcprivacy` declares no tracking or data collection. Own-app preferences use UserDefaults reason `CA92.1`. Backup retention/store snapshots inspect file timestamps and metadata inside the app container (`C617.1`); selected backup imports inspect user-selected file metadata (`3B52.1`). Re-audit these reasons if adding SDKs, network services, App Groups, account sync or analytics. A privacy manifest is not a substitute for App Store privacy answers and a public privacy policy.

The WidgetKit target is a source scaffold, not a shipped extension. Host snapshot writing is disabled without `FOCUS_DESK_WIDGET_HOST`; the unconfigured App Group is not used by distributed builds. Implement and sign a real extension before enabling it.

`Resources/Assets.xcassets` includes original **provisional** application artwork, generated by `xcrun swift scripts/GenerateAppIcon.swift`. It is not final approved branding and uses no SF Symbols or third-party assets. Choose final artwork before public release.

## Release gates

- Choose the final bundle ID, Apple team and app icon before shipping to users.
- Increase `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `Config/Version.xcconfig` for each appropriate release/upload; do not reuse a published build number.
- Require a green validation workflow and archive from a clean, recorded Git commit. Keep the Xcode version with the release record.
- Verify real signatures, provisioning, notarization/Gatekeeper or App Store validation after membership activation. No credentials were available for the initial preparation.
- Run first-launch, upgrade, backup/restore, quit/relaunch and activity recovery checks on macOS 14 and the current supported macOS. Automated and local host checks do not replace that OS matrix.
- Test export/restore on a clean sandboxed install, and direct/App Store replacement using the same production signing team. Do not test on the only copy of real data.
- Remove or finish the Google sign-in placeholder before distributing to users. It currently does not provide authentication or cloud sync. Keep the initial public build clearly local-only until sync is real.
- Publish accurate privacy/support pages, App Store metadata and screenshots. Confirm open-source notices and the final icon's rights.
- Verify the final downloaded DMG after notarization and keep its checksum, archive and dSYM. Never distribute `-unsigned` archives or `-local-test-only` images as releases.

## Validation record

Initial local validation on 26 September 2026: Xcode 27.0, macOS 26.6.2, ARM64. All 44 Swift tests and 12 packaging tests passed. Both unsigned archives include the app and dSYM. The ad-hoc sandboxed application launched, restored a demonstration JSON backup, exported it through the native file picker, and retained the restored task/Journal after quit and relaunch. The DMG passed checksum verification, was mounted read-only, and its contained app passed signature/resource verification. These checks did not use the user's real workspace. Signed exports, notarization, App Store validation and macOS 14 runtime testing remain outstanding.

## Primary references

- [Apple: downloading and installing Xcode components](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components)
- [Apple: notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Apple: configuring App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)
- [Apple: required-reason API entries](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest)
- [GitHub: hosted runner architectures](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
