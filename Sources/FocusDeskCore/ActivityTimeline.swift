import Foundation

public struct ActivityIntervalSnapshot: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var categoryID: UUID
    public var start: Date
    public var end: Date?

    public init(id: UUID = UUID(), categoryID: UUID, start: Date, end: Date? = nil) {
        self.id = id
        self.categoryID = categoryID
        self.start = start
        self.end = end
    }
}

public enum ActivityValidationError: Error, LocalizedError, Equatable {
    case invalidRange
    case futureTime
    case overlap
    case invalidSplit

    public var errorDescription: String? {
        switch self {
        case .invalidRange: "End time must be after start time."
        case .futureTime: "Activity cannot be recorded in the future."
        case .overlap: "This overlaps another interval. Adjust its times first."
        case .invalidSplit: "Choose a split time inside the interval."
        }
    }
}

public struct ActivityDaySegment: Identifiable, Equatable, Sendable {
    public var id: Date { start }
    public var intervalID: UUID?
    public var categoryID: UUID?
    public var start: Date
    public var end: Date
    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

public enum ActivityBalancePeriod: String, CaseIterable, Sendable {
    case day, week, month

    public var calendarComponent: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }

    public func range(containing date: Date, calendar: Calendar = .current) -> DateInterval? {
        calendar.dateInterval(of: calendarComponent, for: date)
    }
}

public enum ActivityIntervalEdge: Sendable {
    case start, end
}

public enum ActivityTimeline {
    /// Resize only an actual endpoint visible in this day, leaving neighbouring records untouched.
    public static func resizing(
        _ interval: ActivityIntervalSnapshot, edge: ActivityIntervalEdge, to requested: Date,
        in day: DateInterval, among intervals: [ActivityIntervalSnapshot], now: Date
    ) throws -> ActivityIntervalSnapshot {
        var result = interval
        let end = interval.end ?? now
        let minimumDuration = min(60, end.timeIntervalSince(interval.start))
        guard minimumDuration > 0 else { throw ActivityValidationError.invalidRange }
        let snapped = Date(timeIntervalSinceReferenceDate: (requested.timeIntervalSinceReferenceDate / 60).rounded() * 60)
        switch edge {
        case .start:
            guard interval.start >= day.start, interval.start < day.end else { throw ActivityValidationError.invalidRange }
            if requested == interval.start { return interval }
            let previousEnd = intervals.filter { $0.id != interval.id }
                .compactMap(\.end).filter { $0 <= interval.start }.max() ?? day.start
            let lower = max(day.start, previousEnd)
            let upper = min(min(day.end, now), end.addingTimeInterval(-minimumDuration))
            guard upper >= lower else { throw ActivityValidationError.invalidRange }
            result.start = min(max(snapped, lower), upper)
        case .end:
            guard let savedEnd = interval.end, savedEnd > day.start, savedEnd <= day.end else {
                throw ActivityValidationError.invalidRange
            }
            if requested == savedEnd { return interval }
            let nextStart = intervals.filter { $0.id != interval.id && $0.start >= savedEnd }
                .map(\.start).min() ?? day.end
            let lower = max(day.start, interval.start.addingTimeInterval(minimumDuration))
            let upper = min(min(day.end, now), nextStart)
            guard upper >= lower else { throw ActivityValidationError.invalidRange }
            result.end = min(max(snapped, lower), upper)
        }
        try validate(result, among: intervals, now: now)
        return result
    }

    public static func validate(
        _ candidate: ActivityIntervalSnapshot,
        among intervals: [ActivityIntervalSnapshot],
        now: Date
    ) throws {
        guard candidate.start <= now, candidate.end.map({ $0 <= now }) ?? true else {
            throw ActivityValidationError.futureTime
        }
        guard candidate.end.map({ $0 > candidate.start }) ?? true else {
            throw ActivityValidationError.invalidRange
        }
        let end = candidate.end ?? .distantFuture
        guard !intervals.contains(where: {
            $0.id != candidate.id && candidate.start < ($0.end ?? .distantFuture) && $0.start < end
        }) else {
            throw ActivityValidationError.overlap
        }
    }

    public static func split(
        _ interval: ActivityIntervalSnapshot, at date: Date, now: Date
    ) throws -> (ActivityIntervalSnapshot, ActivityIntervalSnapshot) {
        guard date > interval.start, date < (interval.end ?? now) else {
            throw ActivityValidationError.invalidSplit
        }
        var first = interval
        first.end = date
        let second = ActivityIntervalSnapshot(categoryID: interval.categoryID, start: date, end: interval.end)
        return (first, second)
    }

    // Calendar boundaries preserve real durations on 23- and 25-hour days.
    public static func segments(
        on day: Date, intervals: [ActivityIntervalSnapshot], now: Date,
        calendar: Calendar = .current
    ) -> [ActivityDaySegment] {
        guard let dayRange = calendar.dateInterval(of: .day, for: day) else { return [] }
        return segments(in: dayRange, intervals: intervals, now: now)
    }

    // Clip to the selected calendar period and exclude time that has not elapsed yet.
    public static func segments(
        in range: DateInterval, intervals: [ActivityIntervalSnapshot], now: Date
    ) -> [ActivityDaySegment] {
        let end = min(range.end, now)
        guard end > range.start else { return [] }
        var result: [ActivityDaySegment] = []
        var cursor = range.start
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            let start = max(cursor, interval.start)
            let finish = min(end, interval.end ?? now)
            guard finish > start else { continue }
            if start > cursor {
                result.append(.init(intervalID: nil, categoryID: nil, start: cursor, end: start))
            }
            result.append(.init(intervalID: interval.id, categoryID: interval.categoryID, start: start, end: finish))
            cursor = finish
        }
        if cursor < end {
            result.append(.init(intervalID: nil, categoryID: nil, start: cursor, end: end))
        }
        return result
    }

    public static func totals(for segments: [ActivityDaySegment]) -> [UUID: TimeInterval] {
        segments.reduce(into: [:]) { result, segment in
            if let categoryID = segment.categoryID {
                result[categoryID, default: 0] += segment.duration
            }
        }
    }
}
