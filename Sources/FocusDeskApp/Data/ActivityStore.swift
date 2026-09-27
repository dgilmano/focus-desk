import AppKit
import FocusDeskCore
import Observation
import SwiftData

@MainActor
@Observable
final class ActivityStore {
    private(set) var categories: [ActivityCategory] = []
    private(set) var intervals: [ActivityInterval] = []
    private(set) var trackingSessions: [TrackingSession] = []
    var errorMessage: String?
    private(set) var notice: String?
    @ObservationIgnored private var context: ModelContext
    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let didSave: () -> Void
    @ObservationIgnored private let saveChanges: (ModelContext) throws -> Void
    @ObservationIgnored private let beforeDeletion: () throws -> Void
    @ObservationIgnored private var heartbeat: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    var availableCategories: [ActivityCategory] { categories.filter { !$0.isArchived } }
    var activeInterval: ActivityInterval? { intervals.first { $0.endedAt == nil } }
    var inactiveTrackingLabel: String { "Choose an Activity" }
    var activeCategory: ActivityCategory? { category(activeInterval?.categoryID) }
    var snapshots: [ActivityIntervalSnapshot] { intervals.map(\.snapshot) }

    init(container: ModelContainer, observeLifecycle: Bool = true,
         didSave: @escaping () -> Void = {}, beforeDeletion: @escaping () throws -> Void = {},
         saveChanges: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.saveChanges = saveChanges
        self.container = container
        self.didSave = didSave
        self.beforeDeletion = beforeDeletion
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
            for session in trackingSessions where session.endedAt == nil {
                session.endedAt = max(session.startedAt, min(Date(), session.lastObservedAt))
            }
            try saveChanges(context)
            try reload()
            didSave()
        } catch {
            context.rollback()
            errorMessage = "Activity could not be loaded: \(error.localizedDescription)"
        }
        if observeLifecycle { observeApplicationLifecycle() }
    }

    var activeTrackingSession: TrackingSession? { trackingSessions.first { $0.endedAt == nil } }

    func trackingWindows(now: Date) -> [DateInterval] {
        trackingSessions.map { DateInterval(start: $0.startedAt, end: max($0.startedAt, $0.endedAt ?? now)) }
    }

    @discardableResult
    func startTracking(at now: Date = Date()) -> Bool {
        guard activeTrackingSession == nil else { return true }
        return commit { try beginTracking(at: now) }
    }

    private func beginTracking(at now: Date) throws {
        guard activeTrackingSession == nil else { return }
        guard !trackingSessions.contains(where: { ($0.endedAt ?? .distantFuture) > now }) else {
            throw ActivityValidationError.overlap
        }
        context.insert(TrackingSession(start: now))
    }

    @discardableResult
    func stopTracking(at now: Date = Date(), reason: String? = nil) -> Bool {
        guard activeTrackingSession != nil || activeInterval != nil else { return true }
        return commit {
            if let active = activeInterval {
                active.endedAt = max(active.startedAt, now)
                active.lastObservedAt = active.endedAt!
            }
            if let session = activeTrackingSession {
                session.endedAt = max(session.startedAt, now)
                session.lastObservedAt = session.endedAt!
            }
            notice = reason
        }
    }

    func category(_ id: UUID?) -> ActivityCategory? { categories.first { $0.id == id } }
    func interval(_ id: UUID) -> ActivityInterval? { intervals.first { $0.id == id } }

    @discardableResult
    func toggleActivity(_ categoryID: UUID, at now: Date = Date()) -> Bool {
        if activeInterval?.categoryID == categoryID { return pause(at: now) }
        return start(categoryID, at: now)
    }

    @discardableResult
    func start(_ categoryID: UUID, at now: Date = Date()) -> Bool {
        guard let session = activeTrackingSession, now >= session.startedAt,
              let category = category(categoryID), !category.isArchived else { return false }
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
    func resizeInterval(_ original: ActivityIntervalSnapshot, to resized: ActivityIntervalSnapshot) -> Bool {
        guard let record = interval(original.id), record.snapshot == original,
              resized.id == original.id, resized.categoryID == original.categoryID,
              (resized.end == nil) == (original.end == nil) else {
            errorMessage = "This interval changed. Please try adjusting it again."
            return false
        }
        guard resized != original else { return true }
        return saveInterval(id: original.id, categoryID: original.categoryID, start: resized.start,
                            end: resized.end, taskID: record.taskID, taskTitle: record.taskTitle)
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
        return commit { try beforeDeletion(); context.delete(record) }
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

    @discardableResult
    func reorderCategories(_ ids: [UUID]) -> Bool {
        let visible = availableCategories.map(\.id)
        guard ids.count == visible.count, Set(ids) == Set(visible) else {
            errorMessage = "Activities changed. Please try reordering them again."
            return false
        }
        guard ids != visible else { return true }
        // Archived categories keep their slots; all existing records and history retain their IDs.
        let byID = Dictionary(uniqueKeysWithValues: availableCategories.map { ($0.id, $0) })
        var next = ids.makeIterator()
        let ordered = categories.map { category in
            category.isArchived ? category : byID[next.next()!]!
        }
        return commit {
            for (index, category) in ordered.enumerated() { category.sortOrder = index }
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
        guard activeInterval != nil || activeTrackingSession != nil else { return }
        _ = commit {
            if let activeInterval { activeInterval.lastObservedAt = max(activeInterval.startedAt, date) }
            if let session = activeTrackingSession { session.lastObservedAt = max(session.startedAt, date) }
        }
    }

    private func commit(_ mutation: () throws -> Void) -> Bool {
        var restore: (() -> Void)?
        do {
            let oldCategories = categories.map { ($0, WorkspaceBackup.CategoryRecord($0)) }
            let oldIntervals = intervals.map { ($0, WorkspaceBackup.IntervalRecord($0)) }
            let oldSessions = trackingSessions.map { ($0, WorkspaceBackup.TrackingRecord($0)) }
            restore = {
                for (model, saved) in oldCategories {
                    model.name = saved.name; model.colorName = saved.colorName; model.symbol = saved.symbol
                    model.sortOrder = saved.sortOrder; model.isArchived = saved.isArchived
                }
                for (model, saved) in oldIntervals {
                    model.categoryID = saved.categoryID; model.startedAt = saved.startedAt
                    model.endedAt = saved.endedAt; model.lastObservedAt = saved.lastObservedAt
                    model.taskID = saved.taskID; model.taskTitle = saved.taskTitle
                }
                for (model, saved) in oldSessions {
                    model.startedAt = saved.startedAt; model.endedAt = saved.endedAt
                    model.lastObservedAt = saved.lastObservedAt
                }
            }
            try mutation()
            try saveChanges(context)
            try reload()
            errorMessage = nil
            didSave()
            return true
        } catch {
            context.rollback()
            restore?()
            try? reload()
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func reload() throws {
        categories = try context.fetch(FetchDescriptor<ActivityCategory>(sortBy: [SortDescriptor(\.sortOrder)]))
        trackingSessions = try context.fetch(FetchDescriptor<TrackingSession>(sortBy: [SortDescriptor(\.startedAt)]))
        intervals = try context.fetch(FetchDescriptor<ActivityInterval>(sortBy: [SortDescriptor(\.startedAt)]))
    }

    func reloadAfterRestore() {
        context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            try reload()
            errorMessage = nil
            notice = "Backup restored. Choose an activity to resume."
        } catch {
            errorMessage = "Restored data could not be refreshed: \(error.localizedDescription)"
        }
    }

    private func observeApplicationLifecycle() {
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.stopTracking(reason: "Tracking stopped when your Mac went to sleep.") }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.stopTracking() }
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
