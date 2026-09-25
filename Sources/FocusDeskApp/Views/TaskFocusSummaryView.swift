import FocusDeskCore
import SwiftUI

struct TaskFocusSummaryView: View {
    @Bindable var task: FocusTask

    var availableWidth: CGFloat
    var availableTags: [TaskTagRecord]
    var onTaskChanged: () -> Void
    var onComplete: () -> Void

    @State private var isEditingCurrentTask = false
    @State private var isEditingMotivation = false
    @State private var isEditingNextStep = false
    @State private var isMotivationHovered = false
    @State private var isCurrentTaskActionHovered = false
    @State private var isMotivationActionHovered = false
    @State private var isNextStepActionHovered = false
    @FocusState private var currentTaskTitleFocused: Bool
    @FocusState private var currentTaskDetailsFocused: Bool
    @FocusState private var motivationEditorFocused: Bool
    @FocusState private var nextStepEditorFocused: Bool

    var body: some View {
        WorkspaceColumns(availableWidth: availableWidth) {
            currentTaskColumn
        } trailing: {
            nextStepPanel
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var currentTaskColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                sectionLabel("Current Task")

                Spacer(minLength: 12)

                subtleActionButton(
                    systemName: isEditingCurrentTask ? "checkmark" : "arrow.up.right",
                    help: isEditingCurrentTask ? "Done editing" : "Edit Current Task",
                    isVisible: isCurrentTaskActionVisible,
                    isHovered: $isCurrentTaskActionHovered,
                    action: isEditingCurrentTask ? endCurrentTaskEditing : beginCurrentTaskEditing
                )

                alwaysVisibleActionButton(systemName: "checkmark.circle", help: "Done", action: onComplete)
            }
            .frame(height: 28)
            .padding(.bottom, 18)

            if isEditingCurrentTask {
                currentTaskEditor
            } else {
                taskTitleBlock
            }

            motivationSection.padding(.top, 28)
        }
        .contentShape(Rectangle())
    }

    private var taskTitleBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(task.title)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .truncationMode(.tail)
                .accessibilityAddTraits(.isHeader)

            if !task.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                MarkdownText(
                    task.details,
                    font: FocusDeskStyle.workspaceBodyFont
                )
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var motivationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "sparkle")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.orange.opacity(0.86))

                Text("Why it matters")
                    .font(.system(size: 13, weight: .semibold))

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
                    font: FocusDeskStyle.workspaceBodyFont
                )
                .foregroundStyle(currentMotivation.isEmpty ? .tertiary : .primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(FocusDeskStyle.focusSurface)
                )
            }

            taskTagsSection
                .padding(.top, 8)
        }
        .contentShape(Rectangle())
        .onHover { isHovered in
            withAnimation(.smooth(duration: 0.12)) {
                isMotivationHovered = isHovered
            }
        }
    }

    private var taskTagsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Tags")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            TaskTagsView(
                task: task,
                availableTags: availableTags,
                onTagsChanged: {
                    task.updatedAt = Date()
                    onTaskChanged()
                }
            )
        }
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
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
            .frame(height: 28)

            if isEditingNextStep {
                nextStepEditor
            } else {
                nextStepContent
            }

            Text(nextStepMetadata)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .allowsTightening(true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
    }

    private var nextStepContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if currentNextStep.isEmpty {
                Text("Add a next step.")
                    .font(FocusDeskStyle.workspaceBodyFont)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            } else {
                activeNextStepRow

                nextStepDivider

                if !remainingNextStepsText.isEmpty {
                    MarkdownText(
                        remainingNextStepsText,
                        font: FocusDeskStyle.workspaceBodyFont
                    )
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .textSelection(.enabled)
    }

    private var nextStepDivider: some View {
        Rectangle()
            .fill(FocusDeskStyle.hairline)
            .frame(height: 1)
            .padding(.top, -2)
            .padding(.bottom, 2)
    }

    private var activeNextStepRow: some View {
        HStack(alignment: .center, spacing: 12) {
            MarkdownText(
                activeNextStepText,
                font: FocusDeskStyle.workspaceBodyFont
            )
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button {
                beginNextStepEditing()
            } label: {
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.teal)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.teal.opacity(0.10))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Edit Next Step")
        }
        .padding(.leading, 14)
        .padding(.trailing, 9)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.teal.opacity(0.05))
        )
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Color.teal.opacity(0.18)) }
    }

    private var nextStepEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: nextStepBinding)
                .font(FocusDeskStyle.workspaceBodyFont)
                .foregroundStyle(.primary)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 180)
                .focused($nextStepEditorFocused)
                .accessibilityLabel("Edit next step")

            if currentNextStep.isEmpty {
                Text("Next step")
                    .font(FocusDeskStyle.workspaceBodyFont)
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
                .font(FocusDeskStyle.workspaceBodyFont)
                .foregroundStyle(.primary)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 100)
                .focused($motivationEditorFocused)
                .accessibilityLabel("Edit why it matters")

            if currentMotivation.isEmpty {
                Text("Add why this task matters.")
                    .font(FocusDeskStyle.workspaceBodyFont)
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
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.primary)
                .focused($currentTaskTitleFocused)
                .accessibilityLabel("Edit current task title")

            ZStack(alignment: .topLeading) {
                TextEditor(text: currentTaskDetailsBinding)
                    .font(FocusDeskStyle.workspaceBodyFont)
                    .foregroundStyle(.secondary)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 100)
                    .focused($currentTaskDetailsFocused)
                    .accessibilityLabel("Edit current task details")

                if task.details.isEmpty {
                    Text("Details")
                        .font(FocusDeskStyle.workspaceBodyFont)
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
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(FocusDeskStyle.focusSurface)
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(FocusDeskStyle.hairline, lineWidth: 1)
            }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(FocusDeskStyle.workspaceSectionFont)
            .foregroundStyle(.primary)
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
                .frame(width: 26, height: 26)
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
                .foregroundStyle(Color.green)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
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
