import FocusDeskCore
import SwiftData
import XCTest
@testable import FocusDesk

@MainActor
final class DataProtectionTests: XCTestCase {
    private enum SaveFailure: Error { case diskFull }

    #if DEBUG
    func testCloudDropMovesBranchAndSupportsUntaggedWithoutChangingTags() throws {
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let store = TaskStore(context: context)
        let parent = FocusTask(title: "Learning plan", sortOrder: 0)
        parent.tagRecords = [.init(name: "Learning")]
        let task = FocusTask(title: "Practice", sortOrder: 1)
        task.tagRecords = [.init(name: "Learning"), .init(name: "Weekly", sortOrder: 1)]
        task.parentTaskID = parent.id
        let tags = task.tagData
        let child = FocusTask(title: "Warm up", sortOrder: 2, completedAt: Date())
        child.parentTaskID = task.id
        child.tagRecords = [.init(name: "Learning")]
        let sport = FocusTask(title: "Training", sortOrder: 3)
        sport.tagRecords = [.init(name: "Sport")]
        for member in [parent, task, child, sport] { context.insert(member) }
        try context.save()
        let moved = try store.moveMapTask(id: task.id, from: "Learning", to: "Sport")
        XCTAssertEqual(moved, [task.id, child.id])
        XCTAssertEqual(task.projectName, "Sport")
        XCTAssertEqual(child.projectName, "Sport")
        XCTAssertEqual(child.parentTaskID, task.id)
        XCTAssertNil(task.parentTaskID)
        XCTAssertEqual(parent.deskProjectKey, "learning")
        XCTAssertEqual(task.tagData, tags)
        XCTAssertThrowsError(try store.moveMapTask(id: task.id, from: "Learning", to: nil))
        _ = try store.moveMapTask(id: task.id, from: "Sport", to: nil)
        XCTAssertNil(task.deskProjectKey)
        XCTAssertNil(child.deskProjectKey)
        XCTAssertThrowsError(try store.renameProject(from: nil, to: "Sport"))
        try store.renameProject(from: nil, to: " Mobility ")
        XCTAssertEqual(task.projectName, "Mobility")
        XCTAssertEqual(child.projectName, "Mobility")
        XCTAssertEqual(task.tagData, tags)
        let snapshot = try WorkspaceBackup.capture(from: ModelContext(container)).validated()
        XCTAssertEqual(Set(snapshot.projects ?? []), ["Sport", "Learning", "Mobility"])
        let fresh = FocusTask(title: "New note", sortOrder: 4)
        XCTAssertTrue(store.create(fresh))
        XCTAssertNil(fresh.deskProjectKey)
    }

    func testFailedDropRestoresParentAndProjectAndAllowsRetry() throws {
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let root = FocusTask(title: "Plan", sortOrder: 0)
        let child = FocusTask(title: "Practice", sortOrder: 1)
        child.parentTaskID = root.id
        let project = DeskProject(name: "Sport")
        context.insert(root)
        context.insert(child)
        context.insert(project)
        try context.save()
        var fail = true
        let store = TaskStore(context: context, persist: { if fail { throw SaveFailure.diskFull }; try $0.save() })
        XCTAssertThrowsError(try store.moveMapTask(id: child.id, from: nil, to: "Sport"))
        XCTAssertNil(child.projectName)
        XCTAssertEqual(child.parentTaskID, root.id)
        XCTAssertThrowsError(try store.renameProject(from: nil, to: "Learning"))
        XCTAssertNil(root.projectName)
        XCTAssertNil(child.projectName)
        fail = false
        _ = try store.moveMapTask(id: child.id, from: nil, to: "Sport")
        XCTAssertNil(child.parentTaskID)
        XCTAssertEqual(child.projectName, "Sport")
    }

