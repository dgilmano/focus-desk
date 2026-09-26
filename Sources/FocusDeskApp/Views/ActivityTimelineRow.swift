import AppKit
import FocusDeskCore
import SwiftUI

struct ActivityTimelineRow: View {
    @Environment(ActivityStore.self) private var store
    @Binding var editingTimeID: UUID?
    var segment: ActivityDaySegment
    var category: ActivityCategory?
    var taskTitle: String?
    var isActive: Bool
    var isFirst: Bool
    var isLast: Bool
    var dayEnd: Date
    var showsInlineRange: Bool
    var rowHeight: CGFloat = 48
    var canResizeStart = false
    var canResizeEnd = false
    var isResizing = false
    var onResize: (ActivityIntervalEdge, CGFloat) -> Void = { _, _ in }
    var onResizeEnded: () -> Void = {}
    var onResizeCancelled: () -> Void = {}
    var onEdit: () -> Void
    @State private var isHovered = false
    @State private var timeDraft: ActivityIntervalSnapshot?

    private var accent: Color { ActivityAppearance.accent(category?.colorName ?? "gray") }
    private var name: String { category?.name ?? "Untracked" }
    private var start: String { ActivityTimeText.clock(segment.start, dayEnd: dayEnd) }
    private var end: String { isActive ? "Now" : ActivityTimeText.clock(segment.end, dayEnd: dayEnd) }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: editTime) {
                Text(start)
                    .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .leading)
            }
            .help("Edit start and end time")

            ZStack {
                Rectangle().fill(accent.opacity(0.45)).frame(width: 2)
                    .padding(.top, isFirst ? 24 : 0)
                    .padding(.bottom, isLast ? 24 : 0)
                Circle().fill(accent).frame(width: 8, height: 8)
                    .background { Circle().fill(ActivityAppearance.canvas).frame(width: 12, height: 12) }
            }
            .frame(width: 12, height: rowHeight)
            .accessibilityHidden(true)

            Group {
                if let timeDraft {
                    ActivityInlineTimeEditor(original: timeDraft) {
                        self.timeDraft = nil
                        editingTimeID = nil
                    }
                } else {
                    intervalContent
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: max(44, rowHeight - 4))
            .background(background, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(segment.intervalID == nil ? "Fill untracked time" : "Edit interval…", action: onEdit)
        }
        .onHover { isHovered = $0 }
        .onChange(of: editingTimeID) {
            if editingTimeID != segment.intervalID { timeDraft = nil }
        }
        .overlay(alignment: .top) {
            if canResizeStart && timeDraft == nil { resizeHandle(.start) }
        }
        .overlay(alignment: .bottom) {
            if canResizeEnd && timeDraft == nil { resizeHandle(.end) }
        }
    }

    private var intervalContent: some View {
        HStack(spacing: 9) {
            Image(systemName: category?.symbol ?? "circle")
                .font(.system(size: 15)).foregroundStyle(accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                activityName
                if let taskTitle, let id = segment.intervalID {
                    ActivityIntervalTaskMenu(intervalID: id, title: taskTitle)
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
            if segment.intervalID == nil {
                Button(action: onEdit) {
                    Image(systemName: "plus")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .opacity(isHovered ? 1 : 0)
                        .frame(width: 16, height: 24)
                }
                .help("Fill untracked time")
                .accessibilityLabel("Fill untracked time")
            } else if isActive {
                Circle().fill(accent).frame(width: 6, height: 6)
                    .accessibilityLabel("Activity is running")
            }
        }
    }

    @ViewBuilder private var activityName: some View {
        if let id = segment.intervalID {
            Menu {
                ForEach(store.categories.filter { !$0.isArchived || $0.id == category?.id }) { choice in
                    Button {
                        guard let record = store.interval(id), record.categoryID != choice.id else { return }
                        _ = store.saveInterval(id: id, categoryID: choice.id, start: record.startedAt,
                                               end: record.endedAt, taskID: record.taskID, taskTitle: record.taskTitle)
                    } label: {
                        Label(choice.name, systemImage: choice.id == category?.id ? "checkmark" : choice.symbol)
                    }
                }
            } label: {
                Text(name).font(.system(size: 12)).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("Change activity for this interval")
            .accessibilityLabel("Activity: \(name)")
        } else {
            Button(action: onEdit) { Text(name).font(.system(size: 12)).lineLimit(1) }
        }
    }

    private func editTime() {
        guard let id = segment.intervalID, let record = store.interval(id) else { onEdit(); return }
        timeDraft = record.snapshot
        editingTimeID = id
    }

    private var background: Color {
        if isActive || isResizing { return accent.opacity(0.1) }
        if isHovered { return FocusDeskStyle.focusSurface }
        return segment.intervalID == nil ? .clear : accent.opacity(0.04)
    }

    private func resizeHandle(_ edge: ActivityIntervalEdge) -> some View {
        ActivityIntervalResizeHandle(
            title: edge == .start ? "Adjust start time" : "Adjust end time",
            value: edge == .start ? start : end,
            accent: accent, emphasized: isHovered || isResizing,
            onChange: { onResize(edge, $0) }, onEnd: onResizeEnded, onCancel: onResizeCancelled
        )
        .padding(.leading, 76)
    }

    private var timeRange: some View {
        Button(action: editTime) {
            Text("\(start) - \(end)")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .monospacedDigit().lineLimit(1)
        }
        .help("Edit start and end time")
        .accessibilityLabel("Edit time: \(start) to \(end)")
    }
}

private struct ActivityIntervalResizeHandle: View {
    var title: String
    var value: String
    var accent: Color
    var emphasized: Bool
    var onChange: (CGFloat) -> Void
    var onEnd: () -> Void
    var onCancel: () -> Void
    @State private var isHovered = false
    @GestureState private var isDragging = false

    var body: some View {
        Rectangle().fill(Color.primary.opacity(0.001))
            .frame(height: 12)
            .overlay {
                Capsule().fill(accent.opacity(isHovered || emphasized ? 0.8 : 0.3))
                    .frame(width: 28, height: 3)
            }
            .contentShape(Rectangle())
            .onHover { hovered in
                guard hovered != isHovered else { return }
                isHovered = hovered
                if hovered { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .updating($isDragging) { _, active, _ in active = true }
                .onChanged { onChange($0.translation.height) }
                .onEnded { _ in onEnd() })
            .onChange(of: isDragging) { if !isDragging { onCancel() } }
            .onDisappear {
                if isHovered { NSCursor.pop(); isHovered = false }
                if isDragging { onCancel() }
            }
            .help("\(title) · drag to resize, one-minute steps")
            .accessibilityElement()
            .accessibilityLabel(title)
            .accessibilityValue(value)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: onChange(1.5)
                case .decrement: onChange(-1.5)
                @unknown default: return
                }
                onEnd()
            }
    }
}
