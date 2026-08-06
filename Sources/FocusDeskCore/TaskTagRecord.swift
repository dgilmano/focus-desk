import Foundation

public struct TaskTagRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var colorName: String
    public var isEnabled: Bool
    public var sortOrder: Int

    public init(
        id: UUID = UUID(),
        name: String,
        colorName: String = "gray",
        isEnabled: Bool = true,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.colorName = colorName
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
    }
}

public enum TaskTagCoding {
    public static func decode(_ source: String?) -> [TaskTagRecord] {
        guard
            let source,
            !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let data = source.data(using: .utf8)
        else {
            return []
        }

        let decoded = (try? JSONDecoder().decode([TaskTagRecord].self, from: data)) ?? []
        return sort(decoded)
    }

    public static func encode(_ tags: [TaskTagRecord]) -> String? {
        let sortedTags = sort(tags)

        guard !sortedTags.isEmpty else {
            return nil
        }

        guard
            let data = try? JSONEncoder().encode(sortedTags),
            let string = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return string
    }

    private static func sort(_ tags: [TaskTagRecord]) -> [TaskTagRecord] {
        tags.sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

            return lhs.sortOrder < rhs.sortOrder
        }
    }
}
