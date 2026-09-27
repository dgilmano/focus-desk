import XCTest
import SwiftData
import FocusDeskCore
@testable import FocusDesk

@MainActor
final class TrackingSessionTests: XCTestCase {
    func testActivityCannotStartUntilTrackingStartsOrAfterTrackingStops() throws {
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        let store = ActivityStore(container: container, observeLifecycle: false)
        let start = Date().addingTimeInterval(-3600)
        for category in store.categories {
            XCTAssertFalse(store.toggleActivity(category.id, at: start))
            XCTAssertFalse(store.start(category.id, at: start))
        }
        XCTAssertTrue(store.intervals.isEmpty)
        XCTAssertTrue(store.trackingSessions.isEmpty)
        XCTAssertTrue(store.startTracking(at: start))
        XCTAssertTrue(store.toggleActivity(store.categories[0].id, at: start))
        XCTAssertTrue(store.stopTracking(at: start.addingTimeInterval(60)))
        for category in store.categories {
            XCTAssertFalse(store.toggleActivity(category.id, at: start.addingTimeInterval(120)))
        }
        XCTAssertEqual(store.intervals.count, 1)
        XCTAssertEqual(store.trackingSessions.count, 1)
        XCTAssertNil(store.activeInterval)
        XCTAssertTrue(store.startTracking(at: start.addingTimeInterval(180)))
        XCTAssertTrue(store.toggleActivity(store.categories[1].id, at: start.addingTimeInterval(180)))
        XCTAssertEqual(store.intervals.count, 2)
    }

    func testRepeatedActivityClickStopsTimerAndNextClickResumes() throws {
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        let store = ActivityStore(container: container, observeLifecycle: false)
        let start = Date().addingTimeInterval(-3600)
        let study = store.categories[1].id
        XCTAssertTrue(store.startTracking(at: start))
        XCTAssertTrue(store.toggleActivity(study, at: start))
        XCTAssertEqual(store.activeCategory?.id, study)
        XCTAssertTrue(store.toggleActivity(study, at: start.addingTimeInterval(60)))
        XCTAssertNil(store.activeInterval)
        XCTAssertNotNil(store.activeTrackingSession)
        XCTAssertEqual(store.inactiveTrackingLabel, "Choose an Activity")
        XCTAssertEqual(store.intervals.first?.endedAt, start.addingTimeInterval(60))
        XCTAssertTrue(store.toggleActivity(study, at: start.addingTimeInterval(120)))
        XCTAssertTrue(store.toggleActivity(store.categories[0].id, at: start.addingTimeInterval(180)))
        XCTAssertEqual(store.activeCategory?.id, store.categories[0].id)
        let saved = try ModelContext(container).fetch(FetchDescriptor<ActivityInterval>())
        XCTAssertEqual(saved.count, 3)
        XCTAssertEqual(saved.filter { $0.endedAt == nil }.count, 1)
        XCTAssertEqual(store.trackingSessions.count, 1)
    }

    func testStartPauseStopAndResumeExcludeOutsideTime() throws {
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        let store = ActivityStore(container: container, observeLifecycle: false)
        let start = Date().addingTimeInterval(-7200)
        XCTAssertTrue(store.startTracking(at: start))
        XCTAssertTrue(store.startTracking(at: start.addingTimeInterval(10)))
        XCTAssertEqual(store.trackingSessions.count, 1)
        XCTAssertTrue(store.start(store.categories[0].id, at: start.addingTimeInterval(60)))
        XCTAssertTrue(store.pause(at: start.addingTimeInterval(120)))
        XCTAssertNotNil(store.activeTrackingSession)
        XCTAssertTrue(store.stopTracking(at: start.addingTimeInterval(180)))
        XCTAssertNil(store.activeTrackingSession)
        XCTAssertTrue(store.startTracking(at: start.addingTimeInterval(3600)))
        XCTAssertTrue(store.start(store.categories[0].id, at: start.addingTimeInterval(3600)))
        XCTAssertTrue(store.stopTracking(at: start.addingTimeInterval(3660)))
        XCTAssertNil(store.activeInterval)
        let range = DateInterval(start: start.addingTimeInterval(-3600), duration: 14400)
        let segments = ActivityTimeline.trackedSegments(in: range, intervals: store.snapshots,
            windows: store.trackingWindows(now: start.addingTimeInterval(4000)), now: start.addingTimeInterval(4000))
        XCTAssertEqual(segments.filter { $0.intervalID == nil }.reduce(0) { $0 + $1.duration }, 120)
        XCTAssertEqual(segments.filter { $0.intervalID != nil }.reduce(0) { $0 + $1.duration }, 120)
        let persisted = try ModelContext(container).fetch(FetchDescriptor<TrackingSession>())
        XCTAssertEqual(persisted.count, 2)
        XCTAssertTrue(persisted.allSatisfy { $0.endedAt != nil })
    }

