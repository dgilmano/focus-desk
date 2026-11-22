import AppKit
import SwiftUI

struct TaskCardView: View {
    @Bindable var task: FocusTask
    var availableWidth: CGFloat

    var showsHeader = true
    var isSavingStep = false
    var noteFocused: FocusState<Bool>.Binding
    var onDraftChanged: () -> Void
    var onSaveJournalEntry: () -> Void
    var onJournalEntryChanged: () -> Void
    var onDeleteJournalEntry: (ProgressEntry) -> Void
    var onReturnJournalEntry: (UUID) -> Bool
    var onCompleteNextStep: (Int, String) -> Bool
    var compactJournal = false
    var onJournalSwipe: (CGFloat) -> Void = { _ in }
    @State private var showEarlier = false
    @State private var isEditingJournal = false

    var body: some View {
        journalContent
            .frame(maxWidth: .infinity, maxHeight: compactJournal && availableWidth >= FocusDeskStyle.workspaceCompactBreakpoint ? .infinity : nil,
                   alignment: .topLeading)
            .background {
                Color.clear.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 36).onEnded { value in
                    guard !isEditingJournal, abs(value.translation.width) > abs(value.translation.height) else { return }
                    onJournalSwipe(value.translation.width)
                })
            }
            .workspacePanel()
            .modifier(DeskTransferTarget { (drag: DeskStepDrag) in
                guard drag.taskID == task.id else { return false }
                return onCompleteNextStep(drag.stepID, drag.source)
            })
    }

    @ViewBuilder private var journalContent: some View {
        if compactJournal {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    DeskDetailHeading(title: "Journal", symbol: "book.pages")
                    Text(task.entries.count, format: .number)
                        .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(FocusDeskStyle.deskAccent)
                        .padding(.horizontal, 6).frame(minWidth: 20, minHeight: 17)
                        .background(FocusDeskStyle.deskAccent.opacity(0.10), in: Capsule())
                        .accessibilityLabel(task.entries.count == 1 ? "1 journal entry" : "\(task.entries.count) journal entries")
                    Spacer()
                    DeskDetailEditButton(isEditing: isEditingJournal, section: "journal") {
                        noteFocused.wrappedValue = false
                        isEditingJournal.toggle()
                    }
                    .disabled(task.entries.isEmpty)
                }
                .frame(minHeight: 28)
                noteInput
                entryList
            }
            .onChange(of: task.entries.isEmpty) {
                if task.entries.isEmpty { isEditingJournal = false }
            }
        } else {
            expandedCard
        }
    }

    private var expandedCard: some View {
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

            Rectangle()
                .fill(FocusDeskStyle.hairline)
                .frame(height: 1)
                .padding(.top, showsHeader ? 2 : 0)

            lowerActivityGrid
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var lowerActivityGrid: some View {
        WorkspaceColumns(availableWidth: availableWidth) {
            workDoneSection
        } trailing: {
            journalTimeline
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var workDoneSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What was done")
                .font(FocusDeskStyle.workspaceSectionFont)
                .frame(height: 28)

            noteInput
        }
    }

    private var noteInput: some View {
        WorkDoneInputBlock(task: task, isSavingStep: isSavingStep, noteFocused: noteFocused,
                           onDraftChanged: onDraftChanged, onSaveJournalEntry: onSaveJournalEntry,
                           compact: compactJournal)
    }

    private var journalTimeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Journal")
                .font(FocusDeskStyle.workspaceSectionFont)
                .frame(height: 28)

            entryList
        }
    }

    @ViewBuilder private var entryList: some View {
        let entries = task.newestEntries
        if entries.isEmpty {
            Text("No journal entries yet.")
                .font(FocusDeskStyle.workspaceBodyFont)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        } else if compactJournal {
            let visible = entries.prefix(showEarlier ? entries.count : 3)
            let days = Dictionary(grouping: visible) { Calendar.current.startOfDay(for: $0.timestamp) }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(days.keys.sorted(by: >), id: \.self) { day in
                    HStack(spacing: 8) {
                        Text(day, format: .dateTime.month(.abbreviated).day().year())
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                        Rectangle().fill(FocusDeskStyle.hairline).frame(height: 1)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 4)
                    ForEach(days[day] ?? []) { entry in
                        journalRow(entry, isLast: false)
                    }
                }
                if entries.count > 3 {
                    Button {
                        showEarlier.toggle()
                    } label: {
                        Label(showEarlier ? "Show less" : "Earlier entries (\(entries.count - 3))",
                              systemImage: showEarlier ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(FocusDeskStyle.deskAccent)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(entries) { entry in
                    journalRow(entry, isLast: entry.id == entries.last?.id)
                }
            }
        }
    }

    private func journalRow(_ entry: ProgressEntry, isLast: Bool) -> some View {
        ProgressEntryRow(entry: entry, isLast: isLast, compact: compactJournal, journalEditing: isEditingJournal,
                         onEntryChanged: onJournalEntryChanged,
                         onDelete: { onDeleteJournalEntry(entry) },
                         onReturn: { _ = onReturnJournalEntry(entry.id) })
    }
}

private struct WorkDoneInputBlock: View {
    @Bindable var task: FocusTask

    var isSavingStep: Bool
    var noteFocused: FocusState<Bool>.Binding
    var onDraftChanged: () -> Void
    var onSaveJournalEntry: () -> Void
    var compact = false
    private var inputAccent: Color { compact ? FocusDeskStyle.deskAccent : .teal }

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .leading) {
                TextField("", text: $task.localDraft)
                    .textFieldStyle(.plain)
                    .font(FocusDeskStyle.workspaceBodyFont)
                    .foregroundStyle(.primary)
                    .accessibilityLabel("What was done")
                    .focused(noteFocused)
                    .onSubmit {
                        if compact && hasDraft && !isSavingStep { onSaveJournalEntry() }
                    }
                    .onChange(of: task.localDraft) {
                        task.updatedAt = Date()
                        onDraftChanged()
                    }

                if task.localDraft.isEmpty {
                    Text(compact ? "What was done?" : "What was done and where did you stop?")
                        .font(FocusDeskStyle.workspaceBodyFont)
                        .lineLimit(1)
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .center)

            Button {
                onSaveJournalEntry()
            } label: {
                Image(systemName: isSavingStep ? "clock" : "checkmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(hasDraft ? inputAccent : Color(nsColor: .tertiaryLabelColor))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!hasDraft || isSavingStep)
            .help("Save Progress")
            .accessibilityLabel("Save Progress")
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, minHeight: compact ? 32 : 48, maxHeight: compact ? 32 : 48, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(FocusDeskStyle.focusSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(
                    hasDraft ? inputAccent.opacity(0.3) : FocusDeskStyle.hairline,
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var hasDraft: Bool {
        !task.localDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct ProgressEntryRow: View {
    @Bindable var entry: ProgressEntry
    var isLast: Bool
    var compact: Bool
    var journalEditing: Bool
    var onEntryChanged: () -> Void
    var onDelete: () -> Void
    var onReturn: () -> Void

    @State private var isExpanded = false
    @State private var isEditingRow = false
    @State private var isHovered = false
    @State private var isActionHovered = false
    @State private var rowWidth = 0.0
    @FocusState private var editorFocused: Bool

    private let collapsedNoteLineLimit = 3
    private var isEditing: Bool { compact ? journalEditing : isEditingRow }

    var body: some View {
        if !isEditing, let taskID = entry.task?.id {
            row.draggable(DeskJournalDrag(taskID: taskID, entryID: entry.id)) {
                Text(entry.note).lineLimit(2).padding(6)
            }
            .contextMenu { DeskCopyTextButton(text: entry.note) }
        } else {
            row
        }
    }

    private var row: some View {
        HStack(alignment: .top, spacing: compact ? 10 : 13) {
            if compact {
                Text(entry.timestamp, format: .dateTime.hour().minute())
                    .font(.system(size: 11, weight: .medium)).monospacedDigit()
                    .foregroundStyle(FocusDeskStyle.deskAccent)
                    .frame(width: 62, alignment: .leading)
                    .padding(.top, 1)
            } else {
                timelineMarker
            }

            VStack(alignment: .leading, spacing: 5) {
                if !compact {
                    Text(DateFormatting.journalString(from: entry.timestamp))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                        .padding(.trailing, 80)
                }

                if isEditing {
                    noteEditor
                } else {
                    MarkdownText(
                        entry.note,
                        font: FocusDeskStyle.workspaceBodyFont,
                        lineLimit: isExpanded ? nil : collapsedNoteLineLimit,
                        emphasisColor: compact ? FocusDeskStyle.deskAccent : nil
                    )
                    .foregroundStyle(.primary.opacity(0.82))
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
            .padding(.trailing, compact ? (journalEditing ? 54 : 26) : 0)
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
            journalActionButtons.padding(.top, 7)
        }
    }

    private var timelineMarker: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(Color.teal.opacity(0.7))
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            if !isLast {
                Rectangle()
                    .fill(FocusDeskStyle.hairline)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
                    .padding(.top, 5)
            }
        }
        .frame(width: 10)
        .frame(minHeight: 34)
    }

    private var noteEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: entryNoteBinding)
                .font(FocusDeskStyle.workspaceBodyFont)
                .foregroundStyle(.secondary)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 78)
                .focused($editorFocused)
                .accessibilityLabel("Edit journal entry")

            if entry.note.isEmpty {
                Text("Journal entry")
                    .font(FocusDeskStyle.workspaceBodyFont)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(FocusDeskStyle.focusSurface)
        )
    }

    private var journalActionButtons: some View {
        HStack(spacing: 2) {
            if !compact {
                journalActionButton(
                    systemName: isEditing ? "checkmark" : "pencil",
                    help: isEditing ? "Done editing" : "Edit Journal Entry",
                    isDestructive: false,
                    action: isEditing ? endEditing : beginEditing
                )
            }

            journalActionButton(systemName: "arrow.uturn.backward", help: "Move to Next step",
                                isDestructive: false, action: onReturn)
            if journalEditing || !compact {
                journalActionButton(
                    systemName: "trash",
                    help: "Delete Journal Entry",
                    isDestructive: true,
                    action: onDelete
                )
            }
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
        .accessibilityLabel(help)
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
            isEditingRow = true
            isExpanded = true
        }

        editorFocused = true
    }

    private func endEditing() {
        withAnimation(.smooth(duration: 0.18)) {
            isEditingRow = false
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

        let font = NSFont.systemFont(ofSize: 12, weight: .regular)
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
            with: NSSize(width: max(1, rowWidth - (compact ? 72 : 23)), height: CGFloat.greatestFiniteMagnitude),
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
