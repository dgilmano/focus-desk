import XCTest
@testable import FocusDesk

final class ActivityDayMapSplitLayoutTests: XCTestCase {
    func testDefaultColumnsFillAvailableWidth() {
        let layout = ActivityDayMapSplitLayout(availableWidth: 1000, proportion: 0.6)
        XCTAssertTrue(layout.isHorizontal)
        XCTAssertEqual(layout.timelineWidth, 951 * 0.6, accuracy: 0.001)
        XCTAssertEqual(layout.timelineWidth + layout.balanceWidth + ActivityDayMapSplitLayout.gutter, 1000)
    }

    func testDraggingResizesBothColumnsAndStopsAtReadableWidths() {
        let layout = ActivityDayMapSplitLayout(availableWidth: 1000, proportion: 0.6)
        for target in [-100.0, 320, 460, 731, 2000] {
            let moved = ActivityDayMapSplitLayout(availableWidth: 1000,
                                                proportion: layout.proportion(forTimelineWidth: target))
            XCTAssertEqual(moved.timelineWidth, min(max(target, 320), 731), accuracy: 0.001)
            XCTAssertGreaterThanOrEqual(moved.timelineWidth, 320)
            XCTAssertGreaterThanOrEqual(moved.balanceWidth, 220)
            XCTAssertEqual(moved.timelineWidth + moved.balanceWidth, 951, accuracy: 0.001)
        }
    }

    func testWindowResizeClampsWithoutChangingPreferredProportion() {
        let narrow = ActivityDayMapSplitLayout(availableWidth: 650, proportion: 0.8)
        XCTAssertEqual(narrow.balanceWidth, 220, accuracy: 0.001)
        XCTAssertEqual(narrow.proportion, 0.8)
        let wide = ActivityDayMapSplitLayout(availableWidth: 1400, proportion: narrow.proportion)
        XCTAssertEqual(wide.timelineWidth, 1351 * 0.8, accuracy: 0.001)
    }

    func testCompactLayoutUsesFullWidthForBothSections() {
        let layout = ActivityDayMapSplitLayout(availableWidth: 649, proportion: 0.7)
        XCTAssertFalse(layout.isHorizontal)
        XCTAssertEqual(layout.timelineWidth, 649)
        XCTAssertEqual(layout.balanceWidth, 649)
        XCTAssertEqual(layout.proportion(forTimelineWidth: 400), 0.7)
    }

    func testInvalidPreferenceFallsBackToDefault() {
        let layout = ActivityDayMapSplitLayout(availableWidth: 1000, proportion: .nan)
        XCTAssertEqual(layout.timelineWidth, 951 * ActivityDayMapSplitLayout.defaultProportion, accuracy: 0.001)
    }
}