    func testRelaunchClosesSessionAtCheckpointEvenWithoutActivity() throws {
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        let store = ActivityStore(container: container, observeLifecycle: false)
        let start = Date().addingTimeInterval(-3600)
        XCTAssertTrue(store.startTracking(at: start))
        store.checkpoint(at: start.addingTimeInterval(120))
        let relaunched = ActivityStore(container: container, observeLifecycle: false)
        XCTAssertNil(relaunched.activeTrackingSession)
        XCTAssertEqual(relaunched.trackingSessions.first?.endedAt, start.addingTimeInterval(120))
    }

    func testFailedStopRollsBackSessionAndActivityAndFailedStartDoesNotInsert() throws {
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        var shouldFail = false
        let store = ActivityStore(container: container, observeLifecycle: false, saveChanges: { context in
            if shouldFail { throw BackupError.invalid("Simulated save failure") }
            try context.save()
        })
        let start = Date().addingTimeInterval(-3600)
        shouldFail = true
        XCTAssertFalse(store.startTracking(at: start))
        XCTAssertTrue(store.trackingSessions.isEmpty)
        shouldFail = false
        XCTAssertTrue(store.startTracking(at: start))
        XCTAssertTrue(store.start(store.categories[0].id, at: start))
        shouldFail = true
        XCTAssertFalse(store.stopTracking(at: start.addingTimeInterval(60)))
        XCTAssertNotNil(store.activeTrackingSession)
        XCTAssertNotNil(store.activeInterval)
        let context = ModelContext(container)
        XCTAssertNil(try context.fetch(FetchDescriptor<TrackingSession>()).first?.endedAt)
        XCTAssertNil(try context.fetch(FetchDescriptor<ActivityInterval>()).first?.endedAt)
        shouldFail = false
        XCTAssertTrue(store.stopTracking(at: start.addingTimeInterval(120)))
    }

    func testBackupRoundTripValidationAndVersionOneCompatibility() throws {
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        let store = ActivityStore(container: container, observeLifecycle: false)
        let start = Date(timeIntervalSince1970: 1700000000.125)
        XCTAssertTrue(store.startTracking(at: start))
        store.checkpoint(at: start.addingTimeInterval(120))
        let snapshot = try WorkspaceBackup.capture(from: ModelContext(container))
        let decoded = try WorkspaceBackup.decode(snapshot.encoded())
        XCTAssertEqual(decoded.trackingSessions, snapshot.trackingSessions)
        let restored = try PersistenceController.makeModelContainer(inMemory: true)
        try decoded.apply(to: restored.mainContext)
        try restored.mainContext.save()
        let saved = try restored.mainContext.fetch(FetchDescriptor<TrackingSession>())
        XCTAssertEqual(saved.first?.endedAt, start.addingTimeInterval(120))
        var invalid = snapshot
        invalid.trackingSessions! += invalid.trackingSessions!
        XCTAssertThrowsError(try invalid.validated())
        invalid = snapshot
        invalid.trackingSessions![0].lastObservedAt = start.addingTimeInterval(-1)
        XCTAssertThrowsError(try invalid.validated())
        invalid = snapshot
        var duplicate = invalid.trackingSessions![0]
        duplicate.id = UUID()
        invalid.trackingSessions!.append(duplicate)
        XCTAssertThrowsError(try invalid.validated())
        var legacy = snapshot
        legacy.version = 1
        legacy.trackingSessions = nil
        let old = try WorkspaceBackup.decode(legacy.encoded())
        XCTAssertNil(old.trackingSessions)
        try old.apply(to: restored.mainContext)
        try restored.mainContext.save()
        XCTAssertTrue(try restored.mainContext.fetch(FetchDescriptor<TrackingSession>()).isEmpty)
    }

