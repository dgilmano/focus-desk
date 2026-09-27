import Foundation
import SwiftData

// Frozen model definitions for schemas 1 and 2. Never edit these persisted fields.
enum HistoricalModels {
@Model
final class FocusTask: Identifiable {
    @Attribute(.unique) var id: UUID
    var title: String
    var details: String
    var createdAt: Date
    var updatedAt: Date
    @Attribute(originalName: "carouselOrder")
    var sortOrder: Int
    var completedAt: Date?
    var motivation: String?
    var nextStep: String?
    var localDraft: String
    var tagData: String?

    @Relationship(deleteRule: .cascade, inverse: \ProgressEntry.task)
    var entries: [ProgressEntry]

    init(
        id: UUID = UUID(),
        title: String,
        details: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sortOrder: Int,
        completedAt: Date? = nil,
        motivation: String? = nil,
        nextStep: String? = nil,
        localDraft: String = "",
        tagData: String? = nil,
        entries: [ProgressEntry] = []
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
        self.completedAt = completedAt
        self.motivation = motivation
        self.nextStep = nextStep
        self.localDraft = localDraft
        self.tagData = tagData
        self.entries = entries
    }
}

@Model
final class ProgressEntry: Identifiable {
    @Attribute(.unique) var id: UUID
    var note: String
    var timestamp: Date
    var task: FocusTask?

    init(id: UUID = UUID(), note: String, timestamp: Date, task: FocusTask? = nil) {
        self.id = id
        self.note = note
        self.timestamp = timestamp
        self.task = task
    }
}
@Model
final class ActivityCategory {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorName: String
    var symbol: String
    var sortOrder: Int
    var isArchived: Bool

    init(id: UUID = UUID(), name: String, colorName: String, symbol: String, sortOrder: Int) {
        self.id = id
        self.name = name
        self.colorName = colorName
        self.symbol = symbol
        self.sortOrder = sortOrder
        self.isArchived = false
    }
}

@Model
final class ActivityInterval {
    @Attribute(.unique) var id: UUID
    var categoryID: UUID
    var startedAt: Date
    var endedAt: Date?
    var lastObservedAt: Date
    var taskID: UUID?
    var taskTitle: String?

    init(id: UUID = UUID(), categoryID: UUID, start: Date, end: Date? = nil,
         taskID: UUID? = nil, taskTitle: String? = nil) {
        self.id = id
        self.categoryID = categoryID
        self.startedAt = start
        self.endedAt = end
        self.lastObservedAt = end ?? start
        self.taskID = taskID
        self.taskTitle = taskTitle
    }

}
}
