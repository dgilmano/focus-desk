import FocusDeskCore
import SwiftUI

struct TaskFocusSummaryView: View {
    @Bindable var task: FocusTask

    var availableTags: [TaskTagRecord]
    var onTaskChanged: () -> Void
    var onComplete: () -> Void

    @State private var isEditingCurrentTask = false
    @State private var isEditingMotivation = false
    @State private var isEditingNextStep = false
    @State private var isCurrentTaskHovered = false
    @State private var isMotivationHovered = false
    @State private var isNextStepHovered = false
    @State private var isCurrentTaskActionHovered = false
    @State private var isMotivationActionHovered = false
    @State private var isNextStepActionHovered = false
    @State private var summaryWidth = 0.0
    @FocusState private var currentTaskTitleFocused: Bool
    @FocusState private var currentTaskDetailsFocused: Bool
    @FocusState private var motivationEditorFocused: Bool
    @FocusState private var nextStepEditorFocused: Bool

    private let compactBreakpoint = 820.0
    private let summarySpacing = 58.0
    private let compactSummarySpacing = 28.0

    var body: some View {
        Group {
            if usesCompactLayout {
                VStack(alignment: .leading, spacing: compactSummarySpacing) {
                    currentTaskColumn
                    nextStepPanel
                }
            } else {
                HStack(alignment: .top, spacing: summarySpacing) {
                    currentTaskColumn
                        .frame(
                            minWidth: 0,
                            maxWidth: .infinity,
                            minHeight: compositionHeight,
                            maxHeight: compositionHeight,
                            alignment: .topLeading
                        )

                    nextStepPanel
                        .frame(
                            minWidth: 0,
                            maxWidth: .infinity,
                            minHeight: compositionHeight,
                            maxHeight: compositionHeight,
                            alignment: .topLeading
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(summaryWidthReader)
    }

    private var currentTaskColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                sectionLabel("Current Task")

                Spacer(minLength: 12)
            }
            .padding(.bottom, 16)

            if isEditingCurrentTask {
                currentTaskEditor
            } else {
                taskTitleBlock
            }

            if usesCompactLayout {
                motivationSection
                    .padding(.top, 38)
            } else {
                Spacer(minLength: 18)

                motivationSection
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered in
            withAnimation(.smooth(duration: 0.12)) {
                isCurrentTaskHovered = isHovered
            }
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 2) {
                subtleActionButton(
                    systemName: isEditingCurrentTask ? "checkmark" : "arrow.up.right",
                    help: isEditingCurrentTask ? "Done editing" : "Edit Current Task",
                    isVisible: isCurrentTaskActionVisible,
                    isHovered: $isCurrentTaskActionHovered,
                    action: isEditingCurrentTask ? endCurrentTaskEditing : beginCurrentTaskEditing
                )

                alwaysVisibleActionButton(
                    systemName: "checkmark.circle",
                    help: "Done",
                    action: onComplete
                )
            }
        }
    }

    private var taskTitleBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(task.title)
                .font(.system(size: currentTitleFontSize, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(usesCompactLayout ? 3 : 4)
                .minimumScaleFactor(0.58)
                .allowsTightening(true)
                .truncationMode(.tail)
                .accessibilityAddTraits(.isHeader)

            if !task.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                MarkdownText(
                    task.details,
                    font: .system(size: usesCompactLayout ? 14 : 15, weight: .regular),
                    lineLimit: usesCompactLayout ? 5 : 4
                )
                .foregroundStyle(.secondary)
                .minimumScaleFactor(0.76)
                .allowsTightening(true)
                .truncationMode(.tail)
            }
        }
    }

