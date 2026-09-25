import AppKit
import FocusDeskCore
import Observation
import SwiftData

@MainActor
@Observable
final class ActivityStore {
    private(set) var categories: [ActivityCategory] = []
    private(set) var intervals: [ActivityInterval] = []
    var errorMessage: String?
    private(set) var notice: String?
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private var heartbeat: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    var availableCategories: [ActivityCategory] { categories.filter { !$0.isArchived } }
    var activeInterval: ActivityInterval? { intervals.first { $0.endedAt == nil } }
    var activeCategory: ActivityCategory? { category(activeInterval?.categoryID) }
    var snapshots: [ActivityIntervalSnapshot] { intervals.map(\.snapshot) }

    init(container: ModelContainer, observeLifecycle: Bool = true) {
        context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            try reload()
            if categories.isEmpty {
                let defaults = [
                    ("Work", "blue", "briefcase"), ("Study", "purple", "book"),
                    ("Life", "orange", "house"), ("Rest", "green", "cup.and.saucer"),
                    ("Other", "gray", "ellipsis")
                ]
                for (index, value) in defaults.enumerated() {
                    context.insert(ActivityCategory(name: value.0, colorName: value.1, symbol: value.2, sortOrder: index))
                }
            }
            // A previous process cannot vouch for time after its last checkpoint.
            for interval in intervals where interval.endedAt == nil {
                interval.endedAt = max(interval.startedAt, min(Date(), interval.lastObservedAt))
                notice = "Previous activity saved. Choose an activity to resume."
            }
            try context.save()
            try reload()
        } catch {
            context.rollback()
            errorMessage = "Activity could not be loaded: \(error.localizedDescription)"
        }
        if observeLifecycle { observeApplicationLifecycle() }
    }

    func category(_ id: UUID?) -> ActivityCategory? { categories.first { $0.id == id } }
    func interval(_ id: UUID) -> ActivityInterval? { intervals.first { $0.id == id } }

    @discardableResult
    func start(_ categoryID: UUID, at now: Date = Date()) -> Bool {
        guard let category = category(categoryID), !category.isArchived else { return false }
        guard activeInterval?.categoryID != categoryID else { return true }
        return commit {
            if let activeInterval {
                activeInterval.endedAt = max(activeInterval.startedAt, now)
                activeInterval.lastObservedAt = activeInterval.endedAt!
            }
            let snapshot = ActivityIntervalSnapshot(categoryID: categoryID, start: now)
            try ActivityTimeline.validate(snapshot, among: snapshots, now: now)
            context.insert(ActivityInterval(id: snapshot.id, categoryID: categoryID, start: now))
            notice = nil
        }
    }

    @discardableResult
    func pause(at now: Date = Date(), reason: String? = nil) -> Bool {
        guard let activeInterval else { return true }
        return commit {
            activeInterval.endedAt = max(activeInterval.startedAt, now)
            activeInterval.lastObservedAt = activeInterval.endedAt!
            notice = reason
        }
    }

    @discardableResult
    func saveInterval(id: UUID?, categoryID: UUID, start: Date, end: Date?,
                      taskID: UUID?, taskTitle: String?, now: Date = Date()) -> Bool {
        guard category(categoryID) != nil else { return false }
        let candidate = ActivityIntervalSnapshot(id: id ?? UUID(), categoryID: categoryID, start: start, end: end)
        return commit {
            try ActivityTimeline.validate(candidate, among: snapshots, now: now)
            if let id, let record = interval(id) {
                record.categoryID = categoryID
                record.startedAt = start
                record.endedAt = end
                record.lastObservedAt = end ?? now
                record.taskID = taskID
                record.taskTitle = taskTitle
            } else {
                context.insert(ActivityInterval(id: candidate.id, categoryID: categoryID, start: start, end: end,
                                                taskID: taskID, taskTitle: taskTitle))
            }
        }
    }

    @discardableResult
    func splitInterval(_ id: UUID, at date: Date, now: Date = Date()) -> Bool {
        guard let record = interval(id) else { return false }
        return commit {
            let (first, second) = try ActivityTimeline.split(record.snapshot, at: date, now: now)
            record.endedAt = first.end
            record.lastObservedAt = first.end!
            let next = ActivityInterval(id: second.id, categoryID: second.categoryID, start: second.start,
                                        end: second.end, taskID: record.taskID, taskTitle: record.taskTitle)
            next.lastObservedAt = second.end ?? now
            context.insert(next)
        }
    }

    @discardableResult
    func deleteInterval(_ id: UUID) -> Bool {
        guard let record = interval(id) else { return false }
        return commit { context.delete(record) }
    }

    @discardableResult
    func saveCategory(id: UUID?, name: String, color: String, symbol: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        guard !categories.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            errorMessage = "An activity with this name already exists."
            return false
        }
        return commit {
            if let category = category(id) {
                category.name = name
                category.colorName = color
                category.symbol = symbol
            } else {
                context.insert(ActivityCategory(name: name, colorName: color, symbol: symbol,
                                                sortOrder: (categories.map(\.sortOrder).max() ?? -1) + 1))
            }
        }
    }

    func setArchived(_ id: UUID, _ archived: Bool) {
        guard let category = category(id) else { return }
        _ = commit {
            if archived, let active = activeInterval, active.categoryID == id {
                active.endedAt = max(active.startedAt, Date())
                active.lastObservedAt = active.endedAt!
            }
            category.isArchived = archived
        }
    }

    func checkpoint(at date: Date = Date()) {
        guard let activeInterval else { return }
        do {
            activeInterval.lastObservedAt = max(activeInterval.startedAt, date)
            try context.save()
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private func commit(_ mutation: () throws -> Void) -> Bool {
        do {
            try mutation()
            try context.save()
            try reload()
            errorMessage = nil
            return true
        } catch {
            context.rollback()
            try? reload()
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func reload() throws {
        categories = try context.fetch(FetchDescriptor<ActivityCategory>(sortBy: [SortDescriptor(\.sortOrder)]))
        intervals = try context.fetch(FetchDescriptor<ActivityInterval>(sortBy: [SortDescriptor(\.startedAt)]))
    }

    private func observeApplicationLifecycle() {
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.pause(reason: "Paused when your Mac went to sleep.") }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.pause() }
        })
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                guard let self else { return }
                self.checkpoint()
            }
        }
    }
}
