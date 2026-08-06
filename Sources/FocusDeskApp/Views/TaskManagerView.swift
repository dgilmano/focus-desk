import SwiftData
import SwiftUI

struct TaskManagerView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \FocusTask.carouselOrder, order: .forward)
    private var tasks: [FocusTask]

    @AppStorage("currentTaskID")
    private var currentTaskIDRaw = ""

    @State private var selectedTab: TaskManagerTab = .active
    @State private var showingNewTask = false
    @State private var taskToEdit: FocusTask?
    @State private var taskToViewHistory: FocusTask?
    @State private var taskToDelete: FocusTask?

    private var activeTasks: [FocusTask] {
        tasks.filter { $0.completedAt == nil }
    }

    private var completedTasks: [FocusTask] {
        tasks
            .filter { $0.completedAt != nil }
            .sorted {
                ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            HStack(spacing: 0) {
                OrbPillSegment(
                    title: "Active",
                    systemImage: "rectangle.stack",
                    value: TaskManagerTab.active,
                    selection: $selectedTab
                )

                Rectangle()
                    .fill(OrbStyle.hairline)
                    .frame(width: 1, height: 24)

                OrbPillSegment(
                    title: "Completed",
                    systemImage: "checkmark.circle",
                    value: TaskManagerTab.completed,
                    selection: $selectedTab
                )
            }
            .padding(5)
            .background(OrbStyle.groupedBackground)
            .clipShape(Capsule(style: .continuous))
            .padding(.horizontal, 24)
            .padding(.bottom, 14)

            Group {
                switch selectedTab {
                case .active:
                    taskList(
                        tasks: activeTasks,
                        emptyTitle: "No active tasks",
                        row: activeRow
                    )
                case .completed:
                    taskList(
                        tasks: completedTasks,
                        emptyTitle: "No completed tasks",
                        row: completedRow
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(OrbStyle.appBackground)
        .sheet(isPresented: $showingNewTask) {
            TaskEditorSheet(mode: .create) { title, details in
                createTask(title: title, details: details)
            }
        }
        .sheet(item: $taskToEdit) { task in
            TaskEditorSheet(mode: .edit(task)) { title, details in
                task.title = title
                task.details = details
                task.updatedAt = Date()
                saveContext()
                refreshWidgetSnapshot()
            }
        }
        .sheet(item: $taskToViewHistory) { task in
            TaskHistoryView(task: task)
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

    private var header: some View {
        HStack(spacing: 12) {
            Text("Tasks")
                .font(.system(size: 28, weight: .semibold))

            Spacer()

            Button {
                showingNewTask = true
            } label: {
                Label("New Task", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: [.command])
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    private func taskList<Row: View>(
        tasks: [FocusTask],
        emptyTitle: String,
        @ViewBuilder row: @escaping (FocusTask) -> Row
    ) -> some View {
        Group {
            if tasks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: selectedTab == .active ? "rectangle.stack" : "checkmark.circle")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)

                    Text(emptyTitle)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(tasks) { task in
                    row(task)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 6, leading: 24, bottom: 6, trailing: 24))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func activeRow(_ task: FocusTask) -> some View {
        TaskManagerRow(task: task) {
            Button("Open") {
                currentTaskIDRaw = task.id.uuidString
                refreshWidgetSnapshot()
            }

            Button("Edit") {
                taskToEdit = task
            }

            Button("Delete", role: .destructive) {
                taskToDelete = task
            }
        }
    }

    private func completedRow(_ task: FocusTask) -> some View {
        TaskManagerRow(task: task) {
            Button("View History") {
                taskToViewHistory = task
            }

            Button("Restore") {
                restore(task)
            }

            Button("Delete", role: .destructive) {
                taskToDelete = task
            }
        }
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

    private func createTask(title: String, details: String) {
        let nextOrder = (tasks.map(\.carouselOrder).max() ?? -1) + 1
        let now = Date()
        let task = FocusTask(
            title: title,
            details: details,
            createdAt: now,
            updatedAt: now,
            carouselOrder: nextOrder
        )

        modelContext.insert(task)
        saveContext()
        currentTaskIDRaw = task.id.uuidString
        refreshWidgetSnapshot()
    }

    private func restore(_ task: FocusTask) {
        task.completedAt = nil
        task.updatedAt = Date()
        saveContext()
        currentTaskIDRaw = task.id.uuidString
        selectedTab = .active
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

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            assertionFailure("Unable to save Focus Desk task manager change: \(error)")
        }
    }

    private func refreshWidgetSnapshot() {
        let selectedTask = activeTasks.first { $0.id.uuidString == currentTaskIDRaw } ?? activeTasks.first
        WidgetSnapshotWriter.write(currentTask: selectedTask, activeTaskCount: activeTasks.count)
    }
}

private enum TaskManagerTab: Hashable {
    case active
    case completed
}

private struct TaskManagerRow<Actions: View>: View {
    var task: FocusTask
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            OrbIcon(
                systemName: task.completedAt == nil ? "rectangle.stack" : "checkmark.circle",
                filled: true
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)

                if !task.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    MarkdownText(
                        task.details,
                        font: .system(size: 13),
                        lineLimit: 1
                    )
                        .foregroundStyle(.secondary)
                }

                Text(rowMetadata)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 16)

            HStack(spacing: 8) {
                actions()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(OrbStyle.groupedBackground)
        )
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
