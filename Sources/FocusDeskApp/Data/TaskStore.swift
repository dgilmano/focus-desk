import Foundation
import FocusDeskCore
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
        case task(WorkspaceBackup.TaskRecord, [WorkspaceBackup.JournalRecord], children: [UUID])
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

    func completeNextStep(_ id: NextStepChecklist.Item.ID, in task: FocusTask, from source: String) -> Bool {
        guard task.modelContext === context, task.completedAt == nil, task.nextStep == source else { return false }
        let checklist = NextStepChecklist(source)
        guard checklist.items.indices.contains(id) else { return false }
        let remaining = checklist.removing(id)
        let previousEntries = task.entries
        let previousUpdatedAt = task.updatedAt
        return perform(rollback: {
            task.nextStep = source
            task.entries = previousEntries
            task.updatedAt = previousUpdatedAt
        }) {
            let now = Date()
            let entry = ProgressEntry(note: "Done: " + checklist.items[id].text, timestamp: now, task: task)
            context.insert(entry)
            task.nextStep = remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : remaining
            task.updatedAt = now
        }
    }

    func moveJournalEntryToNextStep(_ entryID: UUID, in task: FocusTask) -> Bool {
        guard task.modelContext === context, task.completedAt == nil,
              let entry = task.entries.first(where: { $0.id == entryID }) else { return false }
        let note = entry.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = (note.hasPrefix("Done: ") ? String(note.dropFirst("Done: ".count)) : note)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        let previous = task.nextStep
        let updatedAt = task.updatedAt
        return perform(rollback: {
            task.nextStep = previous
            task.updatedAt = updatedAt
        }) {
            try beforeDeletion()
            var steps = previous ?? ""
            if let last = steps.last, !last.isNewline { steps.append("\n") }
            // The open marker preserves literal list/checkbox prefixes in the original step text.
            steps += "- [ ] " + text
            task.nextStep = steps
            task.updatedAt = Date()
            context.delete(entry)
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
        let id = task.id
        let record = WorkspaceBackup.TaskRecord(task)
        let entries = task.entries.map(WorkspaceBackup.JournalRecord.init)
        var children: [FocusTask] = []
        guard perform(rollback: { for child in children { child.parentTaskID = id } }, {
            try beforeDeletion()
            children = try context.fetch(FetchDescriptor<FocusTask>(predicate: #Predicate { $0.parentTaskID == id }))
            for child in children { child.parentTaskID = nil }
            context.delete(task)
        }) else { return false }
        remember(.task(record, entries, children: children.map(\.id)))
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
        var reattached: [FocusTask] = []
        guard perform(rollback: { for child in reattached { child.parentTaskID = nil } }, {
            switch record {
            case .task(let saved, let entries, let children):
                let task = saved.makeModel()
                if !children.isEmpty || task.parentTaskID != nil {
                    let others = try context.fetch(FetchDescriptor<FocusTask>())
                    if let id = task.parentTaskID, !others.contains(where: { $0.id == id && $0.deskProjectKey == task.deskProjectKey }) {
                        task.parentTaskID = nil
                    }
                    let ancestors = TaskHierarchy.branch(from: task.id, links: (others + [task]).compactMap { child in
                        child.parentTaskID.map { ($0, child.id) }
                    })
                    let ids = Set(children)
                    reattached = others.filter {
                        ids.contains($0.id) && !ancestors.contains($0.id) && $0.parentTaskID == nil && $0.deskProjectKey == task.deskProjectKey
                    }
                    for child in reattached { child.parentTaskID = task.id }
                }
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

#if DEBUG || FOCUS_DESK_PERSONAL
struct DeskMapError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

extension TaskStore {
    func renameTask(id: UUID, from original: String, to input: String) throws {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw DeskMapError(message: "Enter a task name.") }
        let descriptor = FetchDescriptor<FocusTask>(predicate: #Predicate { $0.id == id })
        guard let task = try context.fetch(descriptor).first, task.title == original else {
            throw DeskMapError(message: "This task has changed. Reopen Edit to use its current name.")
        }
        guard name != original else { return }
        let previousDate = task.updatedAt
        guard perform(rollback: { task.title = original; task.updatedAt = previousDate }, {
            task.title = name
            task.updatedAt = Date()
        }) else { throw DeskMapError(message: errorMessage ?? "Could not rename the task.") }
    }

    func renameProject(from original: String?, to input: String) throws {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldKey = original.map(DeskProject.key)
        let newKey = DeskProject.key(for: name)
        guard !newKey.isEmpty else { throw DeskMapError(message: "Enter a project name.") }
        let projects = try context.fetch(FetchDescriptor<DeskProject>())
        let project = projects.first { $0.key == oldKey }
        let tasks = try context.fetch(FetchDescriptor<FocusTask>())
        let namedTasks = tasks.map { ($0, $0.deskProjectKey) }
        let members = namedTasks.filter { $0.1 == oldKey }.map { ($0.0, $0.0.projectName) }
        guard project != nil || !members.isEmpty else { throw DeskMapError(message: "This project has changed. Reopen it on the map.") }
        if oldKey != newKey && (projects.contains { $0.key == newKey } || namedTasks.contains { $0.1 == newKey }) {
            throw DeskMapError(message: "A project with this name already exists.")
        }
        let previousName = project?.name
        guard perform(rollback: {
            if let project, let oldKey, let previousName { project.key = oldKey; project.name = previousName }
            for (task, previous) in members { task.projectName = previous }
        }, {
            if let project {
                project.key = newKey
                project.name = name
            } else {
                context.insert(DeskProject(name: name))
            }
            // Tasks originally grouped by a tag now have an explicit project. Keep their tags and Journal intact.
            for (task, _) in members { task.projectName = name }
        }) else { throw DeskMapError(message: errorMessage ?? "Could not rename the project.") }

        // A subsequent undo of a deleted task must use the renamed project too.
        deletions = deletions.map { deletion in
            guard case .task(var record, let entries, let children) = deletion,
                  oldKey != nil, record.makeModel().deskProjectKey == oldKey else { return deletion }
            record.projectName = name
            return .task(record, entries, children: children)
        }
    }

    /// Move the same branch that moves with its parent in the voice editor.
    func moveMapTask(id: UUID, from source: String?, to destination: String?) throws -> Set<UUID> {
        let tasks = try context.fetch(FetchDescriptor<FocusTask>())
        let oldKey = source.map(DeskProject.key)
        let newKey = destination.map(DeskProject.key)
        guard let task = tasks.first(where: { $0.id == id }), task.completedAt == nil, task.deskProjectKey == oldKey else {
            throw DeskMapError(message: "The task or its project changed. Try dragging it again.")
        }
        guard oldKey != newKey else { return [] }
        let projects = try context.fetch(FetchDescriptor<DeskProject>())
        let destinationProject = projects.first { $0.key == newKey }
        if let newKey, destinationProject == nil, !tasks.contains(where: { $0.deskProjectKey == newKey }) {
            throw DeskMapError(message: "The destination project is no longer available.")
        }
        let branch = TaskHierarchy.branch(from: id, links: tasks.map { ($0.id, $0.parentTaskID) })
        let members = tasks.filter { branch.contains($0.id) }.map { ($0, $0.projectName) }
        let oldParent = task.parentTaskID
        let name = destinationProject?.name ?? destination?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard perform(rollback: {
            for (member, previous) in members { member.projectName = previous }
            task.parentTaskID = oldParent
        }, {
            // Keep a tag-derived source available for a return drop even after its last task leaves.
            if let source, !projects.contains(where: { $0.key == oldKey }) { context.insert(DeskProject(name: source)) }
            if destination != nil && destinationProject == nil { context.insert(DeskProject(name: name)) }
            if let oldParent, !tasks.contains(where: { $0.id == oldParent && $0.deskProjectKey == newKey }) {
                task.parentTaskID = nil
            }
            for (member, _) in members { member.projectName = name }
        }) else { throw DeskMapError(message: errorMessage ?? "Could not move the task.") }
        return branch
    }
}
#endif

#if (DEBUG && !FOCUS_DESK_UPDATES) || FOCUS_DESK_PERSONAL
extension TaskStore {
    func saveVoiceReview(_ review: VoiceTaskReview, target: VoiceTaskContext?) throws -> FocusTask? {
        let tasks = try context.fetch(FetchDescriptor<FocusTask>(sortBy: [SortDescriptor(\.sortOrder)]))
        let projectKey = DeskProject.key(for: review.projectName)
        let project = try context.fetch(FetchDescriptor<DeskProject>(predicate: #Predicate { $0.key == projectKey })).first
        let legacyName = tasks.compactMap { $0.deskProjectTag?.name }.first { DeskProject.key(for: $0) == projectKey }
        let name = (project?.name ?? legacyName ?? review.projectName).trimmingCharacters(in: .whitespacesAndNewlines)
        let insertProject = {
            if !name.isEmpty && project == nil { self.context.insert(DeskProject(name: name)) }
        }
        if review.kind == .project {
            guard !name.isEmpty else { throw VoiceNoteError.message("Enter a project name.") }
            guard perform(insertProject) else { throw VoiceNoteError.message(errorMessage ?? "Could not save the project.") }
            return nil
        }
        let existing = target.flatMap { original in tasks.first { $0.id == original.id } }
        if let target, existing.map(VoiceTaskContext.init) != target || target.isCompleted {
            throw VoiceNoteError.message("This task changed while the note was open. Review the note again or save a new task.")
        }
        guard review.unmatchedParent == nil else { throw VoiceNoteError.message("Choose a parent task or select No parent.") }
        if let id = review.parentTaskID {
            let candidates = VoiceTaskReview.parentChoices(for: target, tasks: tasks.map(VoiceTaskContext.init))
            guard let parent = candidates.first(where: { $0.id == id }), DeskProject.key(for: parent.project) == projectKey else {
                throw VoiceNoteError.message("The parent task or its project changed. Choose the parent again.")
            }
        }
        let title = review.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw VoiceNoteError.message("Enter a task title.") }
        let task = existing ?? FocusTask(title: title, sortOrder: (tasks.last?.sortOrder ?? -1) + 1)
        let previous = existing.map(WorkspaceBackup.TaskRecord.init)
        let moving = target.map { DeskProject.key(for: $0.project) != projectKey } ?? false
        let branch = moving ? TaskHierarchy.branch(from: task.id, links: tasks.map { ($0.id, $0.parentTaskID) }) : []
        let children = tasks.filter { $0.id != task.id && branch.contains($0.id) }.map { ($0, $0.projectName) }
        let saved = perform(rollback: {
            previous?.restoreFields(on: task)
            for (child, originalProject) in children { child.projectName = originalProject }
        }) {
            insertProject()
            if existing == nil { self.context.insert(task) }
            task.title = title
            task.details = review.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            let steps = review.nextStep.trimmingCharacters(in: .whitespacesAndNewlines)
            task.nextStep = steps.isEmpty ? nil : steps
            if moving || (existing == nil && !name.isEmpty) {
                task.projectName = name
            }
            for (child, _) in children { child.projectName = name }
            task.parentTaskID = review.parentTaskID
            task.updatedAt = Date()
        }
        if !saved { throw VoiceNoteError.message(errorMessage ?? "Could not save the reviewed changes.") }
        return task
    }
}
#endif
