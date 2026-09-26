import Foundation
import SwiftData

/// A portable format, independent of SwiftData's SQLite layout. Never change version 1 in place.
struct WorkspaceBackup: Codable, Equatable, Sendable {
    var format = "FocusDeskBackup"
    var version = 1
    var createdAt = Date()
    var tasks: [TaskRecord]
    var entries: [JournalRecord]
    var categories: [CategoryRecord]
    var intervals: [IntervalRecord]

    struct TaskRecord: Codable, Equatable, Sendable {
        var id: UUID
        var title: String
        var details: String
        var createdAt: Date
        var updatedAt: Date
        var sortOrder: Int
        var completedAt: Date?
        var motivation: String?
        var nextStep: String?
        var localDraft: String
        var tagData: String?

        @MainActor init(_ task: FocusTask) {
            id = task.id; title = task.title; details = task.details
            createdAt = task.createdAt; updatedAt = task.updatedAt; sortOrder = task.sortOrder
            completedAt = task.completedAt; motivation = task.motivation; nextStep = task.nextStep
            localDraft = task.localDraft; tagData = task.tagData
        }

        @MainActor func makeModel() -> FocusTask {
            FocusTask(id: id, title: title, details: details, createdAt: createdAt,
                      updatedAt: updatedAt, sortOrder: sortOrder, completedAt: completedAt,
                      motivation: motivation, nextStep: nextStep, localDraft: localDraft, tagData: tagData)
        }

        @MainActor func restoreFields(on task: FocusTask) {
            task.title = title; task.details = details; task.createdAt = createdAt; task.updatedAt = updatedAt
            task.sortOrder = sortOrder; task.completedAt = completedAt; task.motivation = motivation
            task.nextStep = nextStep; task.localDraft = localDraft; task.tagData = tagData
        }
    }

    struct JournalRecord: Codable, Equatable, Sendable {
        var id: UUID
        var note: String
        var timestamp: Date
        var taskID: UUID?

        @MainActor init(_ entry: ProgressEntry) {
            id = entry.id; note = entry.note; timestamp = entry.timestamp; taskID = entry.task?.id
        }
    }

    struct CategoryRecord: Codable, Equatable, Sendable {
        var id: UUID
        var name: String
        var colorName: String
        var symbol: String
        var sortOrder: Int
        var isArchived: Bool

        @MainActor init(_ category: ActivityCategory) {
            id = category.id; name = category.name; colorName = category.colorName
            symbol = category.symbol; sortOrder = category.sortOrder; isArchived = category.isArchived
        }
    }

    struct IntervalRecord: Codable, Equatable, Sendable {
        var id: UUID
        var categoryID: UUID
        var startedAt: Date
        var endedAt: Date?
        var lastObservedAt: Date
        var taskID: UUID?
        var taskTitle: String?

        @MainActor init(_ interval: ActivityInterval) {
            id = interval.id; categoryID = interval.categoryID; startedAt = interval.startedAt
            endedAt = interval.endedAt; lastObservedAt = interval.lastObservedAt
            taskID = interval.taskID; taskTitle = interval.taskTitle
        }
    }

    @MainActor static func capture(from context: ModelContext) throws -> Self {
        Self(tasks: try context.fetch(FetchDescriptor<FocusTask>()).map(TaskRecord.init),
             entries: try context.fetch(FetchDescriptor<ProgressEntry>()).map(JournalRecord.init),
             categories: try context.fetch(FetchDescriptor<ActivityCategory>()).map(CategoryRecord.init),
             intervals: try context.fetch(FetchDescriptor<ActivityInterval>()).map(IntervalRecord.init))
    }

    /// Capture live references as well as values: rollback alone can leave SwiftUI-held models stale.
    @MainActor static func rollbackAction(in context: ModelContext) throws -> () -> Void {
        let tasks = try context.fetch(FetchDescriptor<FocusTask>()).map { ($0, TaskRecord($0), $0.entries) }
        let entries = try context.fetch(FetchDescriptor<ProgressEntry>()).map { ($0, JournalRecord($0), $0.task) }
        let categories = try context.fetch(FetchDescriptor<ActivityCategory>()).map { ($0, CategoryRecord($0)) }
        let intervals = try context.fetch(FetchDescriptor<ActivityInterval>()).map { ($0, IntervalRecord($0)) }
        return {
            for (model, saved, related) in tasks { saved.restoreFields(on: model); model.entries = related }
            for (model, saved, related) in entries {
                model.note = saved.note; model.timestamp = saved.timestamp; model.task = related
            }
            for (model, saved) in categories {
                model.name = saved.name; model.colorName = saved.colorName; model.symbol = saved.symbol
                model.sortOrder = saved.sortOrder; model.isArchived = saved.isArchived
            }
            for (model, saved) in intervals {
                model.categoryID = saved.categoryID; model.startedAt = saved.startedAt
                model.endedAt = saved.endedAt; model.lastObservedAt = saved.lastObservedAt
                model.taskID = saved.taskID; model.taskTitle = saved.taskTitle
            }
        }
    }

