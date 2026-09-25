import FocusDeskCore
import SwiftUI

struct ActivityTimelineRow: View {
    var segment: ActivityDaySegment
    var category: ActivityCategory?
    var taskTitle: String?
    var isActive: Bool
    var isFirst: Bool
    var isLast: Bool
    var dayEnd: Date
    var showsInlineRange: Bool
    var onEdit: () -> Void
    @State private var isHovered = false

    private var accent: Color { ActivityAppearance.accent(category?.colorName ?? "gray") }
    private var name: String { category?.name ?? "Untracked" }
    private var start: String { ActivityTimeText.clock(segment.start, dayEnd: dayEnd) }
    private var end: String { isActive ? "Now" : ActivityTimeText.clock(segment.end, dayEnd: dayEnd) }

    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: 8) {
                Text(start)
                    .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .leading)

                ZStack {
                    Rectangle().fill(accent.opacity(0.45)).frame(width: 2)
                        .padding(.top, isFirst ? 24 : 0)
                        .padding(.bottom, isLast ? 24 : 0)
                    Circle().fill(accent).frame(width: 8, height: 8)
                        .background { Circle().fill(ActivityAppearance.canvas).frame(width: 12, height: 12) }
                }
                .frame(width: 12, height: 48)
                .accessibilityHidden(true)

                HStack(spacing: 9) {
                    Image(systemName: category?.symbol ?? "circle")
                        .font(.system(size: 15)).foregroundStyle(accent)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name).font(.system(size: 12)).lineLimit(1)
                        if showsInlineRange, let taskTitle {
                            Text(taskTitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                        } else if !showsInlineRange {
                            timeRange
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if showsInlineRange {
                        timeRange.frame(width: 108, alignment: .leading)
                    }
                    Text(ActivityTimeText.duration(segment.duration))
                        .font(.system(size: 11, weight: isActive ? .medium : .regular))
                        .monospacedDigit().fixedSize()
                        .frame(width: 74, alignment: .trailing)
                    ZStack {
                        Image(systemName: segment.intervalID == nil ? "plus" : "pencil")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .opacity(isHovered ? 1 : 0)
                        Circle().fill(accent).frame(width: 6, height: 6)
                            .opacity(isActive && !isHovered ? 1 : 0)
                    }
                    .frame(width: 16, height: 24)
                }
                .padding(.horizontal, 8)
                .frame(height: 44)
                .background(background, in: RoundedRectangle(cornerRadius: 5))
                .overlay(alignment: .bottom) {
                    if !isActive && !isHovered && !isLast {
                        Rectangle().fill(FocusDeskStyle.hairline).frame(height: 0.5)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help([name, taskTitle, segment.intervalID == nil ? "Fill untracked time" : "Edit interval"]
            .compactMap { $0 }.joined(separator: "\n"))
        .accessibilityLabel("\(name), \(start) to \(end), \(ActivityTimeText.duration(segment.duration))")
        .accessibilityValue(isActive ? "Active" : "")
        .accessibilityHint(segment.intervalID == nil ? "Fill untracked time" : "Edit interval")
    }

    private var background: Color {
        if isActive { return accent.opacity(0.08) }
        return isHovered ? FocusDeskStyle.focusSurface : .clear
    }

    private var timeRange: some View {
        Text("\(start) - \(end)")
            .font(.system(size: 10)).foregroundStyle(.secondary)
            .monospacedDigit().lineLimit(1)
    }
}
