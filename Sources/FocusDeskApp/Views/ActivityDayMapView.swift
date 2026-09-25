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
    var now: Date

    private var day: Date { selectedDate ?? now }
    private var dayRange: DateInterval { Calendar.current.dateInterval(of: .day, for: day)! }
    private var segments: [ActivityDaySegment] {
        ActivityTimeline.segments(on: day, intervals: store.snapshots, now: now)
    }
    private var totals: [UUID: TimeInterval] { ActivityTimeline.totals(for: segments) }
    private var recordedCategories: [ActivityCategory] {
        store.categories.filter { totals[$0.id] != nil }.sorted { totals[$0.id, default: 0] > totals[$1.id, default: 0] }
    }
    private var untracked: TimeInterval { segments.filter { $0.intervalID == nil }.reduce(0) { $0 + $1.duration } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack { heading; Spacer(); dateControls }
                VStack(alignment: .leading, spacing: 8) { heading; dateControls }
            }
            timeline
            if let notice = store.notice, Calendar.current.isDate(day, inSameDayAs: now) {
                Text(notice).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if recordedCategories.isEmpty {
                Text("No activity recorded for this day.").font(.system(size: 13)).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(recordedCategories) { category in
                        totalRow(category)
                    }
                }
            }
            HStack {
                Text("Untracked").foregroundStyle(.secondary)
                Spacer()
                Text(ActivityTimeText.duration(untracked)).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
            Divider()
            HStack {
                Text("Intervals").font(.system(size: 13))
                Spacer()
                ActivityIconButton(symbol: "plus", title: "Add interval") { addInterval() }
                    .disabled(store.availableCategories.isEmpty || !segments.contains { $0.intervalID == nil })
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(segments) { segment in
                        intervalRow(segment)
                    }
                }
            }
            .frame(height: min(240, CGFloat(segments.count) * 38))
            if let error = store.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 18)
        .sheet(item: $draft) { value in
            ActivityIntervalEditor(draft: value)
        }
        .sheet(isPresented: $showingSettings) { ActivityCategoriesView() }
    }

    private var heading: some View {
        Text("Timeline").font(.system(size: 16, weight: .medium))
    }

    private var dateControls: some View {
        HStack(spacing: 4) {
            ActivityIconButton(symbol: "chevron.left", title: "Previous day") { moveDay(-1) }
            DatePicker("Day", selection: Binding(get: { day }, set: {
                selectedDate = Calendar.current.isDate($0, inSameDayAs: now) ? nil : $0
            }), in: ...now, displayedComponents: .date)
                .labelsHidden().datePickerStyle(.field)
            ActivityIconButton(symbol: "chevron.right", title: "Next day") { moveDay(1) }
                .disabled(Calendar.current.isDate(day, inSameDayAs: now))
            Button("Today") { selectedDate = nil }
                .buttonStyle(.plain).font(.system(size: 12))
                .disabled(Calendar.current.isDate(day, inSameDayAs: now))
        }
    }

    private var timeline: some View {
        VStack(spacing: 7) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle().fill(FocusDeskStyle.focusSurface)
                    ForEach(segments) { segment in
                        let palette = TaskTagPalette.palette(for: store.category(segment.categoryID)?.colorName ?? "gray")
                        Button { edit(segment) } label: {
                            Rectangle()
                                .fill(segment.intervalID == nil ? Color.secondary.opacity(0.12) : palette.background)
                                .overlay(alignment: .trailing) { Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1) }
                                .frame(width: max(0, geometry.size.width * segment.duration / dayRange.duration))
                                .frame(height: 36)
                        }
                        .buttonStyle(.plain)
                        .offset(x: geometry.size.width * segment.start.timeIntervalSince(dayRange.start) / dayRange.duration)
                        .help(segmentDescription(segment))
                        .accessibilityLabel(segmentDescription(segment))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .frame(height: 36)
            GeometryReader { geometry in
                ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                    let date = hour == 24 ? dayRange.end : Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: dayRange.start)!
                    Text(String(format: "%02d", hour))
                        .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                        .position(x: max(8, min(geometry.size.width - 8, geometry.size.width * date.timeIntervalSince(dayRange.start) / dayRange.duration)), y: 6)
                }
            }
            .frame(height: 14)
        }
    }

    private func totalRow(_ category: ActivityCategory) -> some View {
        let palette = TaskTagPalette.palette(for: category.colorName)
        let duration = totals[category.id, default: 0]
        let recorded = max(1, totals.values.reduce(0, +))
        return VStack(spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: category.symbol).foregroundStyle(palette.foreground).frame(width: 16)
                Text(category.name).lineLimit(1)
                Spacer()
                Text(ActivityTimeText.duration(duration)).monospacedDigit()
            }
            .font(.system(size: 12))
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 2).fill(palette.background)
                    .frame(width: proxy.size.width * duration / recorded)
            }
            .frame(height: 4)
            .accessibilityHidden(true)
        }
    }

    private func intervalRow(_ segment: ActivityDaySegment) -> some View {
        let category = store.category(segment.categoryID)
        let palette = TaskTagPalette.palette(for: category?.colorName ?? "gray")
        return Button { edit(segment) } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(palette.background).frame(width: 9, height: 18)
                Text("\(timeLabel(segment.start)) - \(timeLabel(segment.end))")
                    .monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 118, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(category?.name ?? "Untracked").lineLimit(1)
                    if let id = segment.intervalID, let title = store.interval(id)?.taskTitle {
                        Text(title).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Text(ActivityTimeText.duration(segment.duration)).foregroundStyle(.secondary).monospacedDigit()
                Image(systemName: segment.intervalID == nil ? "plus" : "pencil").foregroundStyle(.secondary).frame(width: 20)
            }
            .font(.system(size: 12))
            .frame(height: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(segment.intervalID == nil ? "Fill untracked time" : "Edit interval")
    }

    private func segmentDescription(_ segment: ActivityDaySegment) -> String {
        "\(store.category(segment.categoryID)?.name ?? "Untracked"), \(timeLabel(segment.start)) to \(timeLabel(segment.end)), \(ActivityTimeText.duration(segment.duration))"
    }

    private func timeLabel(_ date: Date) -> String {
        date == dayRange.end ? "24:00" : date.formatted(date: .omitted, time: .shortened)
    }

    private func moveDay(_ offset: Int) {
        guard let date = Calendar.current.date(byAdding: .day, value: offset, to: day) else { return }
        selectedDate = Calendar.current.isDate(date, inSameDayAs: now) ? nil : date
    }

    private func addInterval() {
        guard let gap = segments.last(where: { $0.intervalID == nil }) else { return }
        edit(gap)
    }

    private func edit(_ segment: ActivityDaySegment) {
        if let id = segment.intervalID, let record = store.interval(id) {
            draft = .init(intervalID: id, categoryID: record.categoryID, start: record.startedAt,
                          end: record.endedAt ?? now, isRunning: record.endedAt == nil,
                          taskID: record.taskID, taskTitle: record.taskTitle)
        } else if let category = store.availableCategories.first {
            draft = .init(categoryID: category.id, start: segment.start, end: segment.end)
        } else {
            showingSettings = true
        }
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