    func validated() throws -> Self {
        guard format == "FocusDeskBackup", version == 1 else {
            throw BackupError.invalid("This backup format is not supported by this version of Focus Desk.")
        }
        let taskIDs = Set(tasks.map(\.id))
        let categoryIDs = Set(categories.map(\.id))
        guard taskIDs.count == tasks.count, categoryIDs.count == categories.count,
              Set(entries.map(\.id)).count == entries.count,
              Set(intervals.map(\.id)).count == intervals.count else {
            throw BackupError.invalid("The backup contains duplicate records.")
        }
        guard entries.allSatisfy({ $0.taskID == nil || taskIDs.contains($0.taskID!) }),
              intervals.allSatisfy({ categoryIDs.contains($0.categoryID) }) else {
            throw BackupError.invalid("The backup contains broken task or activity links.")
        }
        let sorted = intervals.sorted {
            if $0.startedAt == $1.startedAt { return ($0.endedAt ?? .distantFuture) < ($1.endedAt ?? .distantFuture) }
            return $0.startedAt < $1.startedAt
        }
        for (index, interval) in sorted.enumerated() {
            guard interval.lastObservedAt >= interval.startedAt,
                  interval.endedAt.map({ $0 >= interval.startedAt }) ?? true else {
                throw BackupError.invalid("The backup contains an invalid activity duration.")
            }
            if index > 0 {
                guard let previousEnd = sorted[index - 1].endedAt, previousEnd <= interval.startedAt else {
                    throw BackupError.invalid("The backup contains overlapping activity intervals.")
                }
            }
        }
        return self
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Milliseconds retain journal ordering and subsecond activity boundaries.
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(self)
    }

    static let maximumFileSize = 64 * 1024 * 1024

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumFileSize else {
            throw BackupError.invalid("Choose a Focus Desk backup smaller than 64 MB.")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(Self.self, from: data).validated()
    }

    static func read(from url: URL) throws -> Self {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maximumFileSize else {
            throw BackupError.invalid("Choose a Focus Desk backup smaller than 64 MB.")
        }
        return try decode(Data(contentsOf: url))
    }

    /// Upsert first, then remove absent records; IDs shared with the current store must not be reinserted.
    @MainActor func apply(to context: ModelContext, now: Date = Date()) throws {
        _ = try validated()
        let oldTasks = try context.fetch(FetchDescriptor<FocusTask>())
        let oldEntries = try context.fetch(FetchDescriptor<ProgressEntry>())
        let oldCategories = try context.fetch(FetchDescriptor<ActivityCategory>())
        let oldIntervals = try context.fetch(FetchDescriptor<ActivityInterval>())
        var taskModels = Dictionary(uniqueKeysWithValues: oldTasks.map { ($0.id, $0) })
        let entryModels = Dictionary(uniqueKeysWithValues: oldEntries.map { ($0.id, $0) })
        let categoryModels = Dictionary(uniqueKeysWithValues: oldCategories.map { ($0.id, $0) })
        let intervalModels = Dictionary(uniqueKeysWithValues: oldIntervals.map { ($0.id, $0) })

        for record in tasks {
            let task = taskModels[record.id] ?? record.makeModel()
            if taskModels[record.id] == nil { context.insert(task); taskModels[record.id] = task }
            record.restoreFields(on: task)
        }
        for record in entries {
            let entry = entryModels[record.id] ?? ProgressEntry(id: record.id, note: record.note, timestamp: record.timestamp)
            if entryModels[record.id] == nil { context.insert(entry) }
            entry.note = record.note; entry.timestamp = record.timestamp
            entry.task = record.taskID.flatMap { taskModels[$0] }
        }
        for record in categories {
            let category = categoryModels[record.id] ?? ActivityCategory(id: record.id, name: record.name,
                colorName: record.colorName, symbol: record.symbol, sortOrder: record.sortOrder)
            if categoryModels[record.id] == nil { context.insert(category) }
            category.name = record.name; category.colorName = record.colorName; category.symbol = record.symbol
            category.sortOrder = record.sortOrder; category.isArchived = record.isArchived
        }
        for record in intervals {
            let interval = intervalModels[record.id] ?? ActivityInterval(id: record.id, categoryID: record.categoryID, start: record.startedAt)
            if intervalModels[record.id] == nil { context.insert(interval) }
            interval.categoryID = record.categoryID; interval.startedAt = record.startedAt
            // A restored backup must never count time spent outside this process.
            interval.endedAt = record.endedAt ?? max(record.startedAt, min(now, record.lastObservedAt))
            interval.lastObservedAt = record.endedAt == nil ? interval.endedAt! : record.lastObservedAt
            interval.taskID = record.taskID; interval.taskTitle = record.taskTitle
        }
        let taskIDs = Set(tasks.map(\.id)), entryIDs = Set(entries.map(\.id))
        let categoryIDs = Set(categories.map(\.id)), intervalIDs = Set(intervals.map(\.id))
        for entry in oldEntries where !entryIDs.contains(entry.id) { context.delete(entry) }
        for task in oldTasks where !taskIDs.contains(task.id) { context.delete(task) }
        for interval in oldIntervals where !intervalIDs.contains(interval.id) { context.delete(interval) }
        for category in oldCategories where !categoryIDs.contains(category.id) { context.delete(category) }
    }
}

enum BackupError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): message }
    }
}
