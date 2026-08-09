import AppKit
import Charts
import FocusDeskCore
import SwiftData
import SwiftUI

private enum MainSection: Equatable {
    case desk
    case newTask
    case tasks
    case completed
    case summary
    case allTags
    case tag(String)
}

private struct SidebarTagItem: Identifiable {
    var tag: TaskTagRecord
    var normalizedName: String
    var activeTaskCount: Int

    var id: String {
        normalizedName
    }
}

struct MainDeskView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \FocusTask.sortOrder, order: .forward)
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

    @AppStorage("isTagsSidebarSectionExpanded")
    private var isTagsSidebarSectionExpanded = true

    @AppStorage("googleOAuthClientID")
    private var googleOAuthClientID = ""

    @AppStorage("googleAccountDisplayName")
    private var googleAccountDisplayName = ""

    @AppStorage("googleAccountEmail")
    private var googleAccountEmail = ""

    @FocusState private var noteFocused: Bool

    private let router = DeskRouter()
    private let serverClock = OfflineFirstServerClock.environmentBacked()
    private let defaultSidebarWidth = 174.0
    private let minExpandedSidebarWidth = 132.0
    private let maxSidebarWidth = 260.0
    private let sidebarCollapseThreshold = 72.0
    private let collapsedSidebarWidth = 58.0
    private let collapsedSidebarBackgroundTopPadding = 62.0
    private let collapsedSidebarControlTopPadding = 74.0
    private let workspaceHorizontalPadding = 28.0

    private var activeTasks: [FocusTask] {
        tasks
            .filter { $0.completedAt == nil }
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.createdAt < rhs.createdAt
                }

                return lhs.sortOrder < rhs.sortOrder
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

    private var activeTaggedTasks: [FocusTask] {
        activeTasks.filter { !$0.enabledTagRecords.isEmpty }
    }

    private var journalEntriesTodayCount: Int {
        let calendar = Calendar.current
        return tasks
            .flatMap(\.entries)
            .filter { calendar.isDateInToday($0.timestamp) }
            .count
    }

    private var availableTagRecords: [TaskTagRecord] {
        var seenNames = Set<String>()
        var uniqueTags: [TaskTagRecord] = []

        for tag in tasks.flatMap(\.enabledTagRecords) {
            let normalizedName = normalizedTagName(tag.name)

            guard !normalizedName.isEmpty, !seenNames.contains(normalizedName) else {
                continue
            }

            seenNames.insert(normalizedName)
            uniqueTags.append(tag)
        }

        return uniqueTags.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var sidebarTagItems: [SidebarTagItem] {
        availableTagRecords.map { tag in
            let normalizedName = normalizedTagName(tag.name)
            return SidebarTagItem(
                tag: tag,
                normalizedName: normalizedName,
                activeTaskCount: activeTasks.filter { task in
                    task.enabledTagRecords.contains { taskTag in
                        normalizedTagName(taskTag.name) == normalizedName
                    }
                }.count
            )
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 0) {
                if isSidebarVisible && sidebarWidth > sidebarCollapseThreshold {
                    sidebar
                        .transition(.move(edge: .leading).combined(with: .opacity))
                } else {
                    collapsedSidebar
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(FocusDeskStyle.appBackground)
            }
            .background(FocusDeskStyle.appBackground)
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
        }
        .animation(.spring(duration: 0.34, bounce: 0.16), value: currentTaskIDRaw)
        .animation(.spring(duration: 0.28, bounce: 0.12), value: completionToast?.id)
        .animation(.spring(duration: 0.26, bounce: 0.12), value: isSidebarVisible)
        .animation(.spring(duration: 0.26, bounce: 0.12), value: sidebarWidth)
        .onAppear {
            normalizeSidebarWidth()
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
                .fill(FocusDeskStyle.sidebarBackground)
                .padding(.leading, 4)
                .padding(.top, 4)
                .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 14) {
                Text("Focus Desk")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 14)
                    .padding(.top, 48)

                FocusDeskSidebarSection(title: "Focus") {
                    FocusDeskSidebarButton(
                        title: "Desk",
                        systemImage: "circle.dashed",
                        isSelected: selectedSection == .desk,
                        count: activeTasks.count,
                        iconColor: .orange
                    ) {
                        selectedSection = .desk
                        ensureValidSelection()
                    }

                    FocusDeskSidebarButton(
                        title: "New Task",
                        systemImage: "plus.square.on.square",
                        isSelected: selectedSection == .newTask,
                        iconColor: .blue
                    ) {
                        selectedSection = .newTask
                    }
                    .keyboardShortcut("n", modifiers: [.command])
                }

                FocusDeskSidebarSection(title: "Manage") {
                    FocusDeskSidebarButton(
                        title: "Tasks",
                        systemImage: "tray.full",
                        isSelected: selectedSection == .tasks,
                        count: activeTasks.count,
                        iconColor: .mint
                    ) {
                        selectedSection = .tasks
                    }

                    FocusDeskSidebarButton(
                        title: "Completed",
                        systemImage: "checkmark.circle",
                        isSelected: selectedSection == .completed,
                        count: completedTasks.count,
                        iconColor: .green
                    ) {
                        selectedSection = .completed
                    }

                    FocusDeskSidebarButton(
                        title: "Summary",
                        systemImage: "chart.bar.xaxis",
                        isSelected: selectedSection == .summary,
                        count: journalEntriesTodayCount,
                        iconColor: .purple
                    ) {
                        selectedSection = .summary
                    }
                }

                FocusDeskSidebarSection(title: "Tags", isExpanded: $isTagsSidebarSectionExpanded) {
                    if sidebarTagItems.isEmpty {
                        SidebarEmptyLabel("No tags yet")
                    } else {
                        ForEach(sidebarTagItems) { item in
                            let palette = TaskTagPalette.palette(for: item.tag.colorName)

                            FocusDeskSidebarTagButton(
                                title: item.tag.name,
                                isSelected: selectedSection == .tag(item.normalizedName),
                                count: item.activeTaskCount,
                                dotColor: palette.background,
                                dotBorderColor: palette.foreground
                            ) {
                                selectedSection = .tag(item.normalizedName)
                            }
                        }

                        FocusDeskSidebarAllTagsButton(
                            isSelected: selectedSection == .allTags,
                            count: activeTaggedTasks.count
                        ) {
                            selectedSection = .allTags
                        }
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

            sidebarResizeHandle(topPadding: 4)
        }
        .frame(width: sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var collapsedSidebar: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(FocusDeskStyle.sidebarBackground)
                .padding(.leading, 4)
                .padding(.top, collapsedSidebarBackgroundTopPadding)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                sidebarToggleButton(systemImage: "sidebar.right") {
                    showSidebar()
                }
                .frame(width: 34, height: 34)
                .padding(.top, collapsedSidebarControlTopPadding)

                Rectangle()
                    .fill(FocusDeskStyle.hairline)
                    .frame(width: 34, height: 1)
                    .padding(.top, 12)
                    .padding(.bottom, 14)

                ScrollView(.vertical, showsIndicators: false) {
                    collapsedSidebarNavigation
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)

                Spacer(minLength: 12)

                collapsedSidebarIconButton(
                    title: googleAccountDisplayName.isEmpty ? "Google Account" : googleAccountDisplayName,
                    systemImage: googleOAuthClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "person.crop.circle" : "person.crop.circle.fill",
                    isSelected: false,
                    iconColor: .secondary
                ) {
                    showingGoogleCloudSettings = true
                }
                .padding(.bottom, 18)
            }
            .padding(.horizontal, 8)

            sidebarResizeHandle(topPadding: collapsedSidebarBackgroundTopPadding)
        }
        .frame(width: collapsedSidebarWidth)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var collapsedSidebarNavigation: some View {
        VStack(spacing: 8) {
            collapsedSidebarIconButton(
                title: "Desk",
                systemImage: "circle.dashed",
                isSelected: selectedSection == .desk,
                iconColor: .orange
            ) {
                selectedSection = .desk
                ensureValidSelection()
            }

            collapsedSidebarIconButton(
                title: "New Task",
                systemImage: "plus.square.on.square",
                isSelected: selectedSection == .newTask,
                iconColor: .blue
            ) {
                selectedSection = .newTask
            }
            .keyboardShortcut("n", modifiers: [.command])

            collapsedSidebarIconButton(
                title: "Tasks",
                systemImage: "tray.full",
                isSelected: selectedSection == .tasks,
                iconColor: .mint
            ) {
                selectedSection = .tasks
            }

            collapsedSidebarIconButton(
                title: "Completed",
                systemImage: "checkmark.circle",
                isSelected: selectedSection == .completed,
                iconColor: .green
            ) {
                selectedSection = .completed
            }

            collapsedSidebarIconButton(
                title: "Summary",
                systemImage: "chart.bar.xaxis",
                isSelected: selectedSection == .summary,
                iconColor: .purple
            ) {
                selectedSection = .summary
            }

            if isTagsSidebarSectionExpanded && !sidebarTagItems.isEmpty {
                Rectangle()
                    .fill(FocusDeskStyle.hairline)
                    .frame(width: 24, height: 1)
                    .padding(.vertical, 4)

                ForEach(sidebarTagItems) { item in
                    let palette = TaskTagPalette.palette(for: item.tag.colorName)

                    collapsedSidebarDotButton(
                        title: item.tag.name,
                        isSelected: selectedSection == .tag(item.normalizedName),
                        dotColor: palette.background,
                        borderColor: palette.foreground
                    ) {
                        selectedSection = .tag(item.normalizedName)
                    }
                }

                collapsedSidebarAllTagsButton(
                    isSelected: selectedSection == .allTags
                ) {
                    selectedSection = .allTags
                }
            }
        }
    }

    private func collapsedSidebarIconButton(
        title: String,
        systemImage: String,
        isSelected: Bool,
        iconColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconColor)
                .frame(width: 32, height: 32)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(FocusDeskStyle.selectedBackground)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }

    private func collapsedSidebarDotButton(
        title: String,
        isSelected: Bool,
        dotColor: Color,
        borderColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Circle()
                .fill(dotColor)
                .overlay {
                    Circle()
                        .stroke(borderColor.opacity(0.34), lineWidth: 0.8)
                }
                .frame(width: 15, height: 15)
                .frame(width: 32, height: 32)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(FocusDeskStyle.selectedBackground)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }

    private func collapsedSidebarAllTagsButton(
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.9), lineWidth: 1.4)
                    .frame(width: 13, height: 13)
                    .offset(x: -3)

                Circle()
                    .stroke(Color.primary.opacity(0.9), lineWidth: 1.4)
                    .frame(width: 13, height: 13)
                    .offset(x: 3)
            }
            .frame(width: 32, height: 32)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(FocusDeskStyle.selectedBackground)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("All Tags...")
        .accessibilityLabel("All Tags")
    }

    private func sidebarResizeHandle(topPadding: Double) -> some View {
        Rectangle()
            .fill(Color.primary.opacity(0.001))
            .frame(width: 18)
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
                            sidebarDragStartWidth = max(sidebarWidth, minExpandedSidebarWidth)
                        }

                        let startWidth = sidebarDragStartWidth ?? sidebarWidth
                        setSidebarWidth(startWidth + value.translation.width)
                    }
                    .onEnded { _ in
                        sidebarDragStartWidth = nil
                    }
            )
            .padding(.top, topPadding)
            .padding(.bottom, 8)
            .offset(x: 9)
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
        if width <= sidebarCollapseThreshold {
            sidebarWidth = 0
            isSidebarVisible = false
        } else {
            sidebarWidth = min(max(width, minExpandedSidebarWidth), maxSidebarWidth)
            isSidebarVisible = true
        }
    }

    private func normalizeSidebarWidth() {
        if sidebarWidth <= sidebarCollapseThreshold {
            sidebarWidth = 0
            isSidebarVisible = false
        } else {
            sidebarWidth = min(max(sidebarWidth, minExpandedSidebarWidth), maxSidebarWidth)
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
                        EmptyDeskView {
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
                case .summary:
                    summaryWorkspace
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                case .allTags:
                    manageWorkspace(.allTags)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                case let .tag(normalizedName):
                    manageWorkspace(.tag(normalizedName))
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var detailToolbar: some View {
        Group {
            if selectedSection == .desk {
                ZStack {
                    TaskRotationControl(
                        currentIndex: currentTaskIndex,
                        totalCount: activeTasks.count,
                        onPrevious: selectPreviousTask,
                        onNext: selectNextTask
                    )

                    HStack(spacing: 12) {
                        Spacer()

                        toolbarIconButton(
                            systemName: "plus",
                            help: "New Task"
                        ) {
                            selectedSection = .newTask
                        }

                        toolbarIconButton(
                            systemName: isDarkTheme ? "sun.max" : "moon",
                            help: isDarkTheme ? "Switch to Light Theme" : "Switch to Dark Theme"
                        ) {
                            isDarkTheme.toggle()
                        }
                    }
                }
            } else {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(toolbarTitle)
                            .font(.system(size: 26, weight: .semibold))

                        Text(toolbarSubtitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if selectedSection != .newTask {
                        toolbarIconButton(
                            systemName: "plus",
                            help: "New Task"
                        ) {
                            selectedSection = .newTask
                        }
                    }

                    toolbarIconButton(
                        systemName: isDarkTheme ? "sun.max" : "moon",
                        help: isDarkTheme ? "Switch to Light Theme" : "Switch to Dark Theme"
                    ) {
                        isDarkTheme.toggle()
                    }
                }
            }
        }
        .padding(.leading, workspaceHorizontalPadding)
        .padding(.trailing, workspaceHorizontalPadding)
        .padding(.top, 30)
        .padding(.bottom, 18)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            toggleWindowZoom()
        }
    }

    private func toolbarIconButton(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.primary)
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(FocusDeskStyle.focusSurface)
                )
                .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
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
        case .summary:
            return "Summary"
        case .allTags:
            return "All Tags"
        case let .tag(normalizedName):
            return tagTitle(for: normalizedName)
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
        case .summary:
            return journalEntriesTodayCount == 1 ? "1 journal entry today" : "\(journalEntriesTodayCount) journal entries today"
        case .allTags:
            let count = activeTaggedTasks.count
            return count == 1 ? "1 tagged task" : "\(count) tagged tasks"
        case let .tag(normalizedName):
            let count = activeTasksMatchingTag(normalizedName).count
            return count == 1 ? "1 active task" : "\(count) active tasks"
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

    private var currentTaskIndex: Int {
        guard let currentTask else {
            return 0
        }

        return activeTasks.firstIndex { $0.id == currentTask.id } ?? 0
    }

    private var summaryWorkspace: some View {
        GeometryReader { proxy in
            let contentWidth = max(0, proxy.size.width - (workspaceHorizontalPadding * 2))

            ScrollView {
                SummaryWorkspaceView(
                    tasks: tasks,
                    activeTasks: activeTasks,
                    completedTasks: completedTasks,
                    now: Date(),
                    onOpen: { task in
                        select(task.id)
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

    private var newTaskWorkspace: some View {
        GeometryReader { proxy in
            let contentWidth = max(0, proxy.size.width - (workspaceHorizontalPadding * 2))

            ScrollView {
                NewTaskWorkspaceView(
                    availableTags: availableTagRecords,
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
            let compositionWidth = min(contentWidth, 1210)

            ScrollView {
                VStack(spacing: 46) {
                    TaskFocusSummaryView(
                        task: task,
                        availableTags: availableTagRecords,
                        onTaskChanged: saveContext,
                        onComplete: {
                            complete(task)
                        }
                    )
                        .id("summary-\(task.id.uuidString)")
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                        .zIndex(1)

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
                .frame(maxWidth: compositionWidth, alignment: .topLeading)
                .padding(.horizontal, workspaceHorizontalPadding)
                .padding(.top, 98)
                .padding(.bottom, 28)
                .frame(minWidth: proxy.size.width, maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private func createTask(_ draft: NewTaskDraft) {
        createTask(
            title: draft.title,
            details: draft.details,
            nextStep: draft.nextStep,
            motivation: draft.motivation,
            tags: draft.tags,
            initialJournalEntry: draft.initialJournalEntry
        )
    }

    private func createTask(title: String, details: String) {
        createTask(title: title, details: details, nextStep: "", motivation: "", tags: [], initialJournalEntry: "")
    }

    private func createTask(
        title: String,
        details: String,
        nextStep: String,
        motivation: String,
        tags: [TaskTagRecord],
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

        let nextOrder = (tasks.map(\.sortOrder).max() ?? -1) + 1
        let now = Date()
        let task = FocusTask(
            title: trimmedTitle,
            details: trimmedDetails,
            createdAt: now,
            updatedAt: now,
            sortOrder: nextOrder,
            motivation: trimmedMotivation.isEmpty ? nil : trimmedMotivation,
            nextStep: trimmedNextStep.isEmpty ? nil : trimmedNextStep,
            tagData: TaskTagCoding.encode(tags)
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

    private func activeTasksMatchingTag(_ normalizedName: String) -> [FocusTask] {
        activeTasks.filter { task in
            task.enabledTagRecords.contains { tag in
                normalizedTagName(tag.name) == normalizedName
            }
        }
    }

    private func tagTitle(for normalizedName: String) -> String {
        availableTagRecords.first { tag in
            normalizedTagName(tag.name) == normalizedName
        }?.name ?? "Tag"
    }

    private func normalizedTagName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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

private struct TaskRotationControl: View {
    var currentIndex: Int
    var totalCount: Int
    var onPrevious: () -> Void
    var onNext: () -> Void

    private let maxVisibleDots = 11

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 24) {
                rotationButton(systemName: "chevron.left", help: "Previous Task", action: onPrevious)
                    .keyboardShortcut(.leftArrow, modifiers: [])

                Text(rotationTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .frame(minWidth: 90)

                rotationButton(systemName: "chevron.right", help: "Next Task", action: onNext)
                    .keyboardShortcut(.rightArrow, modifiers: [])
            }

            HStack(spacing: 10) {
                ForEach(visibleDotIndices, id: \.self) { index in
                    Circle()
                        .fill(index == currentIndex ? FocusDeskStyle.focusAccent : Color.secondary.opacity(0.25))
                        .frame(width: 8, height: 8)
                        .animation(.smooth(duration: 0.16), value: currentIndex)
                }
            }
            .frame(height: 8)
        }
        .frame(maxWidth: .infinity)
        .opacity(totalCount > 0 ? 1 : 0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rotationTitle)
    }

    private func rotationButton(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(FocusDeskStyle.focusSurface)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(totalCount <= 1)
        .help(help)
    }

    private var rotationTitle: String {
        guard totalCount > 0 else {
            return "No tasks"
        }

        return "Task \(currentIndex + 1) of \(totalCount)"
    }

    private var visibleDotIndices: [Int] {
        guard totalCount > maxVisibleDots else {
            return Array(0..<totalCount)
        }

        let halfWindow = maxVisibleDots / 2
        let lowerBound = min(max(currentIndex - halfWindow, 0), totalCount - maxVisibleDots)
        return Array(lowerBound..<(lowerBound + maxVisibleDots))
    }
}

private enum ManageWorkspaceMode: Equatable {
    case tasks
    case completed
    case allTags
    case tag(String)

    var emptyTitle: String {
        switch self {
        case .tasks:
            return "No active tasks"
        case .completed:
            return "No completed tasks"
        case .allTags:
            return "No tagged tasks"
        case .tag:
            return "No tagged tasks"
        }
    }

    var emptySubtitle: String {
        switch self {
        case .tasks:
            return "Create a task to start your desk."
        case .completed:
            return "Finished tasks will appear here."
        case .allTags:
            return "Add tags to active tasks to see them here."
        case .tag:
            return "Add this tag to active tasks to see them here."
        }
    }

    var emptyIcon: String {
        switch self {
        case .tasks:
            return "tray.full"
        case .completed:
            return "checkmark.circle"
        case .allTags:
            return "tag"
        case .tag:
            return "number"
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
        case .allTags:
            return activeTasks.filter { !$0.enabledTagRecords.isEmpty }
        case let .tag(normalizedName):
            return activeTasks.filter { task in
                task.enabledTagRecords.contains { tag in
                    tag.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedName
                }
            }
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
        FocusDeskGroupedPanel {
            VStack(spacing: 10) {
                FocusDeskIcon(systemName: mode.emptyIcon, filled: true)

                Text(mode.emptyTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(mode.emptySubtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.tertiary)

                if mode != .completed {
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
            FocusDeskIcon(
                systemName: mode == .completed ? "checkmark.circle" : "rectangle.stack",
                filled: true
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if !task.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    MarkdownText(
                        task.details,
                        font: .system(size: 13, weight: .regular),
                        lineLimit: 1
                    )
                        .foregroundStyle(.secondary)
                }

                Text(rowMetadata)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                switch mode {
                case .tasks, .allTags, .tag:
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
                .fill(FocusDeskStyle.groupedBackground)
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
                .fill(FocusDeskStyle.hairline)
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
                FocusDeskIcon(systemName: "person.crop.circle.badge.plus", filled: true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Google Cloud Sync")
                        .font(.system(size: 24, weight: .semibold))

                    Text(isConnected ? email : "Not connected")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }

            FocusDeskGroupedPanel {
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

            FocusDeskGroupedPanel {
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
        .background(FocusDeskStyle.appBackground)
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

private struct SummaryWorkspaceView: View {
    var tasks: [FocusTask]
    var activeTasks: [FocusTask]
    var completedTasks: [FocusTask]
    var now: Date
    var onOpen: (FocusTask) -> Void
    var onCreate: () -> Void

    @State private var selectedJournalDate: Date?

    private var metrics: LocalSummaryMetrics {
        LocalSummaryMetrics(
            tasks: tasks,
            activeTasks: activeTasks,
            completedTasks: completedTasks,
            now: now,
            journalDate: journalReferenceDate
        )
    }

    private var journalReferenceDate: Date {
        selectedJournalDate ?? now
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 170), spacing: 16)],
                alignment: .leading,
                spacing: 16
            ) {
                SummaryMetricCard(
                    title: "Journal Today",
                    value: "\(metrics.journalEntriesToday.count)",
                    detail: "\(metrics.allJournalEntries.count) total",
                    systemImage: "text.badge.checkmark"
                )

                SummaryMetricCard(
                    title: "Completed",
                    value: "\(metrics.completedToday.count)",
                    detail: "\(completedTasks.count) total",
                    systemImage: "checkmark.circle"
                )

                SummaryMetricCard(
                    title: "Inactive Tasks",
                    value: "\(metrics.inactiveTasks.count)",
                    detail: "No journal step today",
                    systemImage: "clock.badge.exclamationmark"
                )

                SummaryMetricCard(
                    title: "Last Step",
                    value: metrics.lastStepElapsedText,
                    detail: metrics.lastStepDetail,
                    systemImage: "clock"
                )
            }

            if metrics.allJournalEntries.isEmpty && activeTasks.isEmpty {
                emptySummaryState
            } else {
                tagActivityPanel
                needsAttentionPanel
                journalPanel
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var emptySummaryState: some View {
        FocusDeskGroupedPanel {
            VStack(spacing: 10) {
                FocusDeskIcon(systemName: "chart.bar.xaxis", filled: true)

                Text("No summary yet")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("Create a task and log journal steps to build daily analytics.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)

                Button {
                    onCreate()
                } label: {
                    Label("New Task", systemImage: "plus")
                }
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, minHeight: 180)
            .padding(18)
        }
    }

    private var tagActivityPanel: some View {
        FocusDeskGroupedPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Tag activity today")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.primary)

                        Text("Estimated from journal steps")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Text(metrics.tagActivityTotalText)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.tertiary)
                }

                if metrics.tagActivities.isEmpty {
                    Text("No journal activity today.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                } else {
                    TagActivityChart(activities: metrics.tagActivities)

                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(metrics.tagActivities.enumerated()), id: \.element.id) { index, activity in
                            TagActivitySummaryRow(activity: activity)

                            if index < metrics.tagActivities.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding(18)
        }
    }

    private var needsAttentionPanel: some View {
        FocusDeskGroupedPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Needs attention")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.primary)

                    Spacer()

                    Text("\(metrics.inactiveTasks.count)")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.tertiary)
                }

                if metrics.inactiveTasks.isEmpty {
                    Text("Every active task has a journal step today.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(metrics.inactiveTasks.enumerated()), id: \.element.id) { index, task in
                            SummaryTaskAttentionRow(
                                task: task,
                                now: now,
                                onOpen: {
                                    onOpen(task)
                                }
                            )

                            if index < metrics.inactiveTasks.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding(18)
        }
    }

    private var journalPanel: some View {
        FocusDeskGroupedPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(SummaryDateFormatting.journalTitle(for: journalReferenceDate, relativeTo: now))
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.primary)

                        Text(SummaryDateFormatting.dayString(from: journalReferenceDate))
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Text("\(metrics.journalEntriesForSelectedDay.count)")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.tertiary)

                    HStack(spacing: 2) {
                        journalNavigationButton(
                            systemName: "chevron.left",
                            help: "Previous journal day",
                            isDisabled: previousJournalDate == nil
                        ) {
                            if let previousJournalDate {
                                selectedJournalDate = previousJournalDate
                            }
                        }

                        journalNavigationButton(
                            systemName: "chevron.right",
                            help: "Next journal day",
                            isDisabled: !canNavigateForward
                        ) {
                            selectedJournalDate = nextJournalDate
                        }
                    }
                }

                if metrics.journalEntriesForSelectedDay.isEmpty {
                    Text("No journal entries for this day.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(metrics.journalEntriesForSelectedDay.enumerated()), id: \.element.entry.id) { index, item in
                            SummaryJournalEntryRow(item: item)

                            if index < metrics.journalEntriesForSelectedDay.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding(18)
        }
    }

    private func journalNavigationButton(
        systemName: String,
        help: String,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(isDisabled ? .tertiary : .secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(help)
    }

    private var previousJournalDate: Date? {
        metrics.journalDayStarts.last { $0 < selectedJournalDayStart }
    }

    private var nextJournalDate: Date? {
        if let nextJournalDay = metrics.journalDayStarts.first(where: { $0 > selectedJournalDayStart && $0 <= todayStart }) {
            return nextJournalDay
        }

        return canNavigateForward ? nil : selectedJournalDate
    }

    private var canNavigateForward: Bool {
        selectedJournalDayStart < todayStart
    }

    private var selectedJournalDayStart: Date {
        Calendar.current.startOfDay(for: journalReferenceDate)
    }

    private var todayStart: Date {
        Calendar.current.startOfDay(for: now)
    }
}

private struct LocalSummaryMetrics {
    var allJournalEntries: [SummaryJournalEntry]
    var journalEntriesToday: [SummaryJournalEntry]
    var journalEntriesForSelectedDay: [SummaryJournalEntry]
    var journalDayStarts: [Date]
    var completedToday: [FocusTask]
    var inactiveTasks: [FocusTask]
    var latestJournalEntry: SummaryJournalEntry?
    var tagActivities: [TagActivitySummary]
    var now: Date

    init(
        tasks: [FocusTask],
        activeTasks: [FocusTask],
        completedTasks: [FocusTask],
        now: Date,
        journalDate: Date,
        calendar: Calendar = .current
    ) {
        self.now = now
        let startOfDay = calendar.startOfDay(for: now)
        let todayInterval = DateInterval(start: startOfDay, end: now)
        let selectedDayStart = calendar.startOfDay(for: journalDate)
        let selectedDayEnd = calendar.date(byAdding: .day, value: 1, to: selectedDayStart) ?? now

        let allEntries = tasks
            .flatMap { task in
                task.entries.map { entry in
                    SummaryJournalEntry(task: task, entry: entry)
                }
            }
            .sorted { lhs, rhs in
                lhs.entry.timestamp > rhs.entry.timestamp
            }

        allJournalEntries = allEntries
        journalEntriesToday = allEntries.filter { item in
            item.entry.timestamp >= startOfDay && item.entry.timestamp <= now
        }
        journalEntriesForSelectedDay = allEntries.filter { item in
            item.entry.timestamp >= selectedDayStart && item.entry.timestamp < selectedDayEnd
        }
        journalDayStarts = Array(
            Set(allEntries.map { item in
                calendar.startOfDay(for: item.entry.timestamp)
            })
        )
        .sorted()
        completedToday = completedTasks.filter { task in
            guard let completedAt = task.completedAt else {
                return false
            }

            return completedAt >= startOfDay && completedAt <= now
        }
        inactiveTasks = activeTasks
            .filter { task in
                guard let latestEntry = task.latestEntry else {
                    return true
                }

                return latestEntry.timestamp < startOfDay
            }
            .sorted { lhs, rhs in
                let lhsDate = lhs.latestEntry?.timestamp ?? lhs.createdAt
                let rhsDate = rhs.latestEntry?.timestamp ?? rhs.createdAt
                return lhsDate < rhsDate
            }
        latestJournalEntry = allEntries.first
        tagActivities = TagActivityAnalyzer().summaries(
            for: allEntries.map { item in
                TagActivityEvent(
                    taskID: item.task.id,
                    taskTitle: item.task.title,
                    tags: item.task.enabledTagRecords,
                    timestamp: item.entry.timestamp
                )
            },
            in: todayInterval
        )
    }

    var lastStepElapsedText: String {
        guard let latestJournalEntry else {
            return "No steps"
        }

        return SummaryDateFormatting.elapsedString(from: latestJournalEntry.entry.timestamp, to: now)
    }

    var lastStepDetail: String {
        latestJournalEntry?.task.title ?? "No journal entries"
    }

    var tagActivityTotalText: String {
        SummaryDateFormatting.durationString(
            minutes: tagActivities.reduce(0) { partialResult, activity in
                partialResult + activity.estimatedMinutes
            }
        )
    }
}

private struct SummaryJournalEntry {
    var task: FocusTask
    var entry: ProgressEntry
}

private struct SummaryMetricCard: View {
    var title: String
    var value: String
    var detail: String
    var systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                FocusDeskIcon(systemName: systemImage, filled: true)

                Spacer()
            }

            Text(value)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(detail)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 136, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(FocusDeskStyle.groupedBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct TagActivityChart: View {
    var activities: [TagActivitySummary]

    private var chartHeight: Double {
        min(max(Double(activities.count) * 34, 118), 280)
    }

    var body: some View {
        Chart(activities) { activity in
            BarMark(
                x: .value("Estimated time", activity.estimatedMinutes),
                y: .value("Tag", activity.name)
            )
            .foregroundStyle(TaskTagPalette.palette(for: activity.colorName).background)
            .cornerRadius(5)
        }
        .chartXAxis {
            AxisMarks(position: .bottom) { value in
                AxisGridLine()
                    .foregroundStyle(FocusDeskStyle.hairline)

                AxisValueLabel {
                    if let minutes = value.as(Double.self) {
                        Text(SummaryDateFormatting.durationString(minutes: minutes))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) {
                AxisValueLabel()
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .font(.system(size: 11, weight: .regular))
            }
        }
        .frame(height: chartHeight)
    }
}

private struct TagActivitySummaryRow: View {
    var activity: TagActivitySummary

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            SummaryTagBadge(activity: activity)

            Spacer(minLength: 12)

            Text(activityDetail)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(SummaryDateFormatting.durationString(minutes: activity.estimatedMinutes))
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var activityDetail: String {
        "\(activity.taskCount) \(activity.taskCount == 1 ? "task" : "tasks") - \(activity.journalStepCount) \(activity.journalStepCount == 1 ? "step" : "steps")"
    }
}

private struct SummaryTagBadge: View {
    var activity: TagActivitySummary

    private var palette: TaskTagPalette {
        TaskTagPalette.palette(for: activity.colorName)
    }

    var body: some View {
        Text(activity.name)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(palette.foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(palette.background)
            )
    }
}

private struct SummaryTaskAttentionRow: View {
    var task: FocusTask
    var now: Date
    var onOpen: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            FocusDeskIcon(systemName: "clock", filled: false)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(lastStepText)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Button(action: onOpen) {
                Image(systemName: "arrow.forward")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open Task")
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lastStepText: String {
        guard let latestEntry = task.latestEntry else {
            return "No journal steps yet"
        }

        return "\(SummaryDateFormatting.elapsedString(from: latestEntry.timestamp, to: now)) since last step"
    }
}

private struct SummaryJournalEntryRow: View {
    var item: SummaryJournalEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.task.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Text(SummaryDateFormatting.shortTimeString(from: item.entry.timestamp))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            MarkdownText(
                item.entry.note,
                font: .system(size: 13, weight: .regular),
                lineLimit: 2
            )
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum SummaryDateFormatting {
    static func elapsedString(from date: Date, to referenceDate: Date) -> String {
        let elapsedSeconds = max(0, referenceDate.timeIntervalSince(date))

        if elapsedSeconds < 60 {
            return "Just now"
        }

        let units: [(seconds: TimeInterval, shortName: String)] = [
            (60 * 60 * 24 * 365, "y"),
            (60 * 60 * 24 * 30, "mo"),
            (60 * 60 * 24 * 7, "w"),
            (60 * 60 * 24, "d"),
            (60 * 60, "h"),
            (60, "m")
        ]

        guard let unit = units.first(where: { elapsedSeconds >= $0.seconds }) else {
            return "Just now"
        }

        let value = Int(elapsedSeconds / unit.seconds)
        return "\(value)\(unit.shortName) ago"
    }

    static func shortTimeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func journalTitle(for date: Date, relativeTo referenceDate: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: referenceDate) {
            return "Today journal"
        }

        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate) else {
            return "\(dayString(from: date)) journal"
        }

        if calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday journal"
        }

        return "\(dayString(from: date)) journal"
    }

    static func dayString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func durationString(minutes: Double) -> String {
        let roundedMinutes = max(0, Int(minutes.rounded()))

        if roundedMinutes < 60 {
            return "\(roundedMinutes)m"
        }

        let hours = roundedMinutes / 60
        let remainingMinutes = roundedMinutes % 60

        if remainingMinutes == 0 {
            return "\(hours)h"
        }

        return "\(hours)h \(remainingMinutes)m"
    }
}

private struct NewTaskDraft {
    var title = ""
    var details = ""
    var nextStep = ""
    var motivation = ""
    var tags: [TaskTagRecord] = []
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
            TaskTagCoding.encode(tags) ?? "",
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
    var availableTags: [TaskTagRecord]
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
                    .foregroundStyle(.primary)
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

            TaskTagsEditorView(tags: $draft.tags, availableTags: availableTags)
                .padding(.leading, -22)
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: panelHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(FocusDeskStyle.groupedBackground.opacity(0.78))
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
                    .foregroundStyle(.primary)
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
                .fill(FocusDeskStyle.sidebarBackground)
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
                .foregroundStyle(.primary)
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
                .fill(FocusDeskStyle.sidebarBackground)
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

struct CompletionToast: Identifiable, Equatable {
    var id = UUID()
    var taskID: UUID
    var title: String
}
