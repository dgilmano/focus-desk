import AppKit
import SwiftUI

struct TaskCardView: View {
    @Bindable var task: FocusTask

    var showsHeader = true
    var isSavingStep = false
    var noteFocused: FocusState<Bool>.Binding
    var onDraftChanged: () -> Void
    var onSaveJournalEntry: () -> Void
    var onJournalEntryChanged: () -> Void
    var onDeleteJournalEntry: (ProgressEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if showsHeader {
                HStack(alignment: .top, spacing: 14) {
                    FocusDeskIcon(systemName: "target", filled: true)
                        .padding(.top, 5)

                    VStack(alignment: .leading, spacing: 7) {
                        Text(task.title)
                            .font(.system(size: 33, weight: .semibold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.78)
                            .accessibilityAddTraits(.isHeader)

                        if !task.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            MarkdownText(
                                task.details,
                                font: .system(size: 15),
                                lineLimit: 3
                            )
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 13) {
                Text("What Was Done")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.86))
                    .textCase(.uppercase)

                WorkDoneInputBlock(
                    task: task,
                    isSavingStep: isSavingStep,
                    noteFocused: noteFocused,
                    onDraftChanged: onDraftChanged,
                    onSaveJournalEntry: onSaveJournalEntry
                )
            }

            Rectangle()
                .fill(FocusDeskStyle.focusDivider.opacity(0.34))
                .frame(height: 1)
                .padding(.top, 2)
                .padding(.bottom, 2)

            journalTimeline
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var journalTimeline: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Journal")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if task.newestEntries.isEmpty {
                Text("No journal entries yet.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(task.newestEntries.enumerated()), id: \.element.id) { index, entry in
                        ProgressEntryRow(
                            entry: entry,
                            isLast: index == task.newestEntries.count - 1,
                            onEntryChanged: onJournalEntryChanged,
                            onDelete: {
                                onDeleteJournalEntry(entry)
                            }
                        )
                    }
                }
            }
        }
    }
}

private struct WorkDoneInputBlock: View {
    @Bindable var task: FocusTask

