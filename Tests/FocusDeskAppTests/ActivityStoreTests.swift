import XCTest
import SwiftData
@testable import FocusDesk

@MainActor
final class ActivityStoreTests: XCTestCase {
    func testSwitchPauseAndRepeatedSelectionArePersisted() throws {
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        let store = ActivityStore(container: container, observeLifecycle: false)
        let start = Date().addingTimeInterval(-3600)
        let work = store.categories[0].id
        let rest = store.categories[1].id
        XCTAssertTrue(store.start(work, at: start))
        XCTAssertTrue(store.start(work, at: start.addingTimeInterval(60)))
        XCTAssertEqual(store.intervals.count, 1)
        XCTAssertEqual(store.activeInterval?.startedAt, start)
        XCTAssertTrue(store.start(rest, at: start.addingTimeInterval(1200)))
        XCTAssertEqual(store.intervals[0].endedAt, store.intervals[1].startedAt)
        XCTAssertTrue(store.pause(at: start.addingTimeInterval(1800)))
        XCTAssertNil(store.activeInterval)
        let loaded = try ModelContext(container).fetch(FetchDescriptor<ActivityInterval>())
        XCTAssertEqual(loaded.count, 2)
        XCTAssertTrue(loaded.allSatisfy { $0.endedAt != nil })
    }

    func testRelaunchRecoversToCheckpointAndDoesNotCountOfflineGap() throws {
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        let store = ActivityStore(container: container, observeLifecycle: false)
        let start = Date().addingTimeInterval(-7200)
        let checkpoint = start.addingTimeInterval(60)
        store.start(store.categories[0].id, at: start)
        store.checkpoint(at: checkpoint)
        let reopened = ActivityStore(container: container, observeLifecycle: false)
        XCTAssertNil(reopened.activeInterval)
        XCTAssertEqual(reopened.intervals.first?.endedAt, checkpoint)
        XCTAssertNotNil(reopened.notice)
        XCTAssertEqual(reopened.categories.count, 5)
    }

    func testOverlapRollsBackAndSplitDeleteAndTaskLinkWork() throws {
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        let store = ActivityStore(container: container, observeLifecycle: false)
        let start = Date().addingTimeInterval(-7200)
        let category = store.categories[0].id
        let task = UUID()
        XCTAssertTrue(store.saveInterval(id: nil, categoryID: category, start: start,
                                         end: start.addingTimeInterval(3600), taskID: task, taskTitle: "Task"))
        let id = store.intervals[0].id
        XCTAssertFalse(store.saveInterval(id: nil, categoryID: category, start: start.addingTimeInterval(60),
                                          end: start.addingTimeInterval(120), taskID: nil, taskTitle: nil))
        XCTAssertEqual(store.intervals.count, 1)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(store.splitInterval(id, at: start.addingTimeInterval(1800)))
        XCTAssertEqual(store.intervals.count, 2)
        XCTAssertTrue(store.intervals.allSatisfy { $0.taskID == task })
        XCTAssertTrue(store.deleteInterval(id))
        XCTAssertEqual(store.intervals.count, 1)
    }

    func testCategoryArchiveKeepsHistoryAndStopsActiveInterval() throws {
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        let store = ActivityStore(container: container, observeLifecycle: false)
        let category = store.categories[0].id
        store.start(category, at: Date().addingTimeInterval(-60))
        store.setArchived(category, true)
        XCTAssertNil(store.activeInterval)
        XCTAssertNotNil(store.category(category))
        XCTAssertEqual(store.intervals.count, 1)
        XCTAssertFalse(store.availableCategories.contains { $0.id == category })
        XCTAssertFalse(store.start(category))
        store.setArchived(category, false)
        XCTAssertTrue(store.availableCategories.contains { $0.id == category })
        XCTAssertTrue(store.saveCategory(id: category, name: "Client work", color: "mint", symbol: "briefcase"))
        XCTAssertEqual(store.category(category)?.name, "Client work")
        XCTAssertFalse(store.saveCategory(id: nil, name: " Client work ", color: "blue", symbol: "book"))
    }

    func testExistingTaskStoreMigratesWithoutLosingTaskOrJournal() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Migration.store")
        let taskID = UUID()
        try createOriginalStore(at: url, taskID: taskID)
        let upgraded = try PersistenceController.makeModelContainer(at: url)
        let context = ModelContext(upgraded)
        let tasks = try context.fetch(FetchDescriptor<FocusTask>())
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?.id, taskID)
        XCTAssertEqual(tasks.first?.entries.first?.note, "Existing journal")
        let activity = ActivityStore(container: upgraded, observeLifecycle: false)
        XCTAssertEqual(activity.categories.count, 5)
        XCTAssertNil(activity.errorMessage)
    }

    private func createOriginalStore(at url: URL, taskID: UUID) throws {
        let schema = Schema([FocusTask.self, ProgressEntry.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        let context = ModelContext(container)
        let task = FocusTask(id: taskID, title: "Existing task", sortOrder: 0)
        let entry = ProgressEntry(note: "Existing journal", timestamp: Date(), task: task)
        context.insert(task)
        context.insert(entry)
        try context.save()
    }
}
