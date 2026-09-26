import FocusDeskCore
import SwiftData
import XCTest
@testable import FocusDesk

@MainActor
final class DataProtectionTests: XCTestCase {
    private enum SaveFailure: Error { case diskFull }

    func testFailedBoundEditRetainsTextAndCanBeRetried() throws {
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let task = FocusTask(title: "Original", sortOrder: 0)
        context.insert(task)
        try context.save()
        var fail = true
        let store = TaskStore(context: context, persist: {
            if fail { throw SaveFailure.diskFull }
            try $0.save()
        })
        task.title = "Unsaved title"
        task.motivation = "Do not lose this"
        XCTAssertFalse(store.save())
        XCTAssertEqual(task.title, "Unsaved title")
        XCTAssertTrue(context.hasChanges)
        XCTAssertNotNil(store.errorMessage)
        fail = false
        XCTAssertTrue(store.save())
        XCTAssertNil(store.errorMessage)
        let saved = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<FocusTask>()).first)
        XCTAssertEqual(saved.motivation, "Do not lose this")
    }

    func testJournalFailurePreservesDraftAndRetryDoesNotDuplicateEntry() throws {
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let task = FocusTask(title: "Task", sortOrder: 0, localDraft: "  Keep this note  ")
        context.insert(task)
        try context.save()
        var fail = true
        let store = TaskStore(context: context, persist: {
            if fail { throw SaveFailure.diskFull }
            try $0.save()
        })
        let draft = task.localDraft
        XCTAssertFalse(store.recordJournal(for: task, draft: draft, at: Date()))
        XCTAssertEqual(task.localDraft, draft)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgressEntry>()), 0)
        fail = false
        XCTAssertTrue(store.recordJournal(for: task, draft: draft, at: Date()))
        XCTAssertEqual(task.localDraft, "")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgressEntry>()), 1)
        XCTAssertEqual(task.entries.first?.note, "Keep this note")
    }

    func testJournalDoesNotClearTextTypedWhileWaitingForTimestamp() throws {
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        let store = TaskStore(context: container.mainContext)
        let task = FocusTask(title: "Task", sortOrder: 0, localDraft: "New draft")
        XCTAssertTrue(store.create(task))
        XCTAssertTrue(store.recordJournal(for: task, draft: "Submitted draft", at: Date()))
        XCTAssertEqual(task.localDraft, "New draft")
        XCTAssertEqual(task.entries.first?.note, "Submitted draft")
    }

    func testFailedCreateCompletionAndDeletionDoNotCommit() throws {
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let task = FocusTask(title: "Task", sortOrder: 0)
        context.insert(task)
        try context.save()
        let store = TaskStore(context: context, persist: { _ in throw SaveFailure.diskFull })
        XCTAssertFalse(store.create(FocusTask(title: "New task", sortOrder: 1)))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FocusTask>()), 1)
        XCTAssertFalse(store.setCompleted(task, true))
        XCTAssertNil(task.completedAt)
        XCTAssertFalse(store.delete(task))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FocusTask>()), 1)
        XCTAssertNil(store.deletionMessage)
    }

    func testUndoRestoresTaskAndJournalWithOriginalIDs() throws {
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let store = TaskStore(context: context)
        let task = populatedTask()
        XCTAssertTrue(store.create(task))
        let saved = try WorkspaceBackup.capture(from: context)
        let entry = try XCTUnwrap(task.entries.first)
        XCTAssertTrue(store.delete(entry, from: task))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgressEntry>()), 0)
        XCTAssertTrue(store.undoDeletion())
        XCTAssertEqual(task.entries.first?.id, saved.entries.first?.id)
        XCTAssertTrue(store.delete(task))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FocusTask>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgressEntry>()), 0)
        XCTAssertTrue(store.undoDeletion())
        let restored = try WorkspaceBackup.capture(from: context)
        XCTAssertEqual(restored.tasks.first?.id, saved.tasks.first?.id)
        XCTAssertEqual(restored.tasks.first?.tagData, saved.tasks.first?.tagData)
        XCTAssertEqual(restored.tasks.first?.localDraft, saved.tasks.first?.localDraft)
        XCTAssertEqual(restored.entries, saved.entries)
    }

    func testDeletionRequiresRecoveryCopy() throws {
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        let task = populatedTask()
        container.mainContext.insert(task)
        try container.mainContext.save()
        let store = TaskStore(context: container.mainContext, beforeDeletion: { throw SaveFailure.diskFull })
        XCTAssertFalse(store.delete(task))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<FocusTask>()), 1)
        XCTAssertEqual(task.entries.count, 1)
    }

    func testBackupRoundTripPreservesAllFieldsAndRestoresWithoutDuplicates() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        let session = WorkspaceSession(container: container, backupDirectory: directory, observeLifecycle: false)
        XCTAssertTrue(session.tasks.create(populatedTask()))
        let category = session.activity.categories[0]
        let taskID = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<FocusTask>()).first?.id)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertTrue(session.activity.saveInterval(id: nil, categoryID: category.id, start: start,
            end: start.addingTimeInterval(600), taskID: taskID, taskTitle: "Saved task title"))
        session.activity.setArchived(category.id, true)
        let original = try session.backups.snapshot()
        let decoded = try WorkspaceBackup.decode(original.encoded())
        XCTAssertEqual(decoded.tasks, original.tasks)
        XCTAssertEqual(decoded.entries, original.entries)
        XCTAssertEqual(decoded.categories, original.categories)
        XCTAssertEqual(decoded.intervals, original.intervals)

        let task = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<FocusTask>()).first)
        task.title = "New unsaved title"
        XCTAssertTrue(session.tasks.save())
        XCTAssertTrue(session.tasks.create(FocusTask(title: "Additional task", sortOrder: 10)))
        XCTAssertTrue(session.activity.saveCategory(id: nil, name: "Additional category", color: "pink", symbol: "book"))
        try session.restore(decoded)
        let restored = try session.backups.snapshot()
        XCTAssertEqual(restored.tasks, original.tasks)
        XCTAssertEqual(restored.entries, original.entries)
        XCTAssertEqual(Set(restored.categories.map(\.id)), Set(original.categories.map(\.id)))
        XCTAssertEqual(restored.intervals, original.intervals)
        XCTAssertEqual(session.activity.categories.count, original.categories.count)
        XCTAssertFalse(session.activity.availableCategories.contains { $0.id == category.id })
        let recovery = try XCTUnwrap(session.backups.files().first { $0.lastPathComponent.hasPrefix("recovery-") })
        let previous = try WorkspaceBackup.read(from: recovery)
        XCTAssertEqual(previous.tasks.count, 2)
        XCTAssertTrue(previous.tasks.contains { $0.title == "New unsaved title" })
        // Reimporting the same IDs is an update, never an insert conflict.
        try session.restore(decoded)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ProgressEntry>()), 1)
    }

    func testRestoreStopsActiveActivityAtCheckpointAndRefreshesActivityContext() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        let session = WorkspaceSession(container: container, backupDirectory: directory, observeLifecycle: false)
        let start = Date().addingTimeInterval(-1000)
        let checkpoint = start.addingTimeInterval(300)
        XCTAssertTrue(session.activity.start(session.activity.categories[0].id, at: start))
        session.activity.checkpoint(at: checkpoint)
        let backup = try session.backups.snapshot()
        try session.restore(backup)
        XCTAssertNil(session.activity.activeInterval)
        XCTAssertEqual(session.activity.intervals.first?.endedAt, checkpoint)
        XCTAssertTrue(session.activity.start(session.activity.categories[1].id))
        XCTAssertEqual(session.activity.intervals.count, 2)
    }

    func testInvalidBackupDoesNotChangeWorkspaceOrCreateRecoveryCopy() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        let session = WorkspaceSession(container: container, backupDirectory: directory, observeLifecycle: false)
        XCTAssertTrue(session.tasks.create(populatedTask()))
        let original = try session.backups.snapshot()
        var invalid = original
        invalid.version = 999
        XCTAssertThrowsError(try session.restore(invalid))
        invalid = original
        invalid.tasks.append(invalid.tasks[0])
        XCTAssertThrowsError(try session.restore(invalid))
        invalid = original
        invalid.entries[0].taskID = UUID()
        XCTAssertThrowsError(try session.restore(invalid))
        XCTAssertEqual(try session.backups.snapshot().tasks, original.tasks)
        XCTAssertTrue(try session.backups.files().isEmpty)
        XCTAssertThrowsError(try WorkspaceBackup.decode(Data("not a backup".utf8)))
    }

    func testRestoreRollsBackWhenPersistenceFails() throws {
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        let context = container.mainContext
        context.insert(populatedTask())
        try context.save()
        let original = try WorkspaceBackup.capture(from: context)
        var changed = original
        changed.tasks[0].title = "Replacement"
        changed.entries = []
        let store = TaskStore(context: context, persist: { _ in throw SaveFailure.diskFull })
        let visibleTask = try XCTUnwrap(context.fetch(FetchDescriptor<FocusTask>()).first)
        let rollback = try WorkspaceBackup.rollbackAction(in: context)
        XCTAssertFalse(store.perform(rollback: rollback) { try changed.apply(to: context) })
        XCTAssertEqual(visibleTask.title, original.tasks[0].title)
        XCTAssertEqual(visibleTask.entries.count, 1)
        XCTAssertEqual(try WorkspaceBackup.capture(from: context).tasks, original.tasks)
        XCTAssertEqual(try WorkspaceBackup.capture(from: context).entries, original.entries)
    }

    func testBackupFailureIsVisibleAndCannotOverwritePreviousCopy() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        let backups = BackupStore(container: container, directory: directory)
        let file = try backups.safetyCopy()
        let original = try Data(contentsOf: file)
        let blockedPath = directory.appendingPathComponent("not-a-directory")
        try Data("occupied".utf8).write(to: blockedPath)
        let blocked = BackupStore(container: container, directory: blockedPath)
        blocked.schedule()
        blocked.flush()
        XCTAssertNotNil(blocked.errorMessage)
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testUnversionedFourModelStoreOpensWithVersionedSchema() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("legacy.store")
        let original = try makeUnversionedStore(at: url)
        let migrated = try PersistenceController.makeModelContainer(at: url)
        let restored = try WorkspaceBackup.capture(from: ModelContext(migrated))
        XCTAssertEqual(restored.tasks, original.tasks)
        XCTAssertEqual(restored.entries, original.entries)
        XCTAssertEqual(restored.categories, original.categories)
        XCTAssertEqual(restored.intervals, original.intervals)
    }

    func testSQLiteSnapshotIncludesCommittedWALAndDoesNotReplaceExistingFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.store")
        let container = try PersistenceController.makeModelContainer(at: source)
        container.mainContext.insert(populatedTask())
        try container.mainContext.save()
        let destination = directory.appendingPathComponent("copy.store")
        try StoreSnapshot.copy(from: source, to: destination)
        let copy = try PersistenceController.makeModelContainer(at: destination)
        XCTAssertEqual(try copy.mainContext.fetchCount(FetchDescriptor<FocusTask>()), 1)
        XCTAssertEqual(try copy.mainContext.fetchCount(FetchDescriptor<ProgressEntry>()), 1)
        XCTAssertThrowsError(try StoreSnapshot.copy(from: source, to: destination))
    }

    func testRecoveryCreatesNewDatabaseAndPreservesUnreadableOriginal() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let originalURL = directory.appendingPathComponent("FocusDeskStore.store")
        let damaged = Data("unreadable original database".utf8)
        try damaged.write(to: originalURL)
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        container.mainContext.insert(populatedTask())
        try container.mainContext.save()
        let snapshot = try WorkspaceBackup.capture(from: container.mainContext)
        let recovered = try PersistenceController.recover(snapshot, in: directory)
        XCTAssertEqual(try recovered.mainContext.fetchCount(FetchDescriptor<FocusTask>()), 1)
        XCTAssertEqual(try Data(contentsOf: originalURL), damaged)
        let reopenedURL = try XCTUnwrap(PersistenceController.recoveredStoreURL(in: directory))
        XCTAssertNotEqual(reopenedURL, originalURL)
        let reopened = try PersistenceController.makeModelContainer(at: reopenedURL)
        XCTAssertEqual(try reopened.mainContext.fetchCount(FetchDescriptor<ProgressEntry>()), 1)
    }

    func testExportIncludesUnsavedTaskAndFreshActivityContext() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        let session = WorkspaceSession(container: container, backupDirectory: directory, observeLifecycle: false)
        let task = populatedTask()
        XCTAssertTrue(session.tasks.create(task))
        XCTAssertTrue(session.activity.start(session.activity.categories[0].id))
        let old = try session.exportSnapshot()
        task.localDraft = "Unsaved rescue text"
        XCTAssertTrue(session.activity.pause())
        let recent = try session.exportSnapshot()
        XCTAssertNil(old.intervals[0].endedAt)
        XCTAssertNotNil(recent.intervals[0].endedAt)
        XCTAssertEqual(recent.tasks[0].localDraft, "Unsaved rescue text")
    }

    func testFailedJournalDeletionRetainsEntryAndCanBeRetried() throws {
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        let task = populatedTask()
        container.mainContext.insert(task)
        try container.mainContext.save()
        var fail = true
        let store = TaskStore(context: container.mainContext, persist: {
            if fail { throw SaveFailure.diskFull }
            try $0.save()
        })
        let entry = try XCTUnwrap(task.entries.first)
        XCTAssertFalse(store.delete(entry, from: task))
        XCTAssertEqual(task.entries.count, 1)
        XCTAssertEqual(task.entries.first?.note, "Journal\nSecond line")
        fail = false
        XCTAssertTrue(store.delete(entry, from: task))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ProgressEntry>()), 0)
        XCTAssertTrue(store.undoDeletion())
        XCTAssertEqual(task.entries.count, 1)
    }

    func testRecoveryRetentionAndMalformedIntervalValidation() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        let session = WorkspaceSession(container: container, backupDirectory: directory, observeLifecycle: false)
        for _ in 0..<22 { try session.backups.safetyCopy() }
        XCTAssertEqual(try session.backups.files().count, 20)
        let date = Date().addingTimeInterval(-100)
        XCTAssertTrue(session.activity.start(session.activity.categories[0].id, at: date))
        var backup = try session.backups.snapshot()
        backup.intervals[0].endedAt = date.addingTimeInterval(-1)
        XCTAssertThrowsError(try backup.validated())
        backup = try session.backups.snapshot()
        var duplicate = backup.intervals[0]
        duplicate.id = UUID()
        backup.intervals.append(duplicate)
        XCTAssertThrowsError(try backup.validated())
    }

    private func populatedTask() -> FocusTask {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let task = FocusTask(title: "Test task", details: "**Markdown** details", createdAt: date,
            updatedAt: date, sortOrder: 5, completedAt: date, motivation: "Motivation",
            nextStep: "1. First\n2. Second", localDraft: "Unsubmitted note",
            tagData: TaskTagCoding.encode([TaskTagRecord(name: "Work", colorName: "mint")]))
        task.entries.append(ProgressEntry(note: "Journal\nSecond line", timestamp: date, task: task))
        return task
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeUnversionedStore(at url: URL) throws -> WorkspaceBackup {
        let schema = Schema([FocusTask.self, ProgressEntry.self, ActivityCategory.self, ActivityInterval.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        let context = container.mainContext
        context.insert(populatedTask())
        let category = ActivityCategory(name: "Work", colorName: "blue", symbol: "briefcase", sortOrder: 0)
        context.insert(category)
        context.insert(ActivityInterval(categoryID: category.id, start: Date(timeIntervalSince1970: 100), end: Date(timeIntervalSince1970: 200)))
        try context.save()
        return try WorkspaceBackup.capture(from: context)
    }
}