    func testSchemaTwoMigrationPreservesEveryFieldAndRelationship() throws {
        for versioned in [false, true] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("Old.store")
            let expected = try makeOldStore(at: url, versioned: versioned)
            let migrated = try PersistenceController.makeModelContainer(at: url)
            let actual = try WorkspaceBackup.capture(from: ModelContext(migrated))
            XCTAssertEqual(actual.tasks, expected.tasks)
            XCTAssertEqual(actual.entries, expected.entries)
            XCTAssertEqual(actual.categories, expected.categories)
            XCTAssertEqual(actual.intervals, expected.intervals)
            XCTAssertEqual(actual.trackingSessions, [])
        }
    }

    private func makeOldStore(at url: URL, versioned: Bool) throws -> WorkspaceBackup {
        // The exact four-model layout shipped before tracking sessions.
        let schema = versioned ? Schema(versionedSchema: FocusDeskSchemaV2.self)
            : Schema([HistoricalModels.FocusTask.self, HistoricalModels.ProgressEntry.self,
                      HistoricalModels.ActivityCategory.self, HistoricalModels.ActivityInterval.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        let context = ModelContext(container)
        let start = Date(timeIntervalSince1970: 1700000000)
        let task = HistoricalModels.FocusTask(title: "Existing", details: "Markdown **text**", createdAt: start,
            updatedAt: start.addingTimeInterval(60), sortOrder: 3, completedAt: start.addingTimeInterval(120),
            motivation: "Why", nextStep: "Next", localDraft: "Unsaved draft", tagData: "[]")
        let entry = HistoricalModels.ProgressEntry(note: "Journal", timestamp: start, task: task)
        let category = HistoricalModels.ActivityCategory(name: "Rest", colorName: "green", symbol: "leaf", sortOrder: 4)
        category.isArchived = true
        let interval = HistoricalModels.ActivityInterval(categoryID: category.id, start: start,
            end: start.addingTimeInterval(90), taskID: task.id, taskTitle: task.title)
        context.insert(task); context.insert(entry); context.insert(category); context.insert(interval)
        try context.save()
        // Build portable expected values without reading the upgraded store.
        let copy = try PersistenceController.makeModelContainer(inMemory: true)
        let newTask = FocusTask(id: task.id, title: task.title, details: task.details, createdAt: task.createdAt,
            updatedAt: task.updatedAt, sortOrder: task.sortOrder, completedAt: task.completedAt,
            motivation: task.motivation, nextStep: task.nextStep, localDraft: task.localDraft, tagData: task.tagData)
        let newCategory = ActivityCategory(id: category.id, name: category.name, colorName: category.colorName,
            symbol: category.symbol, sortOrder: category.sortOrder)
        newCategory.isArchived = category.isArchived
        copy.mainContext.insert(newTask)
        copy.mainContext.insert(ProgressEntry(id: entry.id, note: entry.note, timestamp: entry.timestamp, task: newTask))
        copy.mainContext.insert(newCategory)
        copy.mainContext.insert(ActivityInterval(id: interval.id, categoryID: interval.categoryID, start: interval.startedAt,
            end: interval.endedAt, taskID: interval.taskID, taskTitle: interval.taskTitle))
        try copy.mainContext.save()
        return try WorkspaceBackup.capture(from: copy.mainContext)
    }
}
