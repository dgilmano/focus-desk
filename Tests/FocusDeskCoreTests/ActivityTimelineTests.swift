import XCTest
@testable import FocusDeskCore

final class ActivityTimelineTests: XCTestCase {
    private let work = UUID()
    private let rest = UUID()
    private let origin = Date(timeIntervalSince1970: 1_700_006_400)
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }

    func testAdjacentIntervalsAreAllowedButOverlapAndSecondActiveAreRejected() throws {
        let now = origin.addingTimeInterval(7200)
        let existing = ActivityIntervalSnapshot(categoryID: work, start: origin, end: origin.addingTimeInterval(3600))
        let adjacent = ActivityIntervalSnapshot(categoryID: rest, start: existing.end!)
        XCTAssertNoThrow(try ActivityTimeline.validate(adjacent, among: [existing], now: now))
        let overlap = ActivityIntervalSnapshot(categoryID: rest, start: origin.addingTimeInterval(60), end: now)
        XCTAssertThrowsError(try ActivityTimeline.validate(overlap, among: [existing], now: now)) {
            XCTAssertEqual($0 as? ActivityValidationError, .overlap)
        }
        XCTAssertThrowsError(try ActivityTimeline.validate(.init(categoryID: work, start: now), among: [adjacent], now: now))
        XCTAssertNoThrow(try ActivityTimeline.validate(existing, among: [existing], now: now))
    }

    func testInvalidAndFutureTimesAreRejected() {
        let now = origin.addingTimeInterval(3600)
        XCTAssertThrowsError(try ActivityTimeline.validate(.init(categoryID: work, start: now, end: origin), among: [], now: now))
        XCTAssertThrowsError(try ActivityTimeline.validate(.init(categoryID: work, start: origin, end: origin), among: [], now: now))
        XCTAssertThrowsError(try ActivityTimeline.validate(.init(categoryID: work, start: origin, end: now.addingTimeInterval(1)), among: [], now: now))
        XCTAssertThrowsError(try ActivityTimeline.validate(.init(categoryID: work, start: now.addingTimeInterval(1)), among: [], now: now))
    }

    func testDayMapClipsAcrossMidnightAndAccountsForGapsAndLiveTime() {
        let day = calendar.startOfDay(for: origin)
        let now = day.addingTimeInterval(5 * 3600)
        let intervals = [
            ActivityIntervalSnapshot(categoryID: work, start: day.addingTimeInterval(-3600), end: day.addingTimeInterval(3600)),
            ActivityIntervalSnapshot(categoryID: rest, start: day.addingTimeInterval(3 * 3600)),
            ActivityIntervalSnapshot(categoryID: work, start: day.addingTimeInterval(-3 * 3600), end: day)
        ]
        let segments = ActivityTimeline.segments(on: day, intervals: intervals, now: now, calendar: calendar)
        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments[1].categoryID, nil)
        XCTAssertEqual(segments.reduce(0) { $0 + $1.duration }, 5 * 3600)
        XCTAssertEqual(ActivityTimeline.totals(for: segments)[work], 3600)
        XCTAssertEqual(ActivityTimeline.totals(for: segments)[rest], 2 * 3600)
    }

    func testEmptyAndFutureDaysDoNotInventRecordedTime() {
        let day = calendar.startOfDay(for: origin)
        let segments = ActivityTimeline.segments(on: day, intervals: [], now: day.addingTimeInterval(60), calendar: calendar)
        XCTAssertEqual(segments.count, 1)
        XCTAssertNil(segments[0].intervalID)
        XCTAssertEqual(segments[0].duration, 60)
        XCTAssertTrue(ActivityTimeline.segments(on: day.addingTimeInterval(86400), intervals: [], now: day, calendar: calendar).isEmpty)
    }

    func testCalendarDaysRespectDaylightSavingTime() {
        var calendar = self.calendar
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        for (month, day, hours) in [(3, 8, 23), (11, 1, 25)] {
            let date = calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
            let range = calendar.dateInterval(of: .day, for: date)!
            let interval = ActivityIntervalSnapshot(categoryID: work, start: range.start, end: range.end)
            let segments = ActivityTimeline.segments(on: date, intervals: [interval], now: range.end, calendar: calendar)
            XCTAssertEqual(ActivityTimeline.totals(for: segments)[work], Double(hours * 3600))
        }
    }

    func testDailyBalanceMatchesJournalIntervalsWithoutCountingGapsAsRecorded() {
        let day = calendar.startOfDay(for: origin)
        let start = day.addingTimeInterval(9 * 3600)
        let now = day.addingTimeInterval(16 * 3600)
        let study = UUID(), life = UUID(), leisure = UUID(), other = UUID()
        let pieces: [(UUID, Double, Double?)] = [
            (work, 0, 110), (rest, 110, 130), (study, 130, 200),
            (life, 200, 245), (leisure, 245, 275), (other, 275, 285),
            (rest, 315, 330), (work, 330, nil)
        ]
        let intervals = pieces.map { category, from, to in
            ActivityIntervalSnapshot(categoryID: category, start: start.addingTimeInterval(from * 60),
                                     end: to.map { start.addingTimeInterval($0 * 60) })
        }
        let segments = ActivityTimeline.segments(on: day, intervals: intervals, now: now, calendar: calendar)
        let totals = ActivityTimeline.totals(for: segments)
        let expected: [UUID: TimeInterval] = [work: 12000, rest: 2100, study: 4200,
                                              life: 2700, leisure: 1800, other: 600]
        XCTAssertEqual(totals, expected)
        let recorded = totals.values.reduce(0, +)
        let untracked = segments.filter { $0.intervalID == nil }.reduce(0) { $0 + $1.duration }
        XCTAssertEqual(recorded, 390 * 60)
        XCTAssertEqual(untracked, (9 * 60 + 30) * 60)
        XCTAssertEqual(recorded + untracked, now.timeIntervalSince(day))
        XCTAssertEqual(segments.last?.intervalID, intervals.last?.id)
        XCTAssertEqual(segments.last?.end, now)
    }

    func testSplitPreservesDurationAndOnlySecondHalfCanRemainRunning() throws {
        let now = origin.addingTimeInterval(3600)
        for end in [now, nil] {
            let source = ActivityIntervalSnapshot(categoryID: work, start: origin, end: end)
            let (first, second) = try ActivityTimeline.split(source, at: origin.addingTimeInterval(1200), now: now)
            XCTAssertEqual(first.id, source.id)
            XCTAssertNotEqual(second.id, source.id)
            XCTAssertEqual(first.end, second.start)
            XCTAssertEqual(second.end, end)
            XCTAssertNoThrow(try ActivityTimeline.validate(second, among: [first], now: now))
            XCTAssertEqual(first.end!.timeIntervalSince(first.start) + (second.end ?? now).timeIntervalSince(second.start), 3600)
            XCTAssertThrowsError(try ActivityTimeline.split(source, at: origin, now: now))
            XCTAssertThrowsError(try ActivityTimeline.split(source, at: now, now: now))
        }
    }
}
