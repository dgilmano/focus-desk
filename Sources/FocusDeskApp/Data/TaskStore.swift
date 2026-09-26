import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class TaskStore {
    private(set) var errorMessage: String?
    private(set) var deletionMessage: String?
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let persist: (ModelContext) throws -> Void
    @ObservationIgnored private let didSave: () -> Void
    @ObservationIgnored private let beforeDeletion: () throws -> Void
    @ObservationIgnored private var deletions: [DeletedRecord] = []

    private enum DeletedRecord {
        case task(WorkspaceBackup.TaskRecord, [WorkspaceBackup.JournalRecord])
        case entry(WorkspaceBackup.JournalRecord)
    }

    init(context: ModelContext, persist: @escaping (ModelContext) throws -> Void = { try $0.save() },
         didSave: @escaping () -> Void = {}, beforeDeletion: @escaping () throws -> Void = {}) {
        self.context = context
        self.persist = persist
        self.didSave = didSave
        self.beforeDeletion = beforeDeletion
        context.autosaveEnabled = false
    }

    /// Keep bound edits in memory on failure so retry never discards the user's text.
    @discardableResult func save() -> Bool {
        do {
            if context.hasChanges { try persist(context); didSave() }
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Changes could not be saved. Your text is still here. Retry before closing Focus Desk. \(error.localizedDescription)"
            return false
        }
    }

    /// Save pending edits first. Only the new operation can then be rolled back.
    @discardableResult func perform(rollback restoreVisibleState: () -> Void = {}, _ mutation: () throws -> Void) -> Bool {
        guard save() else { return false }
        do {
            try mutation()
            try persist(context)
            errorMessage = nil
            didSave()
            return true
        } catch {
            // Remove inverse references before discarding inserts. SwiftUI may still hold these models.
            for entry in context.insertedModelsArray.compactMap({ $0 as? ProgressEntry }) { entry.task = nil }
            restoreVisibleState()
            context.rollback()
            errorMessage = "The operation was not saved. Your previous data is unchanged. \(error.localizedDescription)"
            return false
        }
    }

    func create(_ task: FocusTask) -> Bool {
        perform { context.insert(task) }
    }

    func recordJournal(for task: FocusTask, draft: String, at timestamp: Date) -> Bool {
        let note = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty, task.modelContext != nil else { return false }
        let previousDraft = task.localDraft
        let previousUpdatedAt = task.updatedAt
        let previousEntries = task.entries
        return perform(rollback: {
            task.localDraft = previousDraft
            task.updatedAt = previousUpdatedAt
            task.entries = previousEntries
        }) {
            let entry = ProgressEntry(note: note, timestamp: timestamp, task: task)
            context.insert(entry)
            // The user may have continued typing while the timestamp was being fetched.
            if task.localDraft == draft { task.localDraft = "" }
            task.updatedAt = timestamp
        }
    }

    func setCompleted(_ task: FocusTask, _ completed: Bool) -> Bool {
        let completedAt = task.completedAt
        let updatedAt = task.updatedAt
        return perform(rollback: {
            task.completedAt = completedAt
            task.updatedAt = updatedAt
        }) {
            task.completedAt = completed ? Date() : nil
            task.updatedAt = Date()
        }
    }

    func delete(_ task: FocusTask) -> Bool {
        let record = DeletedRecord.task(.init(task), task.entries.map(WorkspaceBackup.JournalRecord.init))
        guard perform({ try beforeDeletion(); context.delete(task) }) else { return false }
        remember(record)
        return true
    }

    func delete(_ entry: ProgressEntry, from task: FocusTask) -> Bool {
        let record = DeletedRecord.entry(.init(entry))
        let updatedAt = task.updatedAt
        guard perform(rollback: { task.updatedAt = updatedAt }, {
            try beforeDeletion()
            context.delete(entry)
            task.updatedAt = Date()
        }) else { return false }
        remember(record)
        return true
    }

    @discardableResult func undoDeletion() -> Bool {
        guard let record = deletions.last else { return false }
        guard perform({
            switch record {
            case .task(let saved, let entries):
                let task = saved.makeModel()
                context.insert(task)
                for entry in entries {
                    context.insert(ProgressEntry(id: entry.id, note: entry.note, timestamp: entry.timestamp, task: task))
                }
            case .entry(let saved):
                guard let task = try context.fetch(FetchDescriptor<FocusTask>()).first(where: { $0.id == saved.taskID }) else {
                    throw BackupError.invalid("Restore this entry's task first.")
                }
                context.insert(ProgressEntry(id: saved.id, note: saved.note, timestamp: saved.timestamp, task: task))
            }
        }) else { return false }
        deletions.removeLast()
        updateDeletionMessage()
        return true
    }

    func clearDeletionHistory() {
        deletions.removeAll()
        updateDeletionMessage()
    }

    private func remember(_ record: DeletedRecord) {
        deletions.append(record)
        if deletions.count > 20 { deletions.removeFirst() }
        updateDeletionMessage()
    }

    private func updateDeletionMessage() {
        switch deletions.last {
        case .task: deletionMessage = "Task deleted"
        case .entry: deletionMessage = "Journal entry deleted"
        case nil: deletionMessage = nil
        }
    }
}
