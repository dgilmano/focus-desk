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
    var availableWidth: CGFloat

    // Store changes can arrive between TimelineView ticks (for example, a newly started activity).
    private var liveNow: Date { max(now, Date()) }
    private var day: Date { selectedDate ?? liveNow }
    private var dayRange: DateInterval { Calendar.current.dateInterval(of: .day, for: day)! }

    var body: some View {
        let segments = ActivityTimeline.segments(on: day, intervals: store.snapshots, now: liveNow)
        let totals = ActivityTimeline.totals(for: segments)
        VStack(alignment: .leading, spacing: 16) {
            if let notice = store.notice, Calendar.current.isDate(day, inSameDayAs: liveNow) {
                Text(notice).font(.system(size: 12)).foregroundStyle(.secondary)
            }

            if availableWidth >= 650 {
                HStack(alignment: .top, spacing: 24) {
                    timeline(segments)
                        .frame(width: (availableWidth - 49) * 0.6)
                    balance(segments, totals: totals)
                        .padding(.leading, 24)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(FocusDeskStyle.hairline).frame(width: 1)
                        }
                        .frame(maxWidth: .infinity)
                }
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    timeline(segments)
                    Divider()
                    balance(segments, totals: totals)
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
    }

    private func timeline(_ segments: [ActivityDaySegment]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Day timeline").font(.system(size: 17, weight: .semibold))
                Spacer()
                ActivityIconButton(symbol: "plus", title: "Add interval") { addInterval(segments) }
                    .disabled(store.availableCategories.isEmpty || !segments.contains { $0.intervalID == nil })
            }
            .frame(height: 28)

            if !segments.contains(where: { $0.intervalID != nil }) {
                Text("No activity recorded for this day.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }

            LazyVStack(spacing: 0) {
                ForEach(segments) { segment in
                    let record = segment.intervalID.flatMap { store.interval($0) }
                    let isActive = record != nil && record?.endedAt == nil && Calendar.current.isDate(day, inSameDayAs: liveNow)
                    ActivityTimelineRow(
                        segment: segment, category: store.category(segment.categoryID),
                        taskTitle: record?.taskTitle, isActive: isActive,
                        isFirst: segment.id == segments.first?.id,
                        isLast: segment.id == segments.last?.id, dayEnd: dayRange.end,
                        showsInlineRange: availableWidth >= 850
                    ) { edit(segment) }
                }
            }
        }
    }

    private func balance(_ segments: [ActivityDaySegment], totals: [UUID: TimeInterval]) -> some View {
        ActivityDayBalanceView(categories: store.categories, segments: segments, totals: totals,
                               dayEnd: dayRange.end, onSelectInterval: edit)
    }

    private func addInterval(_ segments: [ActivityDaySegment]) {
        guard let gap = segments.last(where: { $0.intervalID == nil }) else { return }
        edit(gap)
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
