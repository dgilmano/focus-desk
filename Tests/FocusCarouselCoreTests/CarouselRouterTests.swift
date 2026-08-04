import XCTest
@testable import FocusCarouselCore

final class CarouselRouterTests: XCTestCase {
    private let router = CarouselRouter()

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
}
