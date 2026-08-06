import FocusDeskCore
import SwiftUI

struct TaskFocusSummaryView: View {
    @Bindable var task: FocusTask

    var availableTags: [TaskTagRecord]
    var onTaskChanged: () -> Void
    var onComplete: () -> Void

    @State private var isEditingCurrentTask = false
    @State private var isEditingNextStep = false
    @State private var isCurrentTaskHovered = false
    @State private var isNextStepHovered = false
    @State private var isCurrentTaskActionHovered = false
    @State private var isNextStepActionHovered = false
    @State private var summaryWidth = 0.0
    @FocusState private var currentTaskTitleFocused: Bool
    @FocusState private var currentTaskDetailsFocused: Bool
    @FocusState private var nextStepEditorFocused: Bool

    private let minimumSummaryHeight = 176.0
    private let compactSummaryHeight = 132.0
    private let compactBreakpoint = 610.0
    private let summarySpacing = 16.0

    var body: some View {
        Group {
            if usesCompactLayout {
                VStack(spacing: summarySpacing) {
                    currentTaskPanel

                    nextStepPanel
                }
            } else {
                HStack(alignment: .top, spacing: summarySpacing) {
                    currentTaskPanel
                        .frame(minWidth: 0, maxWidth: .infinity)

                    nextStepPanel
                        .frame(minWidth: 0, maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(summaryWidthReader)
    }

    private var currentTaskPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current Task")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary)
                .padding(.trailing, 64)

            if isEditingCurrentTask {
                currentTaskEditor
            } else {
                Text(task.title)
                    .font(.system(size: currentTitleFontSize, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(usesCompactLayout ? 2 : 3)
                    .minimumScaleFactor(0.5)
                    .allowsTightening(true)
                    .truncationMode(.tail)
                    .accessibilityAddTraits(.isHeader)

                if !task.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    MarkdownText(
                        task.details,
                        font: .system(size: 15, weight: .regular),
                        lineLimit: 4
                    )
                        .foregroundStyle(.secondary)
                        .minimumScaleFactor(0.72)
                        .allowsTightening(true)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 8)

            TaskTagsView(
                task: task,
                availableTags: availableTags,
                onTagsChanged: onTaskChanged
            )
            .padding(.leading, -22)
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: summaryPanelHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(OrbStyle.groupedBackground.opacity(0.78))
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onHover { isHovered in
            withAnimation(.smooth(duration: 0.12)) {
                isCurrentTaskHovered = isHovered
            }
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 2) {
                editingActionButton(
                    systemName: isEditingCurrentTask ? "checkmark" : "pencil",
                    help: isEditingCurrentTask ? "Done editing" : "Edit Current Task",
                    isVisible: isCurrentTaskActionVisible,
                    isHovered: $isCurrentTaskActionHovered,
                    addsOverlayPadding: false,
                    action: isEditingCurrentTask ? endCurrentTaskEditing : beginCurrentTaskEditing
                )

                alwaysVisibleActionButton(
                    systemName: "checkmark.circle",
                    help: "Done",
                    action: onComplete
                )
            }
            .padding(.top, 14)
            .padding(.trailing, 24)
        }
    }

    private var nextStepPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Next Step")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary)
                .padding(.trailing, 34)

            if isEditingNextStep {
                nextStepEditor
            } else {
                MarkdownText(
                    nextStepText,
                    font: .system(size: 13, weight: .regular),
                    lineLimit: usesCompactLayout ? 4 : 8
                )
                    .foregroundStyle(.tertiary)
                    .minimumScaleFactor(0.78)
                    .allowsTightening(true)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            Text(nextStepMetadata)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .allowsTightening(true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: summaryPanelHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(OrbStyle.sidebarBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .onHover { isHovered in
            withAnimation(.smooth(duration: 0.12)) {
                isNextStepHovered = isHovered
            }
        }
        .overlay(alignment: .topTrailing) {
            editingActionButton(
                systemName: isEditingNextStep ? "checkmark" : "pencil",
                help: isEditingNextStep ? "Done editing" : "Edit Next Step",
                isVisible: isNextStepActionVisible,
                isHovered: $isNextStepActionHovered,
                action: isEditingNextStep ? endNextStepEditing : beginNextStepEditing
            )
        }
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
                .foregroundStyle(.secondary)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: usesCompactLayout ? 58 : 88)
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
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.66))
        )
    }

    private var currentTaskEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Current task", text: currentTaskTitleBinding)
                .textFieldStyle(.plain)
                .font(.system(size: usesCompactLayout ? 20 : 24, weight: .semibold))
                .foregroundStyle(.primary)
                .focused($currentTaskTitleFocused)
                .accessibilityLabel("Edit current task title")

            ZStack(alignment: .topLeading) {
                TextEditor(text: currentTaskDetailsBinding)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: usesCompactLayout ? 42 : 58)
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
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.62))
            )
        }
    }

    private func editingActionButton(
        systemName: String,
        help: String,
        isVisible: Bool,
        isHovered: Binding<Bool>,
        addsOverlayPadding: Bool = true,
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
        .padding(.top, addsOverlayPadding ? 14 : 0)
        .padding(.trailing, addsOverlayPadding ? 24 : 0)
    }

    private func alwaysVisibleActionButton(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
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

    private var summaryPanelHeight: Double {
        usesCompactLayout ? compactSummaryHeight : minimumSummaryHeight
    }

    private var currentTitleFontSize: Double {
        usesCompactLayout ? 26.0 : 34.0
    }

    private var isCurrentTaskActionVisible: Bool {
        true
    }

    private var isNextStepActionVisible: Bool {
        isEditingNextStep || isNextStepHovered || isNextStepActionHovered
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

    private var nextStepText: String {
        currentNextStep.isEmpty ? "Add a next step." : currentNextStep
    }

    private var nextStepMetadata: String {
        if currentNextStep.isEmpty {
            return "No next step yet"
        }

        return "Editable next step"
    }
}
