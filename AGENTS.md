# Focus Desk

## Project
- Native macOS app: Swift 6, SwiftUI/AppKit, SwiftData. Apple Silicon only, macOS 14+; no Intel support.
- Prioritize reliable personal use and signed GitHub updates now. Keep changes compatible with future notarized distribution and the Mac App Store; Store submission is the final milestone.
- Use Focus Desk naming for our own UI and components, not legacy Carousel or borrowed product branding.
- `Sources/FocusDeskCore` holds shared domain logic; `Sources/FocusDeskApp` holds UI, persistence and app integration. Extend existing boundaries and native patterns.

## Working Style
- Reply in Russian. Keep reports brief: changes, verification, remaining limitations.
- Scope work to the request. Read relevant files and docs, not the entire repository or conversation history.
- Preserve the established Desk/Day map visual language. Reuse shared styles; check resizing, light/dark appearance and interaction states for UI changes.
- Keep this file short and stable. Put feature details in focused docs, linked only where needed.

## Data Safety
- Never use the owner's working database for tests, reset unreadable stores, or silently move data between development and production workspaces.
- Preserve tasks, Journal, Markdown, tags, drafts and activity history. Persistence/migration changes must retain backup/recovery safeguards and test failure paths.
- Day map measures recorded intervals; Journal/tag analytics are estimates. Do not conflate them. Cloud sign-in is a placeholder, not working synchronization.

## Verification
Use checks appropriate to the changed surface; expand coverage for persistence, shared behavior and releases.
- App/domain tests: `swift test --arch arm64` (use `--filter` for focused iterations).
- Packaging/updater tests: `python3 -m unittest discover -s scripts/tests -v`.
- Sandboxed development app: `python3 scripts/release.py local`.
- Swift package runs are unsandboxed and are not distribution validation. Use an isolated development/test workspace for UI checks.

## Distribution
- Separate feature changes from publishing: do not package and publish a release for every small edit.
- Personal updates use Sparkle with signed feeds/archives. Keep sandboxing, signature checks and save/backup-before-update protections intact; keep Sparkle out of the App Store target.
- Never commit credentials/private keys, rotate the update key without an explicit plan, hand-edit signed feeds, or reuse a published build number. Ad-hoc signing is not Apple notarization.

## Read When Relevant
- Build entry points and product behavior: `README.md`.
- Persistence, deletion, import/export or migration: `docs/data-protection.md`.
- Personal installation and GitHub updates: `docs/personal-updates.md`.
- Signing, packaging and App Store readiness: `docs/macos-release.md`.
