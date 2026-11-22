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
    var projectName: String?
    var parentTaskID: UUID?

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
final class DeskProject {
    @Attribute(.unique) var key: String
    var name: String

    init(name: String) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.key = Self.key(for: name)
    }

    static func key(for name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum TaskHierarchy {
    static func branch(from root: UUID, links: [(id: UUID, parent: UUID?)]) -> Set<UUID> {
        let children = Dictionary(grouping: links, by: \.parent)
        var found = Set<UUID>()
        var queue = [root]
        while let id = queue.popLast() {
            if found.insert(id).inserted { queue.append(contentsOf: (children[id] ?? []).map(\.id)) }
        }
        return found
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
    var deskProjectKey: String? { deskProjectTag.map { DeskProject.key(for: $0.name) } }

    /// An unset project preserves the original Desk grouping for existing tasks.
    var deskProjectTag: TaskTagRecord? {
        let tags = enabledTagRecords
        guard let projectName else {
            return tags.first { !DeskProject.key(for: $0.name).isEmpty }
        }
        let key = DeskProject.key(for: projectName)
        guard !key.isEmpty else { return nil }
        let paletteTag = tags.first { DeskProject.key(for: $0.name) == key } ?? tags.first
        return TaskTagRecord(id: paletteTag?.id ?? id, name: projectName, colorName: paletteTag?.colorName ?? "blue")
    }

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