    func testMapRenameIncludesLegacyAndCompletedTasksAndDeletionUndo() throws {
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let store = TaskStore(context: context)
        let root = populatedTask()
        root.tagRecords = [TaskTagRecord(name: "Learning", colorName: "green")]
        let tags = root.tagData
        let child = FocusTask(title: "Practice", sortOrder: 2)
        child.parentTaskID = root.id
        child.projectName = "learning"
        let past = FocusTask(title: "Archived", sortOrder: 3)
        past.projectName = "Learning"
        for task in [root, child, past] { context.insert(task) }
        context.insert(DeskProject(name: "Learning"))
        context.insert(DeskProject(name: "Sport"))
        try context.save()
        XCTAssertTrue(store.delete(past))
        XCTAssertThrowsError(try store.renameProject(from: "Learning", to: " sport "))
        try store.renameProject(from: "Learning", to: " Study ")
        XCTAssertEqual(root.tagData, tags)
        XCTAssertEqual(root.deskProjectTag?.name, "Study")
        XCTAssertEqual(root.deskProjectTag?.colorName, "green")
        XCTAssertEqual(child.projectName, "Study")
        XCTAssertTrue(store.undoDeletion())
        try store.renameTask(id: child.id, from: "Practice", to: " Practice piano ")
        XCTAssertThrowsError(try store.renameTask(id: child.id, from: "Practice", to: "Stale edit"))
        XCTAssertEqual(child.title, "Practice piano")
        XCTAssertEqual(child.parentTaskID, root.id)
        let snapshot = try WorkspaceBackup.capture(from: ModelContext(container)).validated()
        XCTAssertEqual(Set(snapshot.projects ?? []), ["Study", "Sport"])
        XCTAssertTrue(snapshot.tasks.allSatisfy { $0.projectName == "Study" })
        XCTAssertEqual(snapshot.entries.map(\.taskID), [root.id])
    }

    func testFailedMapRenameRestoresTaskAndProjectAndAllowsRetry() throws {
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let task = populatedTask()
        let project = DeskProject(name: "Work")
        context.insert(task)
        context.insert(project)
        try context.save()
        let original = WorkspaceBackup.TaskRecord(task)
        var fail = true
        let store = TaskStore(context: context, persist: {
            if fail { throw SaveFailure.diskFull }
            try $0.save()
        })
        XCTAssertThrowsError(try store.renameProject(from: "Work", to: "Projects"))
        XCTAssertThrowsError(try store.renameTask(id: task.id, from: original.title, to: "Updated"))
        XCTAssertEqual(project.name, "Work")
        XCTAssertEqual(project.key, "work")
        XCTAssertEqual(WorkspaceBackup.TaskRecord(task), original)
        fail = false
        try store.renameProject(from: "Work", to: "WORK")
        XCTAssertEqual(task.deskProjectTag?.name, "WORK")
        XCTAssertEqual(project.name, "WORK")
        XCTAssertThrowsError(try store.renameProject(from: "WORK", to: " "))
        XCTAssertThrowsError(try store.renameTask(id: task.id, from: original.title, to: " "))
    }
    #endif

