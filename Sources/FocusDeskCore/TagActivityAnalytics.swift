import Foundation

public struct TagActivityEvent: Equatable, Sendable {
    public var taskID: UUID
    public var taskTitle: String
    public var tags: [TaskTagRecord]
    public var timestamp: Date

    public init(
        taskID: UUID,
        taskTitle: String,
        tags: [TaskTagRecord],
        timestamp: Date
    ) {
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.tags = tags
        self.timestamp = timestamp
    }
}

public struct TagActivitySummary: Equatable, Identifiable, Sendable {
    public var id: String {
        normalizedName
    }

    public var name: String
    public var normalizedName: String
    public var colorName: String
    public var estimatedMinutes: Double
    public var journalStepCount: Int
    public var taskCount: Int

    public init(
        name: String,
        normalizedName: String,
        colorName: String,
        estimatedMinutes: Double,
        journalStepCount: Int,
        taskCount: Int
    ) {
        self.name = name
        self.normalizedName = normalizedName
        self.colorName = colorName
        self.estimatedMinutes = estimatedMinutes
        self.journalStepCount = journalStepCount
        self.taskCount = taskCount
    }
}

public struct TagActivityAnalyzer: Sendable {
    public var defaultStepMinutes: Double
    public var maxStepIntervalMinutes: Double

    public init(defaultStepMinutes: Double = 25, maxStepIntervalMinutes: Double = 120) {
        self.defaultStepMinutes = defaultStepMinutes
        self.maxStepIntervalMinutes = maxStepIntervalMinutes
    }

    public func summaries(
        for events: [TagActivityEvent],
        in interval: DateInterval
    ) -> [TagActivitySummary] {
        let intervalEvents = events
            .filter { interval.contains($0.timestamp) }
            .sorted { lhs, rhs in
                lhs.timestamp < rhs.timestamp
            }

        guard !intervalEvents.isEmpty else {
            return []
        }

        var accumulators: [String: TagActivityAccumulator] = [:]

        for index in intervalEvents.indices {
            let event = intervalEvents[index]
            let previousEvent = index == intervalEvents.startIndex ? nil : intervalEvents[intervalEvents.index(before: index)]
            let estimatedMinutes = estimatedMinutes(for: event, after: previousEvent)
            let tags = normalizedTags(for: event)
            let splitMinutes = estimatedMinutes / Double(tags.count)

            for tag in tags {
                var accumulator = accumulators[tag.normalizedName] ?? TagActivityAccumulator(
                    name: tag.name,
                    normalizedName: tag.normalizedName,
                    colorName: tag.colorName
                )

                accumulator.estimatedMinutes += splitMinutes
                accumulator.journalStepCount += 1
                accumulator.taskIDs.insert(event.taskID)
                accumulators[tag.normalizedName] = accumulator
            }
        }

        return accumulators.values
            .map(\.summary)
            .sorted { lhs, rhs in
                if lhs.estimatedMinutes == rhs.estimatedMinutes {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }

                return lhs.estimatedMinutes > rhs.estimatedMinutes
            }
    }

    private func estimatedMinutes(for event: TagActivityEvent, after previousEvent: TagActivityEvent?) -> Double {
        guard let previousEvent else {
            return defaultStepMinutes
        }

        let elapsedMinutes = event.timestamp.timeIntervalSince(previousEvent.timestamp) / 60

        guard elapsedMinutes.isFinite, elapsedMinutes > 0 else {
            return defaultStepMinutes
        }

        return min(elapsedMinutes, maxStepIntervalMinutes)
    }

    private func normalizedTags(for event: TagActivityEvent) -> [NormalizedTagActivity] {
        var seenNames = Set<String>()
        var tags: [NormalizedTagActivity] = []

        for tag in event.tags where tag.isEnabled {
            let name = tag.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedName = Self.normalizedName(name)

            guard !name.isEmpty, !seenNames.contains(normalizedName) else {
                continue
            }

            seenNames.insert(normalizedName)
            tags.append(
                NormalizedTagActivity(
                    name: name,
                    normalizedName: normalizedName,
                    colorName: tag.colorName
                )
            )
        }

        if tags.isEmpty {
            return [
                NormalizedTagActivity(
                    name: "Untagged",
                    normalizedName: Self.normalizedName("Untagged"),
                    colorName: "gray"
                )
            ]
        }

        return tags
    }

    private static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private struct NormalizedTagActivity {
    var name: String
    var normalizedName: String
    var colorName: String
}

private struct TagActivityAccumulator {
    var name: String
    var normalizedName: String
    var colorName: String
    var estimatedMinutes = 0.0
    var journalStepCount = 0
    var taskIDs = Set<UUID>()

    var summary: TagActivitySummary {
        TagActivitySummary(
            name: name,
            normalizedName: normalizedName,
            colorName: colorName,
            estimatedMinutes: estimatedMinutes,
            journalStepCount: journalStepCount,
            taskCount: taskIDs.count
        )
    }
}
