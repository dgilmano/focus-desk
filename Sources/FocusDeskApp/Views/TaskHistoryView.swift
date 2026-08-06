import SwiftUI

struct TaskHistoryView: View {
    @Environment(\.dismiss) private var dismiss

    var task: FocusTask

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.system(size: 22, weight: .semibold))
                        .lineLimit(2)

                    Text("History")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            if task.newestEntries.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "text.justify.left")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)

                    Text("No journal entries")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(task.newestEntries) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(DateFormatting.journalString(from: entry.timestamp))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)

                        MarkdownText(entry.note, font: .body)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 6)
                }
                .listStyle(.plain)
            }
        }
        .padding(24)
        .frame(width: 560, height: 420)
    }
}
