import Foundation

public struct ProgressSnapshot: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var note: String
    public var timestamp: Date

    public init(id: UUID = UUID(), note: String, timestamp: Date) {
        self.id = id
        self.note = note
        self.timestamp = timestamp
    }
}

public struct TaskSnapshot: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var details: String
    public var sortOrder: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    public var draft: String
    public var latestProgress: ProgressSnapshot?

    public init(
        id: UUID = UUID(),
        title: String,
        details: String = "",
        sortOrder: Int,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        completedAt: Date? = nil,
        draft: String = "",
        latestProgress: ProgressSnapshot? = nil
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.draft = draft
        self.latestProgress = latestProgress
    }

    public var isActive: Bool {
        completedAt == nil
    }
}

public struct DeskRouter: Sendable {
    public init() {}

    public func activeTasks(from tasks: [TaskSnapshot]) -> [TaskSnapshot] {
        tasks
            .filter(\.isActive)
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.createdAt < rhs.createdAt
                }

                return lhs.sortOrder < rhs.sortOrder
            }
    }

    public func currentTask(in tasks: [TaskSnapshot], selectedID: UUID?) -> TaskSnapshot? {
        let active = activeTasks(from: tasks)

        guard let selectedID else {
            return active.first
        }

        return active.first { $0.id == selectedID } ?? active.first
    }

    public func nextTask(in tasks: [TaskSnapshot], after selectedID: UUID?) -> TaskSnapshot? {
        neighbor(in: tasks, after: selectedID, offset: 1)
    }

    public func previousTask(in tasks: [TaskSnapshot], before selectedID: UUID?) -> TaskSnapshot? {
        neighbor(in: tasks, after: selectedID, offset: -1)
    }

    private func neighbor(in tasks: [TaskSnapshot], after selectedID: UUID?, offset: Int) -> TaskSnapshot? {
        let active = activeTasks(from: tasks)

        guard !active.isEmpty else {
            return nil
        }

        guard let selectedID, let index = active.firstIndex(where: { $0.id == selectedID }) else {
            return offset >= 0 ? active.first : active.last
        }

        let wrappedIndex = (index + offset + active.count) % active.count
        return active[wrappedIndex]
    }
}

public protocol ServerClock: Sendable {
    func now() async throws -> Date
}

public struct OfflineFirstServerClock: ServerClock {
    private var remoteClock: (any ServerClock)?

    public init(remoteClock: (any ServerClock)? = nil) {
        self.remoteClock = remoteClock
    }

    public static func environmentBacked(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> OfflineFirstServerClock {
        guard
            let rawURL = environment["FOCUS_DESK_SERVER_TIME_URL"],
            let url = URL(string: rawURL)
        else {
            return OfflineFirstServerClock()
        }

        return OfflineFirstServerClock(remoteClock: HTTPDateHeaderServerClock(endpoint: url))
    }

    public func now() async throws -> Date {
        if let remoteClock, let date = try? await remoteClock.now() {
            return date
        }

        return Date()
    }
}

public struct HTTPDateHeaderServerClock: ServerClock {
    public var endpoint: URL

    public init(endpoint: URL) {
        self.endpoint = endpoint
    }

    public func now() async throws -> Date {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 2

        let (_, response) = try await URLSession.shared.data(for: request)

        guard
            let httpResponse = response as? HTTPURLResponse,
            let dateHeader = httpResponse.value(forHTTPHeaderField: "Date"),
            let date = Self.date(fromHTTPDateHeader: dateHeader)
        else {
            return Date()
        }

        return date
    }

    public static func date(fromHTTPDateHeader header: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: header)
    }
}

public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public var currentTaskTitle: String
    public var latestProgressNote: String?
    public var latestProgressTimestamp: Date?
    public var activeTaskCount: Int
    public var generatedAt: Date

    public init(
        currentTaskTitle: String,
        latestProgressNote: String? = nil,
        latestProgressTimestamp: Date? = nil,
        activeTaskCount: Int,
        generatedAt: Date = Date()
    ) {
        self.currentTaskTitle = currentTaskTitle
        self.latestProgressNote = latestProgressNote
        self.latestProgressTimestamp = latestProgressTimestamp
        self.activeTaskCount = activeTaskCount
        self.generatedAt = generatedAt
    }

    public static let empty = WidgetSnapshot(
        currentTaskTitle: "No active task",
        latestProgressNote: nil,
        latestProgressTimestamp: nil,
        activeTaskCount: 0
    )
}

public struct WidgetSnapshotStore: Sendable {
    public static let appGroupIdentifier = "group.com.focusdesk.app"
    private static let snapshotKey = "focusdesk.widget-snapshot"

    private let suiteName: String

    public init(suiteName: String = Self.appGroupIdentifier) {
        self.suiteName = suiteName
    }

    public func read() -> WidgetSnapshot {
        guard
            let data = defaults.data(forKey: Self.snapshotKey),
            let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else {
            return .empty
        }

        return snapshot
    }

    public func write(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }

        defaults.set(data, forKey: Self.snapshotKey)
    }

    private var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }
}
