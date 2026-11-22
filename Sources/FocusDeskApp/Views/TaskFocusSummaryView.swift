import FocusDeskCore
import SwiftUI

private enum DeskInspectorTab: String, CaseIterable {
    case next = "Next step"
    case why = "Why it matters"

    var symbol: String { self == .next ? "arrow.turn.down.right" : "sparkle" }
}

struct TaskFocusSummaryView: View {
    @Bindable var task: FocusTask

    var availableWidth: CGFloat
    var availableTags: [TaskTagRecord]
    var onTaskChanged: () -> Void
    var onComplete: () -> Void
    var onCompleteNextStep: (NextStepChecklist.Item.ID, String) -> Bool
    var onReturnJournalEntry: (UUID) -> Bool
    var compactInspector = false
    var parentTask: FocusTask?
    var subtasks: [FocusTask] = []
    var selectRelated: (UUID) -> Void = { _ in }
    @State private var inspectorTab = DeskInspectorTab.next
    @Namespace private var tabIndicator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        Group {
            if compactInspector { inspector } else { expandedSummary }
        }
        .workspacePanel(fillHeight: compactInspector && availableWidth >= FocusDeskStyle.workspaceCompactBreakpoint)
        .modifier(DeskTransferTarget { (drag: DeskJournalDrag) in
            guard drag.taskID == task.id, onReturnJournalEntry(drag.entryID) else { return false }
            inspectorTab = .next
            return true
        })
    }

    private var expandedSummary: some View {
        WorkspaceColumns(availableWidth: availableWidth) {
            currentTaskColumn
        } trailing: {
            nextStepPanel
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                DeskDetailHeading(title: "Current task", symbol: "scope")
                Spacer()
                DeskDetailEditButton(isEditing: isEditingCurrentTask, section: "current task") {
                    if isEditingCurrentTask { endCurrentTaskEditing() } else { beginCurrentTaskEditing() }
                }
            }
            .frame(minHeight: 28)
            if isEditingCurrentTask {
                inspectorFields
            } else {
                taskTitleBlock
                if let name = task.projectName, !name.isEmpty {
                    Label(name, systemImage: "folder").font(.caption).foregroundStyle(.secondary)
                }
                if let parentTask {
                    relatedTask(parentTask, symbol: "arrow.turn.left.up", prefix: "Parent")
                }
                if !subtasks.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Subtasks").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(subtasks) { child in
                            relatedTask(child, symbol: child.completedAt == nil ? "circle" : "checkmark.circle.fill", prefix: nil)
                        }
                    }
                }
                TaskTagsView(task: task, availableTags: availableTags, onTagsChanged: onTaskChanged, isEditing: false)
                inspectorMenu
                inspectorTabContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func relatedTask(_ related: FocusTask, symbol: String, prefix: String?) -> some View {
        Button { selectRelated(related.id) } label: {
            Label(prefix.map { "\($0) · \(related.title)" } ?? related.title, systemImage: symbol)
                .lineLimit(2)
        }
        .buttonStyle(.plain).font(.callout)
        .disabled(related.completedAt != nil)
        .accessibilityValue(related.completedAt == nil ? "Open" : "Completed")
    }

    private var inspectorFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            currentTaskEditor
            VStack(alignment: .leading, spacing: 5) {
                inspectorEditorLabel("Tags")
                TaskTagsView(task: task, availableTags: availableTags, onTagsChanged: onTaskChanged)
            }
            VStack(alignment: .leading, spacing: 5) {
                inspectorEditorLabel("Next step")
                nextStepEditor
            }
            VStack(alignment: .leading, spacing: 5) {
                inspectorEditorLabel("Why it matters")
                motivationEditor
            }
            Divider()
            Button(action: onComplete) {
                Label("Mark task as complete", systemImage: "checkmark.circle")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var inspectorTabContent: some View {
        if inspectorTab == .next {
            nextStepContent
        } else {
            MarkdownText(motivationText, font: FocusDeskStyle.workspaceBodyFont, emphasisColor: FocusDeskStyle.deskAccent)
                .foregroundStyle(currentMotivation.isEmpty ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private var inspectorMenu: some View {
        HStack(spacing: 14) {
            ForEach(DeskInspectorTab.allCases, id: \.self) { tab in
                let selected = tab == inspectorTab
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) { inspectorTab = tab }
                } label: {
                    Label(tab.rawValue, systemImage: tab.symbol)
                        .font(.system(size: 11, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? FocusDeskStyle.deskAccent : Color.secondary)
                        .frame(height: 29)
                        .overlay(alignment: .bottom) {
                            if selected {
                                Capsule().fill(FocusDeskStyle.deskAccent).frame(height: 2)
                                    .matchedGeometryEffect(id: "selected", in: tabIndicator)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .background(alignment: .bottom) { Divider() }
    }

    private func inspectorEditorLabel(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: compactInspector ? 5 : 14) {
            Text(task.title)
                .font(.system(size: compactInspector ? 14 : 28, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .truncationMode(.tail)
                .accessibilityAddTraits(.isHeader)

            if !task.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                MarkdownText(
                    task.details,
                    font: FocusDeskStyle.workspaceBodyFont,
                    emphasisColor: compactInspector ? FocusDeskStyle.deskAccent : nil
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
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
    }

    private var nextStepContent: some View {
        let source = currentNextStep
        let checklist = NextStepChecklist(source)
        let nextID = checklist.items.first { !$0.isCompleted }?.id
        return VStack(alignment: .leading, spacing: 0) {
            if checklist.items.isEmpty {
                Text("Add a next step.")
                    .font(FocusDeskStyle.workspaceBodyFont)
                    .foregroundStyle(.secondary)
            }
            ForEach(checklist.items) { item in
                let isNext = item.id == nextID
                let status = item.isCompleted ? "Completed" : (isNext ? "Next" : "Upcoming")
                if item.id != checklist.items.first?.id {
                    Divider().accessibilityHidden(true)
                }
                HStack(spacing: 8) {
                    Button {
                        _ = onCompleteNextStep(item.id, source)
                    } label: {
                        Image(systemName: item.isCompleted ? "checkmark.circle.fill" : (isNext ? "smallcircle.filled.circle" : "circle"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(isNext ? Color.primary : Color.secondary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Step " + String(item.id + 1) + ", " + item.text)
                    .accessibilityValue(status)
                    .help(item.isCompleted ? "Move completed step to Journal" : "Complete step and move to Journal")
                    MarkdownText(item.text, font: FocusDeskStyle.workspaceBodyFont.weight(isNext ? .semibold : .regular))
                        .foregroundStyle(item.isCompleted ? .secondary : .primary)
                        .strikethrough(item.isCompleted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    if isNext && !compactInspector {
                        Button(action: beginNextStepEditing) {
                            Image(systemName: "arrow.right").frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain).accessibilityLabel("Edit next step").help("Edit next step")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .draggable(DeskStepDrag(taskID: task.id, stepID: item.id, source: source)) {
                    Text(item.text).lineLimit(2).padding(6)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nextStepEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: nextStepBinding)
                .font(FocusDeskStyle.workspaceBodyFont)
                .foregroundStyle(.primary)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: compactInspector ? 58 : 180)
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
                .frame(height: compactInspector ? 58 : 100)
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
            if compactInspector { inspectorEditorLabel("Title") }
            TextField("Current task", text: currentTaskTitleBinding)
                .textFieldStyle(.plain)
                .font(.system(size: compactInspector ? 14 : 28, weight: .semibold))
                .foregroundStyle(.primary)
                .focused($currentTaskTitleFocused)
                .accessibilityLabel("Edit current task title")

            if compactInspector { inspectorEditorLabel("Details") }
            ZStack(alignment: .topLeading) {
                TextEditor(text: currentTaskDetailsBinding)
                    .font(FocusDeskStyle.workspaceBodyFont)
                    .foregroundStyle(.secondary)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: compactInspector ? 58 : 100)
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
        .accessibilityLabel(help)
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
        .accessibilityLabel(help)
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
}
