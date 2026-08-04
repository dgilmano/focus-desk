# Focus Desk

Focus Desk is a native SwiftUI macOS app for focusing on one long-running task at a time. It keeps the current task visible, tracks the next step, records what has been done, preserves per-task drafts locally, and keeps a lightweight journal of progress.

## Highlights

- Native SwiftUI macOS application.
- SwiftData local persistence for tasks, progress entries, drafts, and completion state.
- Offline-first time architecture with a single replaceable server-time boundary.
- Keyboard-first workflow: previous, next, record-and-next, done, and dialog escape behavior.
- Task Manager window with Active and Completed tabs.
- Undoable completion toast with a five-second recovery window.
- WidgetKit source target that reads a shared current-task snapshot.

## Build

```sh
swift build
swift test
swift run FocusDesk
```

The Swift package is intentionally dependency-free. The widget target is included as source-ready WidgetKit support; when embedded in an Xcode app-extension target, define `FOCUS_CAROUSEL_WIDGET_EXTENSION` to enable its `@main` widget bundle entry point.

Set `FOCUS_CAROUSEL_SERVER_TIME_URL` to an endpoint that returns an HTTP `Date` header to timestamp progress from server time. Without that endpoint, the app falls back to local time and remains fully offline.
