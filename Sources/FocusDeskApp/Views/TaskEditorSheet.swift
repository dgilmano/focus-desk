import SwiftUI

struct TaskEditorSheet: View {
    enum Mode {
        case create
        case edit(FocusTask)

        var title: String {
            switch self {
            case .create:
                return "New Task"
            case .edit:
                return "Edit Task"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var details: String

    @State private var parentID: UUID?
    let parentChoices: [TaskOutline.Item]
    var mode: Mode
    var onSave: (String, String, UUID?) -> Bool

    init(mode: Mode, parentChoices: [TaskOutline.Item] = [], onSave: @escaping (String, String, UUID?) -> Bool) {
        self.parentChoices = parentChoices
        self.mode = mode
        self.onSave = onSave

        switch mode {
        case .create:
            _title = State(initialValue: "")
            _details = State(initialValue: "")
        case let .edit(task):
            _title = State(initialValue: task.title)
            _details = State(initialValue: task.details)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                FocusDeskIcon(systemName: modeIcon, filled: true)

                Text(mode.title)
                    .font(.system(size: 24, weight: .semibold))
            }

            FocusDeskGroupedPanel {
                VStack(alignment: .leading, spacing: 12) {
                    if !parentChoices.isEmpty {
                        LabeledContent("Parent task") {
                            ProjectTaskPicker(tasks: parentChoices, selection: $parentID, label: "Parent task", emptyChoice: "No parent").frame(height: 24)
                        }
                    }
                    Text("Title")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(FocusDeskStyle.sectionHeadingForeground)

                    TextField("Title", text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18, weight: .medium))
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(nsColor: .textBackgroundColor))
                        )

                    Text("Description")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(FocusDeskStyle.sectionHeadingForeground)

                    TextEditor(text: $details)
                        .font(.system(size: 15))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 120)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(nsColor: .textBackgroundColor))
                        )
                        .accessibilityLabel("Description")
                }
                .padding(18)
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    if onSave(
                        title.trimmingCharacters(in: .whitespacesAndNewlines),
                        details.trimmingCharacters(in: .whitespacesAndNewlines), parentID
                    ) { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(FocusDeskStyle.appBackground)
        .safeAreaInset(edge: .bottom, spacing: 0) { DataProtectionStatus() }
    }

    private var modeIcon: String {
        switch mode {
        case .create:
            return "plus.square.on.square"
        case .edit:
            return "square.and.pencil"
        }
    }
}