    func testUpdateSavesDraftAndPausesActivityBeforeRecoveryCopy() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        let session = WorkspaceSession(container: container, backupDirectory: directory, observeLifecycle: false)
        let task = populatedTask()
        XCTAssertTrue(session.tasks.create(task))
        task.localDraft = "Unsubmitted work must survive the update"
        XCTAssertTrue(session.activity.startTracking(at: Date().addingTimeInterval(-60)))
        XCTAssertTrue(session.activity.start(session.activity.categories[0].id, at: Date().addingTimeInterval(-60)))
        try session.prepareForUpdate()
        XCTAssertNil(session.activity.activeInterval)
        let file = try XCTUnwrap(session.backups.files().first { $0.lastPathComponent.hasPrefix("recovery-") })
        let recovery = try WorkspaceBackup.read(from: file)
        XCTAssertEqual(recovery.tasks.first?.localDraft, task.localDraft)
        XCTAssertEqual(recovery.entries.count, 1)
        XCTAssertNotNil(recovery.intervals.first?.endedAt)
    }

    func testUpdateIsRefusedWhenRecoveryCopyCannotBeWritten() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let blocked = directory.appendingPathComponent("occupied")
        try Data("not a directory".utf8).write(to: blocked)
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        let session = WorkspaceSession(container: container, backupDirectory: blocked, observeLifecycle: false)
        let task = populatedTask()
        XCTAssertTrue(session.tasks.create(task))
        task.localDraft = "Keep this draft"
        XCTAssertThrowsError(try session.prepareForUpdate())
        XCTAssertEqual(try WorkspaceBackup.capture(from: ModelContext(container)).tasks.first?.localDraft, task.localDraft)
    }

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

    func testCompletingStepMovesOnlyThatLineToItsJournal() throws {
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let store = TaskStore(context: context)
        let source = "1. Собрать **логи**\n2. Собрать **логи**\n3. Открыть тикет"
        let task = FocusTask(title: "Сертификат", sortOrder: 0, nextStep: source, localDraft: "Мой черновик")
        XCTAssertTrue(store.create(task))
        XCTAssertTrue(store.completeNextStep(1, in: task, from: source))
        XCTAssertFalse(store.completeNextStep(1, in: task, from: source))
        let savedContext = ModelContext(container)
        let saved = try XCTUnwrap(savedContext.fetch(FetchDescriptor<FocusTask>()).first)
        XCTAssertEqual(saved.nextStep, "1. Собрать **логи**\n3. Открыть тикет")
        XCTAssertEqual(saved.entries.map(\.note), ["Done: Собрать **логи**"])
        XCTAssertEqual(saved.entries.first?.task?.id, task.id)
        XCTAssertEqual(saved.localDraft, "Мой черновик")
        XCTAssertNil(saved.completedAt)
    }

    func testFailedStepCompletionKeepsStepAndRetryRecordsItOnce() throws {
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let source = "- [x] Сверить версии"
        let task = FocusTask(title: "Проверка", sortOrder: 0, nextStep: source)
        context.insert(task)
        context.insert(ProgressEntry(note: "Начало", timestamp: Date(), task: task))
        try context.save()
        let updatedAt = task.updatedAt
        var fail = true
        let store = TaskStore(context: context, persist: {
            if fail { throw SaveFailure.diskFull }
            try $0.save()
        })
        XCTAssertFalse(store.completeNextStep(0, in: task, from: source))
        XCTAssertEqual(task.nextStep, source)
        XCTAssertEqual(task.updatedAt, updatedAt)
        XCTAssertEqual(task.entries.map(\.note), ["Начало"])
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<ProgressEntry>()), 1)
        fail = false
        XCTAssertTrue(store.completeNextStep(0, in: task, from: source))
        XCTAssertNil(task.nextStep)
        XCTAssertFalse(store.completeNextStep(0, in: task, from: source))
        XCTAssertEqual(task.entries.map(\.note).sorted(), ["Done: Сверить версии", "Начало"])
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

    func testJournalStepRoundTripAndFailedReturn() throws {
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        let context = container.mainContext
        var fail = false
        let store = TaskStore(context: context, persist: {
            if fail { throw SaveFailure.diskFull }
            try $0.save()
        })
        let source = "Первый\n- [ ] 2. **Тест**"
        let task = FocusTask(title: "Задача", sortOrder: 0, nextStep: source, localDraft: "Черновик")
        let other = FocusTask(title: "Другая задача", sortOrder: 1)
        XCTAssertTrue(store.create(task))
        XCTAssertTrue(store.create(other))
        XCTAssertTrue(store.completeNextStep(1, in: task, from: source))
        let entryID = try XCTUnwrap(task.entries.first?.id)
        let updatedAt = task.updatedAt
        XCTAssertFalse(store.moveJournalEntryToNextStep(entryID, in: other))
        fail = true
        XCTAssertFalse(store.moveJournalEntryToNextStep(entryID, in: task))
        XCTAssertEqual(task.nextStep, "Первый")
        XCTAssertEqual(task.updatedAt, updatedAt)
        XCTAssertEqual(task.entries.map(\.note), ["Done: 2. **Тест**"])
        fail = false
        XCTAssertTrue(store.moveJournalEntryToNextStep(entryID, in: task))
        XCTAssertFalse(store.moveJournalEntryToNextStep(entryID, in: task))
        XCTAssertEqual(NextStepChecklist(task.nextStep ?? "").items.map(\.text), ["Первый", "2. **Тест**"])
        XCTAssertEqual(task.localDraft, "Черновик")
        XCTAssertNil(other.nextStep)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<ProgressEntry>()), 0)
    }

    func testMoveOrdinaryJournalNoteIntoEmptyChecklist() throws {
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        let store = TaskStore(context: container.mainContext)
        let task = FocusTask(title: "Задача", sortOrder: 0)
        XCTAssertTrue(store.create(task))
        XCTAssertTrue(store.recordJournal(for: task, draft: "Проверить [отчёт](https://example.com)", at: Date()))
        let entryID = try XCTUnwrap(task.entries.first?.id)
        XCTAssertTrue(store.moveJournalEntryToNextStep(entryID, in: task))
        let checklist = NextStepChecklist(task.nextStep ?? "")
        XCTAssertEqual(checklist.items.map(\.text), ["Проверить [отчёт](https://example.com)"])
        XCTAssertFalse(try XCTUnwrap(checklist.items.first).isCompleted)
        XCTAssertTrue(task.entries.isEmpty)
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
        XCTAssertTrue(session.activity.startTracking(at: start))
        XCTAssertTrue(session.activity.start(session.activity.categories[0].id, at: start))
        session.activity.checkpoint(at: checkpoint)
        let backup = try session.backups.snapshot()
        try session.restore(backup)
        XCTAssertNil(session.activity.activeInterval)
        XCTAssertEqual(session.activity.intervals.first?.endedAt, checkpoint)
        XCTAssertTrue(session.activity.startTracking())
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
        XCTAssertTrue(session.activity.startTracking())
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
        XCTAssertTrue(session.activity.startTracking(at: date))
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
        let original = try makeMigrationFixture()
        let schema = Schema(FocusDeskSchemaV2.models)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        let context = container.mainContext
        let task = try XCTUnwrap(original.tasks.first)
        let old = HistoricalModels.FocusTask(id: task.id, title: task.title, details: task.details, createdAt: task.createdAt,
            updatedAt: task.updatedAt, sortOrder: task.sortOrder, completedAt: task.completedAt, motivation: task.motivation,
            nextStep: task.nextStep, localDraft: task.localDraft, tagData: task.tagData)
        context.insert(old)
        for entry in original.entries {
            context.insert(HistoricalModels.ProgressEntry(id: entry.id, note: entry.note, timestamp: entry.timestamp, task: old))
        }
        let category = try XCTUnwrap(original.categories.first)
        let interval = try XCTUnwrap(original.intervals.first)
        context.insert(HistoricalModels.ActivityCategory(id: category.id, name: category.name, colorName: category.colorName,
                                                         symbol: category.symbol, sortOrder: category.sortOrder))
        context.insert(HistoricalModels.ActivityInterval(id: interval.id, categoryID: category.id, start: interval.startedAt, end: interval.endedAt))
        try context.save()
        return original
    }

    private func makeMigrationFixture() throws -> WorkspaceBackup {
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        let context = container.mainContext
        context.insert(populatedTask())
        let category = ActivityCategory(name: "Work", colorName: "blue", symbol: "briefcase", sortOrder: 0)
        context.insert(category)
        context.insert(ActivityInterval(categoryID: category.id, start: Date(timeIntervalSince1970: 100), end: Date(timeIntervalSince1970: 200)))
        try context.save()
        return try WorkspaceBackup.capture(from: context)
    }
}
