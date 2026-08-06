import XCTest
@testable import FocusDeskCore

final class DeskRouterTests: XCTestCase {
    private let router = DeskRouter()

    func testNextTaskSkipsCompletedAndWraps() {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()

        let tasks = [
            TaskSnapshot(id: firstID, title: "First", carouselOrder: 0),
            TaskSnapshot(id: secondID, title: "Done", carouselOrder: 1, completedAt: Date()),
            TaskSnapshot(id: thirdID, title: "Third", carouselOrder: 2)
        ]

        XCTAssertEqual(router.nextTask(in: tasks, after: firstID)?.id, thirdID)
        XCTAssertEqual(router.nextTask(in: tasks, after: thirdID)?.id, firstID)
    }

    func testPreviousTaskSkipsCompletedAndWraps() {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()

        let tasks = [
            TaskSnapshot(id: firstID, title: "First", carouselOrder: 0),
            TaskSnapshot(id: secondID, title: "Done", carouselOrder: 1, completedAt: Date()),
            TaskSnapshot(id: thirdID, title: "Third", carouselOrder: 2)
        ]

        XCTAssertEqual(router.previousTask(in: tasks, before: firstID)?.id, thirdID)
        XCTAssertEqual(router.previousTask(in: tasks, before: thirdID)?.id, firstID)
    }

    func testCurrentTaskFallsBackWhenSelectionIsMissingOrCompleted() {
        let firstID = UUID()
        let completedID = UUID()

        let tasks = [
            TaskSnapshot(id: firstID, title: "First", carouselOrder: 0),
            TaskSnapshot(id: completedID, title: "Done", carouselOrder: 1, completedAt: Date())
        ]

        XCTAssertEqual(router.currentTask(in: tasks, selectedID: nil)?.id, firstID)
        XCTAssertEqual(router.currentTask(in: tasks, selectedID: completedID)?.id, firstID)
    }

    func testActiveTasksUseCreatedAtAsStableTieBreaker() {
        let later = Date(timeIntervalSince1970: 20)
        let earlier = Date(timeIntervalSince1970: 10)

        let tasks = [
            TaskSnapshot(title: "Later", carouselOrder: 0, createdAt: later),
            TaskSnapshot(title: "Earlier", carouselOrder: 0, createdAt: earlier)
        ]

        XCTAssertEqual(router.activeTasks(from: tasks).map(\.title), ["Earlier", "Later"])
    }

    func testHTTPDateHeaderParsingSupportsServerTimeBoundary() {
        let date = HTTPDateHeaderServerClock.date(
            fromHTTPDateHeader: "Sun, 02 Aug 2026 20:01:00 GMT"
        )

        XCTAssertEqual(date?.timeIntervalSince1970, 1785700860)
    }

    func testMarkdownFormattingPreservesReadableTaskListLayout() {
        let markdown = """
        Next:
        - **Call** client
        - `Ship` patch
        """

        let rendered = MarkdownFormatting.attributedString(from: markdown)

        XCTAssertEqual(
            String(rendered.characters),
            """
            Next:
            - Call client
            - Ship patch
            """
        )
    }

    func testTaskTagCodingRoundTripsSortedTags() throws {
        let second = TaskTagRecord(name: "BGP", colorName: "pink", sortOrder: 2)
        let first = TaskTagRecord(name: "General", colorName: "gray", isEnabled: false, sortOrder: 1)

        let encoded = try XCTUnwrap(TaskTagCoding.encode([second, first]))
        let decoded = TaskTagCoding.decode(encoded)

        XCTAssertEqual(decoded.map(\.name), ["General", "BGP"])
        XCTAssertEqual(decoded.first?.colorName, "gray")
        XCTAssertEqual(decoded.first?.isEnabled, false)
    }
}
