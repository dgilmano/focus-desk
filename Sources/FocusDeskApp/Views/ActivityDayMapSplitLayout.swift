import Foundation

struct ActivityDayMapSplitLayout {
    static let defaultProportion = 0.6
    static let gutter: CGFloat = 49
    private static let minimumTimelineWidth: CGFloat = 320
    private static let minimumBalanceWidth: CGFloat = 220

    let availableWidth: CGFloat
    let proportion: Double

    var isHorizontal: Bool { availableWidth >= 650 }
    private var paneWidth: CGFloat { max(0, availableWidth - Self.gutter) }

    var timelineWidth: CGFloat {
        guard isHorizontal else { return max(0, availableWidth) }
        let value = proportion.isFinite ? proportion : Self.defaultProportion
        return clampedTimelineWidth(paneWidth * value)
    }

    var balanceWidth: CGFloat {
        isHorizontal ? paneWidth - timelineWidth : max(0, availableWidth)
    }

    func proportion(forTimelineWidth width: CGFloat) -> Double {
        guard isHorizontal else { return proportion }
        return clampedTimelineWidth(width) / paneWidth
    }

    private func clampedTimelineWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, Self.minimumTimelineWidth), paneWidth - Self.minimumBalanceWidth)
    }
}