    private var motivationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "sparkle")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(Color.orange.opacity(0.86))

                sectionLabel("Why it matters")

                Spacer(minLength: 12)

                subtleActionButton(
                    systemName: isEditingMotivation ? "checkmark" : "pencil",
                    help: isEditingMotivation ? "Done editing" : "Edit Why It Matters",
                    isVisible: isMotivationActionVisible,
                    isHovered: $isMotivationActionHovered,
                    action: isEditingMotivation ? endMotivationEditing : beginMotivationEditing
                )
            }

            if isEditingMotivation {
                motivationEditor
            } else {
                MarkdownText(
                    motivationText,
                    font: .system(size: 14, weight: .regular),
                    lineLimit: usesCompactLayout ? 5 : 4
                )
                .foregroundStyle(currentMotivation.isEmpty ? .tertiary : .secondary)
                .minimumScaleFactor(0.78)
                .allowsTightening(true)
                .truncationMode(.tail)
                .textSelection(.enabled)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 86, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(FocusDeskStyle.focusSurface.opacity(0.86))
                )
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered in
            withAnimation(.smooth(duration: 0.12)) {
                isMotivationHovered = isHovered
            }
        }
    }

    private var nextStepPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 8) {
                sectionLabel("Next Step")

                Spacer(minLength: 12)

                subtleActionButton(
                    systemName: isEditingNextStep ? "checkmark" : "arrow.up.right",
                    help: isEditingNextStep ? "Done editing" : "Edit Next Step",
                    isVisible: isNextStepActionVisible,
                    isHovered: $isNextStepActionHovered,
                    action: isEditingNextStep ? endNextStepEditing : beginNextStepEditing
                )
            }

            if isEditingNextStep {
                nextStepEditor
            } else {
                nextStepContent
            }

            Spacer(minLength: 8)

            Text(nextStepMetadata)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .allowsTightening(true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: usesCompactLayout ? 202 : compositionHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(FocusDeskStyle.focusSurface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(FocusDeskStyle.focusDivider.opacity(0.28), lineWidth: 0.7)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onHover { isHovered in
            withAnimation(.smooth(duration: 0.12)) {
                isNextStepHovered = isHovered
            }
        }
    }

    private var nextStepContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if currentNextStep.isEmpty {
                Text("Add a next step.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            } else {
                activeNextStepRow

                nextStepDivider

                if !remainingNextStepsText.isEmpty {
                    MarkdownText(
                        remainingNextStepsText,
                        font: .system(size: 14, weight: .regular),
                        lineLimit: 5
                    )
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.78)
                    .allowsTightening(true)
                    .truncationMode(.tail)
                }
            }
        }
        .textSelection(.enabled)
    }

    private var nextStepDivider: some View {
        Rectangle()
            .fill(FocusDeskStyle.focusDivider.opacity(0.42))
            .frame(height: 1)
            .padding(.top, -2)
            .padding(.bottom, 2)
    }

    private var activeNextStepRow: some View {
        HStack(alignment: .center, spacing: 12) {
            MarkdownText(
                activeNextStepText,
                font: .system(size: 14, weight: .regular),
                lineLimit: usesCompactLayout ? 3 : 2
            )
            .foregroundStyle(.primary)
            .minimumScaleFactor(0.78)
            .allowsTightening(true)
            .truncationMode(.tail)

            Spacer(minLength: 8)

            Button {
                beginNextStepEditing()
            } label: {
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(FocusDeskStyle.focusAccent)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Edit Next Step")
        }
        .padding(.leading, 14)
        .padding(.trailing, 9)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(FocusDeskStyle.focusAccent.opacity(0.10))
        )
    }

    private var summaryWidthReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    updateSummaryWidth(proxy.size.width)
                }
                .onChange(of: proxy.size.width) { _, newWidth in
                    updateSummaryWidth(newWidth)
                }
        }
    }

    private var nextStepEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: nextStepBinding)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: usesCompactLayout ? 78 : 118)
                .focused($nextStepEditorFocused)
                .accessibilityLabel("Edit next step")

            if currentNextStep.isEmpty {
                Text("Next step")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }
        }
        .background(editorBackground)
    }

    private var motivationEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: motivationBinding)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: usesCompactLayout ? 64 : 78)
                .focused($motivationEditorFocused)
                .accessibilityLabel("Edit why it matters")

            if currentMotivation.isEmpty {
                Text("Add why this task matters.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }
        }
        .background(editorBackground)
    }

    private var currentTaskEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Current task", text: currentTaskTitleBinding)
                .textFieldStyle(.plain)
                .font(.system(size: usesCompactLayout ? 25 : 31, weight: .semibold))
                .foregroundStyle(.primary)
                .focused($currentTaskTitleFocused)
                .accessibilityLabel("Edit current task title")

            ZStack(alignment: .topLeading) {
                TextEditor(text: currentTaskDetailsBinding)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: usesCompactLayout ? 52 : 68)
                    .focused($currentTaskDetailsFocused)
                    .accessibilityLabel("Edit current task details")

                if task.details.isEmpty {
                    Text("Details")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .background(editorBackground)
        }
    }

    private var editorBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(nsColor: .textBackgroundColor).opacity(0.58))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(FocusDeskStyle.focusDivider.opacity(0.22), lineWidth: 0.7)
            }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.primary.opacity(0.86))
    }

    private func subtleActionButton(
        systemName: String,
        help: String,
        isVisible: Bool,
        isHovered: Binding<Bool>,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .onHover { isButtonHovered in
            withAnimation(.smooth(duration: 0.12)) {
                isHovered.wrappedValue = isButtonHovered
            }
        }
    }

    private func alwaysVisibleActionButton(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(isCurrentTaskHovered ? .secondary : .tertiary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var measuredSummaryWidth: Bool {
        summaryWidth > 0
    }

    private var usesCompactLayout: Bool {
        measuredSummaryWidth && summaryWidth < compactBreakpoint
    }

    private var compositionHeight: Double {
        usesCompactLayout ? 0 : 264
    }

    private var currentTitleFontSize: Double {
        usesCompactLayout ? 34.0 : 44.0
    }

    private var isCurrentTaskActionVisible: Bool {
        true
    }

    private var isMotivationActionVisible: Bool {
        isEditingMotivation || isMotivationHovered || isMotivationActionHovered
    }

    private var isNextStepActionVisible: Bool {
        true
    }

    private func updateSummaryWidth(_ width: Double) {
        let normalizedWidth = max(0, width)

        if abs(summaryWidth - normalizedWidth) > 0.5 {
            summaryWidth = normalizedWidth
        }
    }

    private func beginNextStepEditing() {
        guard !isEditingNextStep else {
            return
        }

        withAnimation(.smooth(duration: 0.18)) {
            isEditingNextStep = true
        }

        nextStepEditorFocused = true
    }

    private func endNextStepEditing() {
        withAnimation(.smooth(duration: 0.18)) {
            isEditingNextStep = false
        }

        nextStepEditorFocused = false
    }

    private func beginMotivationEditing() {
        guard !isEditingMotivation else {
            return
        }

        withAnimation(.smooth(duration: 0.18)) {
            isEditingMotivation = true
        }

        motivationEditorFocused = true
    }

    private func endMotivationEditing() {
        withAnimation(.smooth(duration: 0.18)) {
            isEditingMotivation = false
        }

        motivationEditorFocused = false
    }

    private func beginCurrentTaskEditing() {
        guard !isEditingCurrentTask else {
            return
        }

        withAnimation(.smooth(duration: 0.18)) {
            isEditingCurrentTask = true
        }

        currentTaskTitleFocused = true
        currentTaskDetailsFocused = false
    }

    private func endCurrentTaskEditing() {
        withAnimation(.smooth(duration: 0.18)) {
            isEditingCurrentTask = false
        }

        currentTaskTitleFocused = false
        currentTaskDetailsFocused = false
    }

    private var currentNextStep: String {
        task.nextStep ?? ""
    }

    private var currentMotivation: String {
        task.motivation ?? ""
    }

    private var nextStepBinding: Binding<String> {
        Binding(
            get: {
                task.nextStep ?? ""
            },
            set: { newValue in
                task.nextStep = newValue
                task.updatedAt = Date()
                onTaskChanged()
            }
        )
    }

    private var motivationBinding: Binding<String> {
        Binding(
            get: {
                task.motivation ?? ""
            },
            set: { newValue in
                task.motivation = newValue
                task.updatedAt = Date()
                onTaskChanged()
            }
        )
    }

    private var currentTaskTitleBinding: Binding<String> {
        Binding(
            get: {
                task.title
            },
            set: { newValue in
                task.title = newValue
                task.updatedAt = Date()
                onTaskChanged()
            }
        )
    }

    private var currentTaskDetailsBinding: Binding<String> {
        Binding(
            get: {
                task.details
            },
            set: { newValue in
                task.details = newValue
                task.updatedAt = Date()
                onTaskChanged()
            }
        )
    }

    private var motivationText: String {
        currentMotivation.isEmpty ? "Add why this task matters." : currentMotivation
    }

    private var nextStepLines: [String] {
        currentNextStep
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var activeNextStepText: String {
        nextStepLines.first ?? currentNextStep
    }

    private var remainingNextStepsText: String {
        guard nextStepLines.count > 1 else {
            return ""
        }

        return nextStepLines.dropFirst().joined(separator: "\n")
    }

    private var nextStepMetadata: String {
        if currentNextStep.isEmpty {
            return "No next step yet"
        }

        if nextStepLines.count <= 1 {
            return "Current move"
        }

        return "\(nextStepLines.count - 1) remaining"
    }
}
