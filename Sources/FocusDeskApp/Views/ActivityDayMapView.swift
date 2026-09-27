import AppKit
import FocusDeskCore
import SwiftData
import SwiftUI

private struct ActivityIntervalDraft: Identifiable {
    var id = UUID()
    var intervalID: UUID?
    var categoryID: UUID
    var start: Date
    var end: Date
    var isRunning = false
    var taskID: UUID?
    var taskTitle: String?
}

struct ActivityDayMapView: View {
    @Environment(ActivityStore.self) private var store
    @Binding var selectedDate: Date?
    @State private var draft: ActivityIntervalDraft?
    @State private var showingSettings = false
    @AppStorage("dayMapTimelineProportion") private var timelineProportion = ActivityDayMapSplitLayout.defaultProportion
    @State private var dividerDragStartWidth: CGFloat?
    @State private var isDividerHovered = false
    @State private var selectedSegmentID: String?
    var now: Date
    var availableWidth: CGFloat

    // Store changes can arrive between TimelineView ticks (for example, a newly started activity).
    private var liveNow: Date { max(now, Date()) }
    private var day: Date { selectedDate ?? liveNow }
    private var dayRange: DateInterval { Calendar.current.dateInterval(of: .day, for: day)! }
    private var trackingButtonWidth: CGFloat {
        ActivityPaletteLayout.cardWidth(availableWidth: availableWidth, categoryCount: store.availableCategories.count)
    }
    private var stopTrackingColor: Color {
        ActivityAppearance.accent(store.categories.first { $0.name.caseInsensitiveCompare("Leisure") == .orderedSame }?.colorName ?? "pink")
    }
    var body: some View {
        let segments = ActivityTimeline.trackedSegments(in: dayRange, intervals: store.snapshots,
                                                        windows: store.trackingWindows(now: liveNow), now: liveNow)
        let layout = ActivityDayMapSplitLayout(availableWidth: availableWidth, proportion: timelineProportion)
        VStack(alignment: .leading, spacing: 16) {
            timelineHeader
                .padding(.bottom, 8)
            VStack(alignment: .leading, spacing: 12) {
                ActivityPaletteView(availableWidth: availableWidth)
                Rectangle()
                    .fill(FocusDeskStyle.hairline)
                    .frame(height: 1)
            }
            .padding(.bottom, 12)

            if let notice = store.notice, Calendar.current.isDate(day, inSameDayAs: liveNow) {
                Text(notice).font(.system(size: 12)).foregroundStyle(.secondary)
            }

            if layout.isHorizontal {
                HStack(alignment: .top, spacing: ActivityDayMapSplitLayout.gutter) {
                    timeline(segments, width: layout.timelineWidth)
                        .frame(width: layout.timelineWidth)
                    balance
                        .frame(width: layout.balanceWidth)
                }
                .overlay(alignment: .leading) {
                    columnDivider(layout)
                        .offset(x: layout.timelineWidth + ActivityDayMapSplitLayout.gutter / 2 - 7)
                }
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    timeline(segments, width: availableWidth)
                    Divider()
                    balance
                }
            }

            if let error = store.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(item: $draft) { value in
            ActivityIntervalEditor(draft: value)
        }
        .sheet(isPresented: $showingSettings) { ActivityCategoriesView() }
        .onChange(of: dayRange.start) { selectedSegmentID = nil }
    }

