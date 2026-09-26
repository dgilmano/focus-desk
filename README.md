# Focus Desk

Focus Desk is a native SwiftUI macOS app for focusing on one long-running task at a time. It keeps the current task visible, tracks the next step, records what has been done, preserves per-task drafts locally, and keeps a lightweight journal of progress.

Supported release platform: **Apple Silicon, macOS 14 or later**. Intel builds are not supported. Distribution is planned for the Mac App Store and signed, notarized GitHub downloads.

## Highlights

- Native SwiftUI macOS application.
- SwiftData local persistence for tasks, progress entries, drafts, and completion state.
- Offline-first time architecture with a single replaceable server-time boundary.
- Keyboard-first workflow: previous, next, record-and-next, done, and dialog escape behavior.
- Task Manager window with Active and Completed tabs.
- Undoable completion toast with a five-second recovery window.
- WidgetKit source scaffold (not included in the distributed application yet).
- Dedicated Day map page under Focus with an adaptive activity palette: one-click switching, explicit pause, and editable names, colors, and icons. A compact palette is also available in the macOS menu bar.
- Day map includes calendar navigation, time totals, editable intervals, gap filling, splitting, and optional task links. Its selected date is shared with the Journal in Summary.
- Day map pairs a chronological activity journal with a native daily-balance ring and a color timeline. The layout stacks on narrow windows; category colors, archived history, and untracked gaps stay consistent across views.
- Sidebar navigation: Focus (Desk, Day map), Manage (New Task, Tasks, Completed, Summary), and Tags.

## Activity

Activity records local start/end timestamps independently of tasks and journal entries. Selecting the active category again is a no-op. Switching categories closes the previous interval and starts the next in one save. Category archival preserves historical intervals.

Sleep and normal application quit pause recording. While running, the application saves a checkpoint every 30 seconds. Following an unexpected exit, the unfinished interval is closed at that checkpoint; time while the app was unavailable is left untracked. Activity does not infer computer usage or pause when the mouse is idle. Day boundaries use the current local calendar, including daylight-saving transitions.

The existing tag chart remains an estimate from Journal entries; it is not combined with the measured Activity totals. Task links on activity intervals are optional and do not follow task navigation automatically.

Debug builds support `swift run FocusDesk --activity-preview` for visual checks using an in-memory store, without modifying the task database. Release builds ignore this option.

## Build

For a complete macOS application bundle, use Xcode 16 or newer on an Apple Silicon Mac:

```sh
python3 scripts/release.py local
```

The app is created at `dist/DerivedData/Build/Products/Debug/Focus Desk.app`. It is called **Focus Desk Dev** when running and uses a separate, sandboxed development workspace. No Apple Developer membership is required for this ad-hoc signed local build. It is not a public release.

`FocusDesk.xcodeproj` includes shared schemes for development, Developer ID distribution on GitHub, and Mac App Store distribution. All build **arm64 only** with macOS 14 as the minimum. Version and build number live in `Config/Version.xcconfig`.

The dependency-free Swift package remains the test and lightweight development entry point:

```sh
swift build
swift test
swift build -c release --arch arm64
swift run FocusDesk
```

These Swift package commands do not create a distributable app bundle and are not sandboxed. Use the Xcode build to test distribution behavior. Before moving real data from an old Swift package build to the new sandboxed app, export a backup and restore it in the new app. Nothing is automatically moved or deleted.

The widget scaffold is disabled in the app until a real extension, App Group and signing configuration are added. The extension entry point uses `FOCUS_DESK_WIDGET_EXTENSION`; the app writer separately uses `FOCUS_DESK_WIDGET_HOST`. Do not enable either in a release without updating entitlements and the privacy manifest.

Debug Swift package builds can use `FOCUS_DESK_SERVER_TIME_URL` with an HTTP `Date` endpoint. Release builds always use the local clock. The Xcode app has no network entitlement; cloud sign-in remains an unfinished UI, not working cloud sync.

Packaging, signing, notarization, Apple account setup, and release gates: [macOS release guide](docs/macos-release.md).

## Data Protection

Open **Focus Desk > Data & Backups...** in the macOS menu bar to export, restore, or create a local backup.

- Save failures are shown in the app. Bound text remains available for retry; failed Journal submissions retain the original draft and do not create duplicate entries. New Task and Task Manager editor forms only close or clear after a successful save.
- Tasks and Journal entries have undoable deletion. The last 20 deletions can be undone during the current session using the banner or **Focus Desk > Undo Last Deletion**. A successful recovery copy is required before deleting tasks, Journal entries, or Day map intervals.
- Automatic backups coalesce changes over up to 30 seconds and flush on a normal quit. The latest snapshot in each local hour is kept, retaining 48 hourly files. The last 20 pre-deletion, pre-restore, or manually created recovery copies are retained separately.
- Versioned JSON backups contain all tasks, completed state, Markdown, tags, drafts, Journal, activity categories (including archived ones), intervals, and task links. UI preferences and account settings are not included. Imports are limited to 64 MB and validated before changing the workspace.
- Restore replaces the workspace, saves a recovery copy first, and refreshes both data contexts. Imported active activity ends at its saved checkpoint; time away is not counted.
- Startup creates a consistent SQLite snapshot before opening/migrating a production database. It includes committed WAL data. The last five successful-start snapshots are retained; failed opens do not prune them. An unreadable database shows a recovery screen instead of being silently reset. Recovering a JSON backup creates a separate database and preserves the original files.
- Backups are stored under Application Support in `FocusDesk/Backups` (inside the app container for sandboxed distribution). They are **not encrypted** and remain on this Mac. Export copies to another protected location for device-loss protection. Local copies are not cloud sync.

Implementation and release checks: [Data protection](docs/data-protection.md).
