import Foundation
import SwiftData
import FocusDeskCore

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

    var snapshot: ActivityIntervalSnapshot {
        .init(id: id, categoryID: categoryID, start: startedAt, end: endedAt)
    }
}