    private var timelineHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Day timeline").font(.system(size: 17, weight: .semibold))
                Spacer()

            }
            .frame(height: 28)

            if Calendar.current.isDate(day, inSameDayAs: liveNow) {
                VStack(alignment: .leading, spacing: 24) {
                    if store.activeTrackingSession != nil {
                        Label {
                            Text("Tracking started")
                        } icon: {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.green)
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 12)
                        .frame(width: trackingButtonWidth, height: 44, alignment: .leading)
                        .background(FocusDeskStyle.focusSurface, in: RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(FocusDeskStyle.hairline, lineWidth: 1)
                        }
                        .accessibilityLabel("Tracking started")
                    } else {
                        Button { _ = store.startTracking() } label: {
                            Label("Start tracking", systemImage: "play.fill")
                        }
                        .buttonStyle(ActivityTrackingButtonStyle(tint: .blue, width: trackingButtonWidth))
                        .help("Start your day, then choose an activity")
                    }
                    ActivityTrackingStatus()
                        .padding(.leading, 12)
                }
            }

        }
    }

    private func columnDivider(_ layout: ActivityDayMapSplitLayout) -> some View {
        Rectangle()
            .fill(Color.primary.opacity(0.001))
            .frame(width: 14)
            .overlay {
                Rectangle()
                    .fill(isDividerHovered || dividerDragStartWidth != nil ? Color.secondary : FocusDeskStyle.hairline)
                    .frame(width: 1)
            }
            .contentShape(Rectangle())
            .onHover { hovered in
                guard hovered != isDividerHovered else { return }
                isDividerHovered = hovered
                if hovered { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .highPriorityGesture(
                // Global coordinates keep the drag stable while the divider itself moves.
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        if dividerDragStartWidth == nil { dividerDragStartWidth = layout.timelineWidth }
                        let width = (dividerDragStartWidth ?? layout.timelineWidth) + value.translation.width
                        timelineProportion = layout.proportion(forTimelineWidth: width)
                    }
                    .onEnded { _ in dividerDragStartWidth = nil }
            )
            .onDisappear {
                dividerDragStartWidth = nil
                if isDividerHovered {
                    NSCursor.pop()
                    isDividerHovered = false
                }
            }
            .help("Resize columns")
            .accessibilityElement()
            .accessibilityLabel("Resize Day timeline and Daily balance")
            .accessibilityValue("\(Int(layout.proportion(forTimelineWidth: layout.timelineWidth) * 100)) percent timeline")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    timelineProportion = layout.proportion(forTimelineWidth: layout.timelineWidth + 24)
                case .decrement:
                    timelineProportion = layout.proportion(forTimelineWidth: layout.timelineWidth - 24)
                @unknown default: break
                }
            }
    }

    private func timeline(_ segments: [ActivityDaySegment], width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !segments.contains(where: { $0.intervalID != nil }) {
                Text("No activity recorded for this day.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }

            VStack(spacing: 0) {
                // Keep the row identity stable while its time is edited.
                ForEach(segments, id: \.timelineIdentity) { segment in
                    let record = segment.intervalID.flatMap { store.interval($0) }
                    let isActive = record != nil && record?.endedAt == nil && Calendar.current.isDate(day, inSameDayAs: liveNow)
                    ActivityTimelineRow(
                        isSelected: selectedSegmentID == segment.timelineIdentity,
                        onSelect: { selectedSegmentID = segment.timelineIdentity },
                        segment: segment, category: store.category(segment.categoryID),
                        taskTitle: record?.taskTitle, isActive: isActive,
                        isFirst: segment.id == segments.first?.id,
                        isLast: segment.id == segments.last?.id, dayEnd: dayRange.end,
                        showsInlineRange: width >= 480,
                        onEdit: { edit(segment) }
                    )
                }
            }
            if Calendar.current.isDate(day, inSameDayAs: liveNow) {
                Button { _ = store.stopTracking() } label: {
                    Label("Stop tracking", systemImage: "stop.fill")
                }
                .buttonStyle(ActivityTrackingButtonStyle(tint: stopTrackingColor, width: trackingButtonWidth))
                .disabled(store.activeTrackingSession == nil && store.activeInterval == nil)
            }
            if let active = store.activeTrackingSession, Calendar.current.isDate(day, inSameDayAs: liveNow) {
                Text("Tracking since \(active.startedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else if let last = store.trackingSessions.last(where: {
                $0.startedAt < dayRange.end && ($0.endedAt ?? liveNow) > dayRange.start
            }), let end = last.endedAt {
                Text("Tracking stopped at \(end.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }

        }
    }

    private var balance: some View {
        ActivityDayBalanceView(categories: store.categories, intervals: store.snapshots,
                               trackingWindows: store.trackingWindows(now: liveNow),
                               selectedDate: $selectedDate, now: liveNow, onSelectInterval: edit)
    }

    private func edit(_ segment: ActivityDaySegment) {
        if let id = segment.intervalID, let record = store.interval(id) {
            draft = .init(intervalID: id, categoryID: record.categoryID, start: record.startedAt,
                          end: record.endedAt ?? liveNow, isRunning: record.endedAt == nil,
                          taskID: record.taskID, taskTitle: record.taskTitle)
        } else if let category = store.availableCategories.first {
            draft = .init(categoryID: category.id, start: segment.start, end: segment.end)
        } else {
            showingSettings = true
        }
    }
}

private struct ActivityTrackingButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var tint: Color
    var width: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 12)
            .frame(width: width, height: 44, alignment: .leading)
            .background(isEnabled ? tint.opacity(configuration.isPressed ? 0.8 : 1) : FocusDeskStyle.focusSurface,
                        in: RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(configuration.isPressed || !isEnabled ? 0 : 0.12), radius: 3, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

private extension ActivityDaySegment {
    var timelineIdentity: String {
        intervalID?.uuidString ?? "gap-\(start.timeIntervalSinceReferenceDate)"
    }
}

private struct ActivityIntervalEditor: View {
    @Environment(ActivityStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FocusTask.title) private var tasks: [FocusTask]
    @State var draft: ActivityIntervalDraft
    @State private var splitTime = Date()
    @State private var confirmingDelete = false

    private var availableCategories: [ActivityCategory] {
        store.categories.filter { !$0.isArchived || $0.id == draft.categoryID }
    }
    private var original: ActivityInterval? { draft.intervalID.flatMap { store.interval($0) } }
    private var hasChanges: Bool {
        guard let original else { return true }
        return original.categoryID != draft.categoryID || original.startedAt != draft.start ||
            original.endedAt != (draft.isRunning ? nil : draft.end) || original.taskID != draft.taskID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(draft.intervalID == nil ? "Add interval" : "Edit interval").font(.headline)
            Form {
                Picker("Activity", selection: $draft.categoryID) {
                    ForEach(availableCategories) { category in
                        Label(category.name, systemImage: category.symbol).tag(category.id)
                    }
                }
                DatePicker("From", selection: $draft.start, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                if draft.isRunning {
                    LabeledContent("Until", value: "In progress")
                } else {
                    DatePicker("Until", selection: $draft.end, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                }
                Picker("Task", selection: $draft.taskID) {
                    Text("No task").tag(nil as UUID?)
                    ForEach(tasks) { task in Text(task.title).tag(Optional(task.id)) }
                    if let id = draft.taskID, !tasks.contains(where: { $0.id == id }) {
                        Text(draft.taskTitle ?? "Deleted task").tag(Optional(id))
                    }
                }
            }
            if let id = draft.intervalID {
                Divider()
                HStack {
                    DatePicker("Split at", selection: $splitTime, displayedComponents: [.date, .hourAndMinute])
                    ActivityIconButton(symbol: "scissors", title: hasChanges ? "Save changes before splitting" : "Split interval") {
                        if store.splitInterval(id, at: splitTime) { dismiss() }
                    }
                    .disabled(hasChanges || splitTime <= draft.start || splitTime >= (draft.isRunning ? Date() : draft.end))
                }
            }
            if let error = store.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if draft.intervalID != nil {
                    ActivityIconButton(symbol: "trash", title: "Delete interval") { confirmingDelete = true }
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    let title = tasks.first { $0.id == draft.taskID }?.title ?? (draft.taskID == nil ? nil : draft.taskTitle)
                    if store.saveInterval(id: draft.intervalID, categoryID: draft.categoryID,
                                          start: draft.start, end: draft.isRunning ? nil : draft.end,
                                          taskID: draft.taskID, taskTitle: title) { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .font(.system(size: 12))
        .padding(22)
        .frame(width: 430)
        .onAppear { splitTime = draft.start.addingTimeInterval(draft.end.timeIntervalSince(draft.start) / 2) }
        .onChange(of: original?.endedAt) {
            if draft.isRunning, let end = original?.endedAt {
                draft.isRunning = false
                draft.end = end
            }
        }
        .confirmationDialog("Delete this interval?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete interval", role: .destructive) {
                if let id = draft.intervalID, store.deleteInterval(id) { dismiss() }
            }
        } message: { Text("This time will become untracked.") }
    }
}