    var isSavingStep: Bool
    var noteFocused: FocusState<Bool>.Binding
    var onDraftChanged: () -> Void
    var onSaveJournalEntry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .leading) {
                TextField("", text: $task.localDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)
                    .accessibilityLabel("What was done")
                    .focused(noteFocused)
                    .onChange(of: task.localDraft) {
                        task.updatedAt = Date()
                        onDraftChanged()
                    }

                if task.localDraft.isEmpty {
                    Text("What was done and where did you stop?")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .center)

            Button {
                onSaveJournalEntry()
            } label: {
                HStack(spacing: 6) {
                    if hasDraft {
                        Text("Save")
                            .font(.system(size: 12, weight: .medium))
                    }

                    Image(systemName: isSavingStep ? "clock" : "checkmark")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(hasDraft ? FocusDeskStyle.focusAccent : Color(nsColor: .tertiaryLabelColor))
                .padding(.horizontal, hasDraft ? 10 : 0)
                .frame(minWidth: hasDraft ? 58 : 24, minHeight: 24)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!hasDraft || isSavingStep)
            .help("Save Progress")
        }
        .padding(.leading, 15)
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, minHeight: 58, maxHeight: 58, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.28))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    hasDraft ? FocusDeskStyle.focusAccent.opacity(0.34) : FocusDeskStyle.focusDivider.opacity(0.58),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var hasDraft: Bool {
        !task.localDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct ProgressEntryRow: View {
    @Bindable var entry: ProgressEntry
    var isLast: Bool
    var onEntryChanged: () -> Void
    var onDelete: () -> Void

    @State private var isExpanded = false
    @State private var isEditing = false
    @State private var isHovered = false
    @State private var isActionHovered = false
    @State private var rowWidth = 0.0
    @FocusState private var editorFocused: Bool

    private let collapsedNoteLineLimit = 3

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            VStack(spacing: 0) {
                Circle()
                    .fill(Color.secondary.opacity(0.58))
                    .frame(width: 6, height: 6)
                    .padding(.top, 6)

                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.30))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                        .padding(.top, 5)
                }
            }
            .frame(width: 10)
            .frame(minHeight: 34)

            VStack(alignment: .leading, spacing: 5) {
                Text(DateFormatting.journalString(from: entry.timestamp))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.trailing, 66)

                if isEditing {
                    noteEditor
                } else {
                    MarkdownText(
                        entry.note,
                        font: .system(size: 13, weight: .regular),
                        lineLimit: isExpanded ? nil : collapsedNoteLineLimit
                    )
                    .foregroundStyle(.primary.opacity(0.82))
                    .textSelection(.enabled)
                }

                if !isEditing && isExpandable {
                    Button {
                        withAnimation(.smooth(duration: 0.18)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(isExpanded ? "Show less" : "Show more")

                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10, weight: .regular))
                        }
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.tertiary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 3)
                }
            }
        }
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovered in
            withAnimation(.smooth(duration: 0.12)) {
                isHovered = hovered
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: ProgressEntryRowWidthPreferenceKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(ProgressEntryRowWidthPreferenceKey.self) { width in
            if abs(rowWidth - width) > 0.5 {
                rowWidth = width
            }
        }
        .overlay(alignment: .topTrailing) {
            journalActionButtons
                .padding(.top, 7)
        }
    }

    private var noteEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: entryNoteBinding)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.secondary)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 78)
                .focused($editorFocused)
                .accessibilityLabel("Edit journal entry")

            if entry.note.isEmpty {
                Text("Journal entry")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.66))
        )
    }

    private var journalActionButtons: some View {
        HStack(spacing: 2) {
            journalActionButton(
                systemName: isEditing ? "checkmark" : "pencil",
                help: isEditing ? "Done editing" : "Edit Journal Entry",
                isDestructive: false,
                action: isEditing ? endEditing : beginEditing
            )

            journalActionButton(
                systemName: "trash",
                help: "Delete Journal Entry",
                isDestructive: true,
                action: onDelete
            )
        }
        .opacity(actionsVisible ? 1 : 0)
        .allowsHitTesting(actionsVisible)
        .onHover { hovered in
            withAnimation(.smooth(duration: 0.12)) {
                isActionHovered = hovered
            }
        }
    }

    private func journalActionButton(
        systemName: String,
        help: String,
        isDestructive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(isDestructive ? Color.red.opacity(0.72) : Color(nsColor: .secondaryLabelColor))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var entryNoteBinding: Binding<String> {
        Binding(
            get: {
                entry.note
            },
            set: { newValue in
                entry.note = newValue
                onEntryChanged()
            }
        )
    }

    private var actionsVisible: Bool {
        isEditing || isHovered || isActionHovered
    }

    private func beginEditing() {
        withAnimation(.smooth(duration: 0.18)) {
            isEditing = true
            isExpanded = true
        }

        editorFocused = true
    }

    private func endEditing() {
        withAnimation(.smooth(duration: 0.18)) {
            isEditing = false
        }

        editorFocused = false
    }

    private var isExpandable: Bool {
        renderedNoteLineCount > collapsedNoteLineLimit
    }

    private var renderedNoteLineCount: Int {
        guard rowWidth > 0 else {
            return fallbackNoteLineCount
        }

        let font = NSFont.systemFont(ofSize: 13, weight: .regular)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping

        let attributedString = NSAttributedString(
            string: entry.note,
            attributes: [
                .font: font,
                .paragraphStyle: paragraphStyle
            ]
        )

        let lineHeight = max(font.ascender - font.descender + font.leading, 1)
        let boundingRect = attributedString.boundingRect(
            with: NSSize(width: rowWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )

        return max(1, Int(ceil(boundingRect.height / lineHeight)))
    }

    private var fallbackNoteLineCount: Int {
        entry.note.components(separatedBy: .newlines).count
    }
}

private struct ProgressEntryRowWidthPreferenceKey: PreferenceKey {
    static let defaultValue = 0.0

    static func reduce(value: inout Double, nextValue: () -> Double) {
        value = nextValue()
    }
}

enum DateFormatting {
    static func sessionString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func journalString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func relativeString(from date: Date, relativeTo referenceDate: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: referenceDate)
    }

    static func elapsedSinceLastUpdateString(from date: Date, relativeTo referenceDate: Date) -> String {
        let elapsedSeconds = max(0, referenceDate.timeIntervalSince(date))

        if elapsedSeconds < 60 {
            return "Just updated"
        }

        let units: [(seconds: TimeInterval, name: String)] = [
            (60 * 60 * 24 * 365, "year"),
            (60 * 60 * 24 * 30, "month"),
            (60 * 60 * 24 * 7, "week"),
            (60 * 60 * 24, "day"),
            (60 * 60, "hour"),
            (60, "minute")
        ]

        guard let unit = units.first(where: { elapsedSeconds >= $0.seconds }) else {
            return "Just updated"
        }

        let value = Int(elapsedSeconds / unit.seconds)
        let pluralSuffix = value == 1 ? "" : "s"
        return "\(value) \(unit.name)\(pluralSuffix) since last update"
    }
}
