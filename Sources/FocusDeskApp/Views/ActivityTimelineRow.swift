import FocusDeskCore
import SwiftUI

struct ActivityTimelineRow: View {
    var isSelected: Bool
    var onSelect: () -> Void
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

            intervalContent
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(background, in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.7) : .clear, lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onSelect()
            onEdit()
        }
        // Select on press without waiting for the double-click recognition window.
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in
            if !isSelected { onSelect() }
        })
        .help("Click to select · double-click to edit")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction { onSelect() }
        .accessibilityAction(named: "Edit interval") { onSelect(); onEdit() }
        .contextMenu {
            Button(segment.intervalID == nil ? "Fill untracked time" : "Edit interval…", action: onEdit)
        }
        .onHover { isHovered = $0 }
    }

    private var intervalContent: some View {
        HStack(spacing: 9) {
            Image(systemName: category?.symbol ?? "circle")
                .font(.system(size: 15)).foregroundStyle(accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.system(size: 12)).lineLimit(1)
                if let taskTitle {
                    Text(taskTitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                if !showsInlineRange {
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
            // Reserve the same trailing space for gaps, running and completed intervals.
            ZStack {
                Color.clear
                if isActive {
                    Circle().fill(accent).frame(width: 6, height: 6)
                        .accessibilityLabel("Activity is running")
                }
            }
            .frame(width: 16, height: 24)
        }
    }

    private var background: Color {
        if isSelected { return Color.accentColor.opacity(0.1) }
        if isActive { return accent.opacity(0.1) }
        if isHovered { return FocusDeskStyle.focusSurface }
        return .clear
    }

    private var timeRange: some View {
        Text("\(start) - \(end)")
            .font(.system(size: 10)).foregroundStyle(.secondary)
            .monospacedDigit().lineLimit(1)
    }
}
