import FocusDeskCore
import SwiftData
import SwiftUI

struct ActivityInlineTimeEditor: View {
    @Environment(ActivityStore.self) private var store
    let original: ActivityIntervalSnapshot
    var onClose: () -> Void
    @State private var start: Date
    @State private var end: Date
    @State private var error: String?

    init(original: ActivityIntervalSnapshot, onClose: @escaping () -> Void) {
        self.original = original
        self.onClose = onClose
        _start = State(initialValue: original.start)
        _end = State(initialValue: original.end ?? Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            timeField("From", date: $start)
            if original.end != nil {
                timeField("Until", date: $end)
            } else {
                Text("Until now · activity is running").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Spacer(minLength: 0)
                Button("Cancel", action: onClose)
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
        }
        .font(.system(size: 12))
        .padding(.vertical, 12)
        .onExitCommand(perform: onClose)
        .onSubmit(save)
    }

    private func timeField(_ title: String, date: Binding<Date>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(date.wrappedValue.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            DatePicker(title, selection: date, in: ...Date(), displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.field)
                .controlSize(.small)
                .fixedSize()
        }
    }

    private func save() {
        var candidate = original
        candidate.start = start
        candidate.end = original.end == nil ? nil : end
        if store.resizeInterval(original, to: candidate) { onClose() }
        else { error = store.errorMessage }
    }
}

struct ActivityIntervalTaskMenu: View {
    @Environment(ActivityStore.self) private var store
    @Query(sort: \FocusTask.title) private var tasks: [FocusTask]
    var intervalID: UUID
    var title: String

    var body: some View {
        Menu {
            Button("No task") { select(nil) }
            ForEach(tasks) { task in Button(task.title) { select(task) } }
        } label: {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Change linked task")
        .accessibilityLabel("Linked task: \(title)")
    }

    private func select(_ task: FocusTask?) {
        guard let record = store.interval(intervalID) else { return }
        _ = store.saveInterval(id: intervalID, categoryID: record.categoryID, start: record.startedAt,
                               end: record.endedAt, taskID: task?.id, taskTitle: task?.title)
    }
}
