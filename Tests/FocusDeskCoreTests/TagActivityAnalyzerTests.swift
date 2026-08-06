import XCTest
@testable import FocusDeskCore

final class TagActivityAnalyzerTests: XCTestCase {
    func testSummariesSplitEstimatedTimeAcrossMultipleTags() {
        let taskID = UUID()
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let analyzer = TagActivityAnalyzer(defaultStepMinutes: 30, maxStepIntervalMinutes: 90)
        let interval = DateInterval(start: start, duration: 60 * 60 * 24)
        let events = [
            TagActivityEvent(
                taskID: taskID,
                taskTitle: "Design",
                tags: [
                    TaskTagRecord(name: "Product", colorName: "blue"),
                    TaskTagRecord(name: "Design", colorName: "purple")
                ],
                timestamp: start.addingTimeInterval(60 * 30)
            )
        ]

        let summaries = analyzer.summaries(for: events, in: interval)

        XCTAssertEqual(summaries.count, 2)
        XCTAssertEqual(summaries.map(\.name).sorted(), ["Design", "Product"])
        XCTAssertTrue(summaries.allSatisfy { $0.estimatedMinutes == 15 })
        XCTAssertTrue(summaries.allSatisfy { $0.journalStepCount == 1 })
        XCTAssertTrue(summaries.allSatisfy { $0.taskCount == 1 })
    }

    func testSummariesCapLongGapsAndGroupUntaggedActivity() {
        let firstTaskID = UUID()
        let secondTaskID = UUID()
        let start = Date(timeIntervalSinceReferenceDate: 2_000)
        let analyzer = TagActivityAnalyzer(defaultStepMinutes: 25, maxStepIntervalMinutes: 60)
        let interval = DateInterval(start: start, duration: 60 * 60 * 24)
        let events = [
            TagActivityEvent(
                taskID: firstTaskID,
                taskTitle: "Inbox",
                tags: [],
                timestamp: start.addingTimeInterval(60 * 10)
            ),
            TagActivityEvent(
                taskID: secondTaskID,
                taskTitle: "Planning",
                tags: [],
                timestamp: start.addingTimeInterval(60 * 180)
            )
        ]

        let summary = analyzer.summaries(for: events, in: interval).first

        XCTAssertEqual(summary?.name, "Untagged")
        XCTAssertEqual(summary?.estimatedMinutes, 85)
        XCTAssertEqual(summary?.journalStepCount, 2)
        XCTAssertEqual(summary?.taskCount, 2)
    }

    func testSummariesIgnoreEventsOutsideInterval() {
        let taskID = UUID()
        let start = Date(timeIntervalSinceReferenceDate: 3_000)
        let analyzer = TagActivityAnalyzer(defaultStepMinutes: 25, maxStepIntervalMinutes: 60)
        let interval = DateInterval(start: start, duration: 60 * 60)
        let events = [
            TagActivityEvent(
                taskID: taskID,
                taskTitle: "Old",
                tags: [TaskTagRecord(name: "Archive", colorName: "brown")],
                timestamp: start.addingTimeInterval(-60)
            )
        ]

        XCTAssertTrue(analyzer.summaries(for: events, in: interval).isEmpty)
    }
}
