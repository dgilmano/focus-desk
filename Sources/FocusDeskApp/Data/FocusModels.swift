import Foundation
import SwiftData
import FocusDeskCore

private enum FocusTaskSchema {
    static let legacySortOrderAttributeName = ["car", "ouselOrder"].joined()
}

@Model
final class FocusTask: Identifiable {
    @Attribute(.unique) var id: UUID
    var title: String
    var details: String
    var createdAt: Date
    var updatedAt: Date
    @Attribute(originalName: FocusTaskSchema.legacySortOrderAttributeName)
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

extension FocusTask {
    var newestEntries: [ProgressEntry] {
        entries.sorted { lhs, rhs in
            lhs.timestamp > rhs.timestamp
        }
    }

    var latestEntry: ProgressEntry? {
        newestEntries.first
    }

    var tagRecords: [TaskTagRecord] {
        get {
            TaskTagCoding.decode(tagData)
        }
        set {
            tagData = TaskTagCoding.encode(newValue)
        }
    }

    var enabledTagRecords: [TaskTagRecord] {
        tagRecords.filter(\.isEnabled)
    }

    var snapshot: TaskSnapshot {
        TaskSnapshot(
            id: id,
            title: title,
            details: details,
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt,
            completedAt: completedAt,
            draft: localDraft,
            latestProgress: latestEntry.map {
                ProgressSnapshot(id: $0.id, note: $0.note, timestamp: $0.timestamp)
            }
        )
    }
}
