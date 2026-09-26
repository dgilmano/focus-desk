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
- WidgetKit source target that reads a shared current-task snapshot.
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

```sh
swift build
swift test
swift build -c release --arch arm64
swift run FocusDesk
```

The Swift package is intentionally dependency-free. The widget target is included as source-ready WidgetKit support; when embedded in an Xcode app-extension target, define `FOCUS_DESK_WIDGET_EXTENSION` to enable its `@main` widget bundle entry point.

Set `FOCUS_DESK_SERVER_TIME_URL` to an endpoint that returns an HTTP `Date` header to timestamp progress from server time. Without that endpoint, the app falls back to local time and remains fully offline.

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
