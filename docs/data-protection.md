# Data protection

## Ownership

`TaskStore` is the main-actor boundary for task creation, completion, Journal submission, deletion, undo, and saving bound edits. Its main context has autosave disabled so success and failure are explicit. It saves pending edits before a destructive operation; failures roll back only the new operation. Relationship inserts are detached before rollback, and live values are restored for models retained by SwiftUI.

`ActivityStore` keeps a separate context. Successful commits and checkpoints schedule backups. `WorkspaceSession` coordinates restoration and refreshes the activity context and all workspace windows afterward. Do not add view-level `try? save()` calls or introduce another unsupervised writer.

`BackupStore` reads committed records through a fresh context, not a cached view query. Export additionally includes pending task text from the main context, allowing text rescue when database writes fail. Local automatic writes use atomic replacement and restrictive file permissions. The exported JSON format is versioned independently of the database schema.

## Schema changes

The existing two-model task database is represented by schema 1; the current four-model database is schema 2. Both previously unversioned databases are tested against the migration plan. Entity names, relationship identity, and the legacy sort-order attribute mapping are preserved.

Before the next structural model change, freeze the existing schema's model definitions and introduce a new version and migration stage. Do not modify historical schema definitions in place. Include a disk-based fixture migration test that checks every stored field and relationship, not just record counts.

SQLite startup snapshots use the public SQLite online-backup API. Copying just the `.store` file from an open WAL database is not an acceptable backup. The JSON format is the user-facing recovery path; raw `.store` snapshots are a support fallback and must not be copied over a running database.

## Restore contract

1. Decode and validate the entire backup before mutation. Reject unsupported versions, duplicate IDs, dangling Journal/category relationships, invalid intervals, and overlaps. Historical task references on activity may intentionally point to a deleted task.
2. Require explicit confirmation of replacement and show record counts.
3. Save pending task changes and write a recovery copy. Abort if either fails.
4. Upsert matching IDs, remove missing records, and save all changes once. Restore cached values and roll back if the save fails.
5. Refresh activity state, recreate workspace view state, clear obsolete undo history, and checkpoint automatic backup state. Restored running intervals are closed at their saved checkpoint.

If startup cannot open the database, JSON recovery writes a new `recovered-<UUID>.store`. An atomically written `active-store.json` selects that database only after a successful save. The old database and its sidecars are never overwritten or deleted by this path. A missing or invalid marker target is an error, not permission to create an empty workspace.

## Limits

- Local files are not encrypted by Focus Desk. FileVault and encrypted external backup storage remain separate user/system choices. No backup content is sent to a server.
- Retention is bounded: 48 hourly snapshots, 20 recovery copies, five startup database snapshots. Export important milestones separately.
- Automatic backups may lag the latest committed data by up to 30 seconds. Uncommitted form text is not a crash-proof draft system. A sudden power loss or a failed disk can still destroy changes that could not be written anywhere.
- Undo history is session-local. Persistent recovery after relaunch uses backup restoration, which replaces the entire workspace rather than merging individual records.
- Import/export currently supports workspaces up to 64 MB. Larger workspaces need a streaming format before increasing this limit.

## Release gates

- Apple Silicon only; build release artifacts with `--arch arm64`. No Intel or universal-binary QA promise.
- Run the automated migration, save-failure, round-trip, undo, WAL snapshot, retention, and recovery tests on the oldest supported macOS as well as the current release before publishing.
- Verify export/import and startup recovery in the signed sandboxed app with the user-selected read/write file entitlement. This Swift package does not yet contain the final App Store project, signing configuration, or installer.
- Verify a normal quit, forced quit, disk-full condition, read-only backup destination, and an app upgrade using disposable data. Never run destructive recovery tests against a user's production database.
- For Mac App Store vs. GitHub builds, explicitly test the transition between sandbox and non-sandbox storage. Do not silently move or replace one installation's database.

## API references

- [SwiftData model contexts](https://developer.apple.com/documentation/swiftdata/modelcontext)
- [Schema migration plans](https://developer.apple.com/documentation/swiftdata/schemamigrationplan)
- [Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)
- [SQLite online backup](https://www.sqlite.org/backup.html)
