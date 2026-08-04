import AppKit
import FocusCarouselCore
import SwiftData
import SwiftUI

private enum MainSection {
    case desk
    case newTask
    case tasks
    case completed
}

struct MainCarouselView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \FocusTask.carouselOrder, order: .forward)
    private var tasks: [FocusTask]

    @AppStorage("currentTaskID")
    private var currentTaskIDRaw = ""

    @State private var selectedSection: MainSection = .desk
    @State private var completionToast: CompletionToast?
    @State private var toastDismissalTask: Task<Void, Never>?
    @State private var isSavingStep = false
    @State private var isSidebarVisible = true
    @State private var sidebarDragStartWidth: Double?
    @State private var taskToDelete: FocusTask?
    @State private var showingGoogleCloudSettings = false

    @AppStorage("sidebarWidth")
    private var sidebarWidth = 174.0

    @AppStorage("isDarkTheme")
    private var isDarkTheme = false

    @AppStorage("googleOAuthClientID")
    private var googleOAuthClientID = ""

    @AppStorage("googleAccountDisplayName")
    private var googleAccountDisplayName = ""

    @AppStorage("googleAccountEmail")
    private var googleAccountEmail = ""

    @FocusState private var noteFocused: Bool

    private let router = CarouselRouter()
    private let serverClock = OfflineFirstServerClock.environmentBacked()
    private let defaultSidebarWidth = 174.0
    private let maxSidebarWidth = 260.0
    private let sidebarCollapseThreshold = 1.0
    private let workspaceHorizontalPadding = 28.0

    private var activeTasks: [FocusTask] {
        tasks
            .filter { $0.completedAt == nil }
            .sorted { lhs, rhs in
                if lhs.carouselOrder == rhs.carouselOrder {
                    return lhs.createdAt < rhs.createdAt
                }

                return lhs.carouselOrder < rhs.carouselOrder
            }
    }

    private var currentTaskID: UUID? {
        UUID(uuidString: currentTaskIDRaw)
    }

    private var currentTask: FocusTask? {
        if let currentTaskID, let selected = activeTasks.first(where: { $0.id == currentTaskID }) {
            return selected
        }

        return activeTasks.first
    }

    private var activeTaskIDs: [UUID] {
        activeTasks.map(\.id)
    }

    private var completedTasks: [FocusTask] {
        tasks
            .filter { $0.completedAt != nil }
            .sorted {
                ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
            }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 0) {
                if isSidebarVisible && sidebarWidth > sidebarCollapseThreshold {
                    sidebar
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(OrbStyle.appBackground)
            }
            .background(OrbStyle.appBackground)
            .ignoresSafeArea(edges: .top)
            .background(WindowChromeConfigurator())

            if let completionToast {
                CompletionToastView(
                    toast: completionToast,
                    undo: undoCompletion
                )
                .padding(18)
                .transition(AnyTransition.move(edge: .top).combined(with: .opacity))
            }

            if !isSidebarVisible {
                sidebarToggleButton(systemImage: "sidebar.right") {
                    showSidebar()
                }
                .padding(.top, 10)
                .padding(.leading, 116)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .animation(.spring(duration: 0.34, bounce: 0.16), value: currentTaskIDRaw)
        .animation(.spring(duration: 0.28, bounce: 0.12), value: completionToast?.id)
        .animation(.spring(duration: 0.26, bounce: 0.12), value: isSidebarVisible)
        .animation(.spring(duration: 0.26, bounce: 0.12), value: sidebarWidth)
        .onAppear {
            isSidebarVisible = sidebarWidth > sidebarCollapseThreshold
            ensureValidSelection()
            refreshWidgetSnapshot()
            noteFocused = true
        }
        .onChange(of: activeTaskIDs) {
            ensureValidSelection()
            refreshWidgetSnapshot()
        }
        .onChange(of: currentTaskIDRaw) {
            refreshWidgetSnapshot()
        }
        .sheet(isPresented: $showingGoogleCloudSettings) {
            GoogleCloudSettingsView(
                oauthClientID: $googleOAuthClientID,
                displayName: googleAccountDisplayName,
                email: googleAccountEmail
            )
        }
        .alert("Delete task?", isPresented: deletingTaskBinding) {
            Button("Delete", role: .destructive) {
                if let taskToDelete {
                    delete(taskToDelete)
                }
            }

            Button("Cancel", role: .cancel) {
                taskToDelete = nil
            }
        } message: {
            Text("This removes the task and its journal.")
        }
    }

    private var sidebar: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(OrbStyle.sidebarBackground)
                .padding(.leading, 4)
                .padding(.top, 4)
                .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 18) {
                Text("Focus Desk")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 18)
                    .padding(.top, 48)

                OrbSidebarSection(title: "Focus") {
                    OrbSidebarButton(
                        title: "Desk",
                        systemImage: "circle.dashed",
                        isSelected: selectedSection == .desk,
                        count: activeTasks.count
                    ) {
                        selectedSection = .desk
                        ensureValidSelection()
                    }

                    OrbSidebarButton(
                        title: "New Task",
                        systemImage: "plus.square.on.square",
                        isSelected: selectedSection == .newTask
                    ) {
                        selectedSection = .newTask
                    }
                    .keyboardShortcut("n", modifiers: [.command])
                }

                OrbSidebarSection(title: "Manage") {
                    OrbSidebarButton(
                        title: "Tasks",
                        systemImage: "tray.full",
                        isSelected: selectedSection == .tasks,
                        count: activeTasks.count
                    ) {
                        selectedSection = .tasks
                    }

                    OrbSidebarButton(
                        title: "Completed",
                        systemImage: "checkmark.circle",
                        isSelected: selectedSection == .completed,
                        count: completedTasks.count
                    ) {
                        selectedSection = .completed
                    }
                }

                Spacer(minLength: 12)

                CloudAccountSidebarView(
                    displayName: googleAccountDisplayName,
                    email: googleAccountEmail,
                    isConfigured: !googleOAuthClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    showingGoogleCloudSettings = true
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 18)
            .clipped()

            sidebarToggleButton(systemImage: "sidebar.left") {
                hideSidebar()
            }
            .padding(.top, 10)
            .padding(.trailing, 15)

            sidebarResizeHandle
        }
        .frame(width: sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var sidebarResizeHandle: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.001))
            .frame(width: 12)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { isHovering in
                if isHovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if sidebarDragStartWidth == nil {
                            sidebarDragStartWidth = sidebarWidth
                        }

                        let startWidth = sidebarDragStartWidth ?? sidebarWidth
                        setSidebarWidth(startWidth + value.translation.width)
                    }
                    .onEnded { _ in
                        sidebarDragStartWidth = nil
                    }
            )
            .padding(.top, 4)
            .padding(.bottom, 8)
    }

    private func sidebarToggleButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isSidebarVisible ? "Hide Sidebar" : "Show Sidebar")
    }

    private func setSidebarWidth(_ width: Double) {
        let clampedWidth = min(max(width, 0), maxSidebarWidth)

        if clampedWidth <= sidebarCollapseThreshold {
            sidebarWidth = 0
            isSidebarVisible = false
        } else {
            sidebarWidth = clampedWidth
            isSidebarVisible = true
        }
    }

    private func hideSidebar() {
        withAnimation(.spring(duration: 0.26, bounce: 0.12)) {
            sidebarWidth = 0
            isSidebarVisible = false
        }
    }

    private func showSidebar() {
        withAnimation(.spring(duration: 0.26, bounce: 0.12)) {
            if sidebarWidth <= sidebarCollapseThreshold {
                sidebarWidth = defaultSidebarWidth
            }

            isSidebarVisible = true
        }
    }

    private var detail: some View {
        VStack(spacing: 0) {
            detailToolbar

            Group {
                switch selectedSection {
                case .desk:
                    if let task = currentTask {
                        taskWorkspace(task)
                    } else {
                        EmptyCarouselView {
                            selectedSection = .newTask
                        }
                    }
                case .newTask:
                    newTaskWorkspace
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                case .tasks:
                    manageWorkspace(.tasks)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                case .completed:
                    manageWorkspace(.completed)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var detailToolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(toolbarTitle)
                    .font(.system(size: 26, weight: .semibold))

                Text(toolbarSubtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if selectedSection == .desk {
                Button {
                    selectPreviousTask()
                } label: {
                    Label("Previous", systemImage: "chevron.left")
                }
                .labelStyle(.iconOnly)
                .keyboardShortcut(.leftArrow, modifiers: [])
                .help("Previous Task")

                Button {
                    selectNextTask()
                } label: {
                    Label("Next", systemImage: "chevron.right")
                }
                .labelStyle(.iconOnly)
                .keyboardShortcut(.rightArrow, modifiers: [])
                .help("Next Task")
            }

            if selectedSection != .newTask {
                Button {
                    selectedSection = .newTask
                } label: {
                    Label("New Task", systemImage: "plus")
                }
                .labelStyle(.iconOnly)
                .help("New Task")
            }

            Button {
                isDarkTheme.toggle()
            } label: {
                Label(isDarkTheme ? "Light Theme" : "Dark Theme", systemImage: isDarkTheme ? "sun.max" : "moon")
            }
            .labelStyle(.iconOnly)
            .help(isDarkTheme ? "Switch to Light Theme" : "Switch to Dark Theme")
        }
        .padding(.horizontal, 28)
        .padding(.top, 30)
        .padding(.bottom, 18)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            toggleWindowZoom()
        }
    }

    private var toolbarTitle: String {
        switch selectedSection {
        case .desk:
            return "Desk"
        case .newTask:
            return "New Task"
        case .tasks:
            return "Tasks"
        case .completed:
            return "Completed"
        }
    }

    private var toolbarSubtitle: String {
        switch selectedSection {
        case .newTask:
            return "Create a focused task"
        case .tasks:
            return activeTasks.count == 1 ? "1 active task" : "\(activeTasks.count) active tasks"
        case .completed:
            return completedTasks.count == 1 ? "1 completed task" : "\(completedTasks.count) completed tasks"
        case .desk:
            break
        }

        if activeTasks.isEmpty {
            return "No active tasks"
        }

        if activeTasks.count == 1 {
            return "1 active task"
        }

        return "\(activeTasks.count) active tasks"
    }

    private var newTaskWorkspace: some View {
        GeometryReader { proxy in
            let contentWidth = max(0, proxy.size.width - (workspaceHorizontalPadding * 2))

            ScrollView {
                NewTaskWorkspaceView(
                    onCreate: { draft in
                        createTask(draft)
                    },
                    onCancel: {
                        selectedSection = .desk
                    }
                )
                .frame(minWidth: contentWidth, maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, workspaceHorizontalPadding)
                .padding(.top, 34)
                .padding(.bottom, 28)
                .frame(minWidth: proxy.size.width, maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private func manageWorkspace(_ mode: ManageWorkspaceMode) -> some View {
        GeometryReader { proxy in
            let contentWidth = max(0, proxy.size.width - (workspaceHorizontalPadding * 2))

            ScrollView {
                ManageWorkspaceView(
                    mode: mode,
                    activeTasks: activeTasks,
                    completedTasks: completedTasks,
                    onOpen: { task in
                        select(task.id)
                    },
                    onComplete: { task in
                        complete(task)
                    },
                    onRestore: { task in
                        restore(task)
                    },
                    onDelete: { task in
                        taskToDelete = task
                    },
                    onCreate: {
                        selectedSection = .newTask
                    }
                )
                .frame(minWidth: contentWidth, maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, workspaceHorizontalPadding)
                .padding(.top, 34)
                .padding(.bottom, 28)
                .frame(minWidth: proxy.size.width, maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private func taskWorkspace(_ task: FocusTask) -> some View {
        GeometryReader { proxy in
            let contentWidth = max(0, proxy.size.width - (workspaceHorizontalPadding * 2))

            ScrollView {
                VStack(spacing: 16) {
                    TaskFocusSummaryView(
                        task: task,
                        onTaskChanged: saveContext,
                        onComplete: {
                            complete(task)
                        }
                    )
                        .id("summary-\(task.id.uuidString)")
                        .transition(.opacity.combined(with: .move(edge: .trailing)))

                    MotivationBlockView(task: task, onMotivationChanged: saveContext)

                    TaskCardView(
                        task: task,
                        showsHeader: false,
                        isSavingStep: isSavingStep,
                        noteFocused: $noteFocused,
                        onDraftChanged: saveContext,
                        onSaveJournalEntry: {
                            saveJournalEntry(task)
                        },
                        onJournalEntryChanged: {
                            task.updatedAt = Date()
                            saveContext()
                            refreshWidgetSnapshot()
                        },
                        onDeleteJournalEntry: { entry in
                            deleteJournalEntry(entry, from: task)
                        }
                    )
                    .id(task.id)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    .gesture(
                        DragGesture(minimumDistance: 36)
                            .onEnded { value in
                                if value.translation.width <= -42 {
                                    selectNextTask()
                                } else if value.translation.width >= 42 {
                                    selectPreviousTask()
                                }
                            }
                    )
                }
                .frame(minWidth: contentWidth, maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, workspaceHorizontalPadding)
                .padding(.top, 34)
                .padding(.bottom, 28)
                .frame(minWidth: proxy.size.width, maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private func createTask(_ draft: NewTaskDraft) {
        createTask(
            title: draft.title,
            details: draft.details,
            nextStep: draft.nextStep,
            motivation: draft.motivation,
            initialJournalEntry: draft.initialJournalEntry
        )
    }

    private func createTask(title: String, details: String) {
        createTask(title: title, details: details, nextStep: "", motivation: "", initialJournalEntry: "")
    }

    private func createTask(
        title: String,
        details: String,
        nextStep: String,
        motivation: String,
        initialJournalEntry: String
    ) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNextStep = nextStep.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMotivation = motivation.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedJournalEntry = initialJournalEntry.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTitle.isEmpty else {
            return
        }

        let nextOrder = (tasks.map(\.carouselOrder).max() ?? -1) + 1
        let now = Date()
        let task = FocusTask(
            title: trimmedTitle,
            details: trimmedDetails,
            createdAt: now,
            updatedAt: now,
            carouselOrder: nextOrder,
            motivation: trimmedMotivation.isEmpty ? nil : trimmedMotivation,
            nextStep: trimmedNextStep.isEmpty ? nil : trimmedNextStep
        )

        if !trimmedJournalEntry.isEmpty {
            let entry = ProgressEntry(note: trimmedJournalEntry, timestamp: now, task: task)
            task.entries.append(entry)
        }

        modelContext.insert(task)
        saveContext()
        select(task.id)
        refreshWidgetSnapshot()
    }

    private func saveJournalEntry(_ task: FocusTask) {
        let note = task.localDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !note.isEmpty else {
            return
        }

        isSavingStep = true

        Task {
            let timestamp = (try? await serverClock.now()) ?? Date()

            await MainActor.run {
                let entry = ProgressEntry(note: note, timestamp: timestamp, task: task)
                task.entries.append(entry)
                task.localDraft = ""
                task.updatedAt = timestamp
                saveContext()
                refreshWidgetSnapshot()
                isSavingStep = false
            }
        }
    }

    private func deleteJournalEntry(_ entry: ProgressEntry, from task: FocusTask) {
        modelContext.delete(entry)
        task.updatedAt = Date()
        saveContext()
        refreshWidgetSnapshot()
    }

    private func complete(_ task: FocusTask) {
        let nextID = nextActiveTaskID(after: task.id, excluding: task.id)
        task.completedAt = Date()
        task.updatedAt = Date()
        saveContext()

        if let nextID {
            select(nextID)
        } else {
            currentTaskIDRaw = ""
        }

        showCompletionToast(for: task)
        refreshWidgetSnapshot()
    }

    private func restore(_ task: FocusTask) {
        task.completedAt = nil
        task.updatedAt = Date()
        saveContext()
        select(task.id)
        refreshWidgetSnapshot()
    }

    private func delete(_ task: FocusTask) {
        let replacementSelection = activeTasks.first { $0.id != task.id }?.id.uuidString ?? ""

        modelContext.delete(task)
        saveContext()

        if currentTaskIDRaw == task.id.uuidString {
            currentTaskIDRaw = replacementSelection
        }

        taskToDelete = nil
        refreshWidgetSnapshot()
    }

    private var deletingTaskBinding: Binding<Bool> {
        Binding(
            get: { taskToDelete != nil },
            set: { isPresented in
                if !isPresented {
                    taskToDelete = nil
                }
            }
        )
    }

    private func showCompletionToast(for task: FocusTask) {
        toastDismissalTask?.cancel()
        completionToast = CompletionToast(taskID: task.id, title: task.title)

        toastDismissalTask = Task {
            try? await Task.sleep(for: .seconds(5))

            await MainActor.run {
                if completionToast?.taskID == task.id {
                    completionToast = nil
                }
            }
        }
    }

    private func undoCompletion() {
        guard let completionToast else {
            return
        }

        toastDismissalTask?.cancel()

        guard let task = tasks.first(where: { $0.id == completionToast.taskID }) else {
            self.completionToast = nil
            return
        }

        task.completedAt = nil
        task.updatedAt = Date()
        saveContext()
        select(task.id)
        self.completionToast = nil
        refreshWidgetSnapshot()
    }

    private func selectPreviousTask() {
        let snapshots = activeTasks.map(\.snapshot)
        guard let previous = router.previousTask(in: snapshots, before: currentTask?.id) else {
            return
        }

        select(previous.id)
    }

    private func selectNextTask() {
        let snapshots = activeTasks.map(\.snapshot)
        guard let next = router.nextTask(in: snapshots, after: currentTask?.id) else {
            return
        }

        select(next.id)
    }

    private func nextActiveTaskID(after taskID: UUID, excluding excludedID: UUID) -> UUID? {
        let snapshots = activeTasks
            .filter { $0.id != excludedID }
            .map(\.snapshot)

        return router.nextTask(in: snapshots, after: taskID)?.id ?? snapshots.first?.id
    }

    private func select(_ id: UUID) {
        selectedSection = .desk
        currentTaskIDRaw = id.uuidString
        noteFocused = true
    }

    private func toggleWindowZoom() {
        NSApplication.shared.keyWindow?.zoom(nil)
    }

    private func ensureValidSelection() {
        guard let selected = router.currentTask(in: activeTasks.map(\.snapshot), selectedID: currentTaskID) else {
            currentTaskIDRaw = ""
            return
        }

        if selected.id != currentTaskID {
            currentTaskIDRaw = selected.id.uuidString
        }
    }

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            assertionFailure("Unable to save Focus Desk state: \(error)")
        }
    }

    private func refreshWidgetSnapshot() {
        WidgetSnapshotWriter.write(currentTask: currentTask, activeTaskCount: activeTasks.count)
    }
}

private enum ManageWorkspaceMode {
    case tasks
    case completed

    var emptyTitle: String {
        switch self {
        case .tasks:
            return "No active tasks"
        case .completed:
            return "No completed tasks"
        }
    }

    var emptySubtitle: String {
        switch self {
        case .tasks:
            return "Create a task to start your desk."
        case .completed:
            return "Finished tasks will appear here."
        }
    }

    var emptyIcon: String {
        switch self {
        case .tasks:
            return "tray.full"
        case .completed:
            return "checkmark.circle"
        }
    }
}

private struct ManageWorkspaceView: View {
    var mode: ManageWorkspaceMode
    var activeTasks: [FocusTask]
    var completedTasks: [FocusTask]
    var onOpen: (FocusTask) -> Void
    var onComplete: (FocusTask) -> Void
    var onRestore: (FocusTask) -> Void
    var onDelete: (FocusTask) -> Void
    var onCreate: () -> Void

    private var visibleTasks: [FocusTask] {
        switch mode {
        case .tasks:
            return activeTasks
        case .completed:
            return completedTasks
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if visibleTasks.isEmpty {
                emptyState
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(visibleTasks) { task in
                        ManageTaskRow(
                            task: task,
                            mode: mode,
                            onOpen: onOpen,
                            onComplete: onComplete,
                            onRestore: onRestore,
                            onDelete: onDelete
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var emptyState: some View {
        OrbGroupedPanel {
            VStack(spacing: 10) {
                OrbIcon(systemName: mode.emptyIcon, filled: true)

                Text(mode.emptyTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(mode.emptySubtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.tertiary)

                if mode == .tasks {
                    Button {
                        onCreate()
                    } label: {
                        Label("New Task", systemImage: "plus")
                    }
                    .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 180)
            .padding(18)
        }
    }
}

private struct ManageTaskRow: View {
    var task: FocusTask
    var mode: ManageWorkspaceMode
    var onOpen: (FocusTask) -> Void
    var onComplete: (FocusTask) -> Void
    var onRestore: (FocusTask) -> Void
    var onDelete: (FocusTask) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            OrbIcon(
                systemName: mode == .tasks ? "rectangle.stack" : "checkmark.circle",
                filled: true
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if !task.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(task.details)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(rowMetadata)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                switch mode {
                case .tasks:
                    rowAction(systemImage: "arrow.forward", help: "Open Task") {
                        onOpen(task)
                    }

                    rowAction(systemImage: "checkmark", help: "Mark Completed") {
                        onComplete(task)
                    }
                case .completed:
                    rowAction(systemImage: "arrow.uturn.backward", help: "Restore Task") {
                        onRestore(task)
                    }
                }

                rowAction(systemImage: "trash", help: "Delete Task", role: .destructive) {
                    onDelete(task)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(OrbStyle.groupedBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func rowAction(
        systemImage: String,
        help: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(actionForeground(role: role))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func actionForeground(role: ButtonRole?) -> Color {
        if role == .destructive {
            return .red.opacity(0.75)
        }

        return Color(nsColor: .secondaryLabelColor)
    }

    private var rowMetadata: String {
        if let completedAt = task.completedAt {
            return "Completed \(DateFormatting.journalString(from: completedAt))"
        }

        if let latest = task.latestEntry {
            return "Last worked \(DateFormatting.journalString(from: latest.timestamp))"
        }

        return "Created \(DateFormatting.journalString(from: task.createdAt))"
    }
}

private struct CloudAccountSidebarView: View {
    var displayName: String
    var email: String
    var isConfigured: Bool
    var action: () -> Void

    private var isConnected: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var title: String {
        if isConnected {
            return displayName
        }

        return "Sign in with Google"
    }

    private var subtitle: String {
        if isConnected {
            return email
        }

        return isConfigured ? "Ready to connect" : "Cloud sync off"
    }

    var body: some View {
        VStack(spacing: 10) {
            Rectangle()
                .fill(OrbStyle.hairline)
                .frame(height: 1)

            Button(action: action) {
                HStack(spacing: 10) {
                    accountAvatar

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text(subtitle)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .frame(height: 54)
                .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(isConnected ? "Google account" : "Sign in with Google")
        }
    }

    private var accountAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.secondary.opacity(0.14))

            if isConnected {
                Text(initials)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 38, height: 38)
    }

    private var initials: String {
        let parts = displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)

        let value = String(parts).uppercased()
        return value.isEmpty ? "G" : value
    }
}

private struct GoogleCloudSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var oauthClientID: String
    var displayName: String
    var email: String

    private var isConnected: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                OrbIcon(systemName: "person.crop.circle.badge.plus", filled: true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Google Cloud Sync")
                        .font(.system(size: 24, weight: .semibold))

                    Text(isConnected ? email : "Not connected")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }

            OrbGroupedPanel {
                VStack(alignment: .leading, spacing: 12) {
                    Text("OAuth Client ID")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.primary)

                    TextField("Paste Google OAuth client ID", text: $oauthClientID)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .regular))
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(nsColor: .textBackgroundColor).opacity(0.66))
                        )

                    Text("Cloud data will use Google Drive app data storage after sign-in is wired.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
            }

            OrbGroupedPanel {
                VStack(alignment: .leading, spacing: 10) {
                    settingsRow(title: "Provider", value: "Google")
                    settingsRow(title: "Storage", value: "Drive app data")
                    settingsRow(title: "Scope", value: "drive.appdata")
                }
                .padding(18)
            }

            HStack {
                Button {
                    openGoogleCredentials()
                } label: {
                    Label("Google Cloud", systemImage: "safari")
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500)
        .background(OrbStyle.appBackground)
    }

    private func settingsRow(title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func openGoogleCredentials() {
        guard let url = URL(string: "https://console.cloud.google.com/apis/credentials") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}

private struct NewTaskDraft {
    var title = ""
    var details = ""
    var nextStep = ""
    var motivation = ""
    var initialJournalEntry = ""

    var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasContent: Bool {
        [
            title,
            details,
            nextStep,
            motivation,
            initialJournalEntry
        ]
            .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

private enum NewTaskFocusField: Hashable {
    case title
    case details
    case nextStep
    case motivation
    case initialJournalEntry
}

private struct NewTaskWorkspaceView: View {
    var onCreate: (NewTaskDraft) -> Void
    var onCancel: () -> Void

    @State private var draft = NewTaskDraft()
    @State private var workspaceWidth = 0.0
    @FocusState private var focusedField: NewTaskFocusField?

    private let compactBreakpoint = 610.0
    private let panelSpacing = 16.0
    private let regularPanelHeight = 176.0
    private let compactPanelHeight = 152.0

    var body: some View {
        VStack(spacing: 16) {
            if usesCompactLayout {
                VStack(spacing: panelSpacing) {
                    taskPanel
                    nextStepPanel
                }
            } else {
                HStack(alignment: .top, spacing: panelSpacing) {
                    taskPanel
                        .frame(minWidth: 0, maxWidth: .infinity)

                    nextStepPanel
                        .frame(minWidth: 0, maxWidth: .infinity)
                }
            }

            oneLineBlock(
                text: $draft.motivation,
                placeholder: "Your motivation",
                focusField: .motivation
            )

            oneLineBlock(
                text: $draft.initialJournalEntry,
                placeholder: "What was done",
                focusField: .initialJournalEntry
            )

            actionFooter
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(widthReader)
        .onAppear {
            focusedField = .title
        }
    }

    private var taskPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Task")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary)

            ZStack(alignment: .leading) {
                TextField("", text: $draft.title)
                    .textFieldStyle(.plain)
                    .font(.system(size: usesCompactLayout ? 22 : 26, weight: .semibold))
                    .foregroundStyle(.primary)
                    .focused($focusedField, equals: .title)
                    .accessibilityLabel("Task title")

                if draft.title.isEmpty {
                    Text("Task title")
                        .font(.system(size: usesCompactLayout ? 22 : 26, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                }
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $draft.details)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: usesCompactLayout ? 48 : 64)
                    .focused($focusedField, equals: .details)
                    .accessibilityLabel("Details")

                if draft.details.isEmpty {
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

            Spacer(minLength: 8)
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: panelHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(OrbStyle.groupedBackground.opacity(0.78))
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var nextStepPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Next Step")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $draft.nextStep)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: usesCompactLayout ? 88 : 108)
                    .focused($focusedField, equals: .nextStep)
                    .accessibilityLabel("Next step")

                if draft.nextStep.isEmpty {
                    Text("Add a next step")
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

            Spacer(minLength: 8)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: panelHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(OrbStyle.sidebarBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func oneLineBlock(
        text: Binding<String>,
        placeholder: String,
        focusField: NewTaskFocusField
    ) -> some View {
        ZStack(alignment: .leading) {
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.tertiary)
                .focused($focusedField, equals: focusField)
                .accessibilityLabel(placeholder)

            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 17)
        .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(OrbStyle.sidebarBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var actionFooter: some View {
        HStack(spacing: 10) {
            Button {
                resetDraft()
            } label: {
                Label("Clear", systemImage: "xmark")
            }
            .disabled(!draft.hasContent)

            Button("Cancel") {
                onCancel()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button {
                submitDraft()
            } label: {
                Label("Create Task", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!draft.canCreate)
        }
        .padding(.top, 2)
    }

    private var widthReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    updateWorkspaceWidth(proxy.size.width)
                }
                .onChange(of: proxy.size.width) { _, newWidth in
                    updateWorkspaceWidth(newWidth)
                }
        }
    }

    private var usesCompactLayout: Bool {
        workspaceWidth > 0 && workspaceWidth < compactBreakpoint
    }

    private var panelHeight: Double {
        usesCompactLayout ? compactPanelHeight : regularPanelHeight
    }

    private func updateWorkspaceWidth(_ width: Double) {
        let normalizedWidth = max(0, width)

        if abs(workspaceWidth - normalizedWidth) > 0.5 {
            workspaceWidth = normalizedWidth
        }
    }

    private func resetDraft() {
        withAnimation(.smooth(duration: 0.18)) {
            draft = NewTaskDraft()
        }

        focusedField = .title
    }

    private func submitDraft() {
        guard draft.canCreate else {
            return
        }

        onCreate(draft)
        resetDraft()
    }
}

private struct MotivationBlockView: View {
    @Bindable var task: FocusTask
    var onMotivationChanged: () -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            TextField("", text: motivationText)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Your motivation")

            if currentMotivation.isEmpty {
                Text("Your motivation")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 17)
        .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(OrbStyle.sidebarBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var currentMotivation: String {
        task.motivation ?? ""
    }

    private var motivationText: Binding<String> {
        Binding(
            get: {
                task.motivation ?? ""
            },
            set: { newValue in
                task.motivation = newValue
                task.updatedAt = Date()
                onMotivationChanged()
            }
        )
    }
}

struct CompletionToast: Identifiable, Equatable {
    var id = UUID()
    var taskID: UUID
    var title: String
}
