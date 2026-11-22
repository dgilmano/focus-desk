#if DEBUG || FOCUS_DESK_PERSONAL
import SwiftUI

struct DeskToolbar: View {
    let tasks: [FocusTask]
    let projectNames: [String]
    let currentTaskID: UUID?
    @Binding var isDarkTheme: Bool
    @Binding var readNotices: Set<String>
    let voiceNote: () -> Void
    let newTask: () -> Void
    let addJournalEntry: () -> Void
    let selectTask: (UUID) -> Void
    let previousTask: () -> Void
    let nextTask: () -> Void

    private let subtitleSpacing: CGFloat = 10.5

    private var subtitle: String {
        let projects = Set((projectNames + tasks.compactMap { $0.deskProjectTag?.name }).map(DeskProject.key))
        let taskCount = tasks.count == 1 ? "1 open task" : "\(tasks.count) open tasks"
        let projectCount = projects.count == 1 ? "1 project" : "\(projects.count) projects"
        return "\(projectCount) · \(taskCount)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: subtitleSpacing) {
            HStack(spacing: 8) {
                Text("Desk")
                    .font(.system(size: 28, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                #if !FOCUS_DESK_UPDATES || FOCUS_DESK_PERSONAL
                Button(action: voiceNote) {
                    Image(systemName: "mic")
                        .font(.system(size: 14))
                        .frame(width: 34, height: 34)
                        .background(FocusDeskStyle.groupedBackground, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .anchorPreference(key: VoiceButtonAnchor.self, value: .bounds) { $0 }
                .accessibilityLabel("Voice note")
                .help("Dictate tasks or next steps")
                #endif
                DeskNotificationsButton(readNotices: $readNotices)
                newTaskButton
            }
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 20)
        .padding(.bottom, subtitleSpacing)
    }

    private var newTaskButton: some View {
        HStack(spacing: 0) {
            Button(action: newTask) {
                Label("New task", systemImage: "plus")
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                    .contentShape(Rectangle())
            }
            Rectangle().fill(.white.opacity(0.3)).frame(width: 1, height: 18)
            Menu {
                Button("Add journal entry", systemImage: "square.and.pencil", action: addJournalEntry)
                    .disabled(currentTaskID == nil)
                Menu("Switch task", systemImage: "list.bullet") {
                    Button("Previous task", action: previousTask)
                    Button("Next task", action: nextTask)
                    Divider()
                    let outline = TaskOutline(tasks.map(TaskOutline.Item.init))
                    ForEach(outline.rows()) { row in
                        Button {
                            selectTask(row.id)
                        } label: {
                            if row.id == currentTaskID {
                                Label(outline.path(to: row.id), systemImage: "checkmark")
                            } else {
                                Text(outline.path(to: row.id))
                            }
                        }
                    }
                }
                .disabled(tasks.count < 2)
                Divider()
                Button(isDarkTheme ? "Switch to light theme" : "Switch to dark theme",
                       systemImage: isDarkTheme ? "sun.max" : "moon") {
                    isDarkTheme.toggle()
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 28, height: 34)
                    .contentShape(Rectangle())
            }
            .menuIndicator(.hidden)
            .menuStyle(.button)
            .accessibilityLabel("More actions")
            .help("More actions")
        }
        .buttonStyle(.plain)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white)
        .background(FocusDeskStyle.deskActionBlue,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .fixedSize()
    }
}

private struct DeskNotificationsButton: View {
    @Environment(ActivityStore.self) private var activity
    @Environment(TaskStore.self) private var tasks
    @Environment(BackupStore.self) private var backups
    @Binding var readNotices: Set<String>
    @State private var showingNotifications = false

    private var notices: [String] {
        [tasks.errorMessage, backups.errorMessage, activity.errorMessage, activity.notice].compactMap { $0 }
    }

    var body: some View {
        let messages = notices
        let hasUnread = messages.contains { !readNotices.contains($0) }
        Button {
            showingNotifications.toggle()
        } label: {
            Image(systemName: "bell")
                .font(.system(size: 14, weight: .medium))
                .overlay(alignment: .topTrailing) {
                    if hasUnread {
                        Circle().fill(.red).frame(width: 5, height: 5)
                            .offset(x: 2, y: -1)
                    }
                }
                .frame(width: 34, height: 34)
                .background(FocusDeskStyle.groupedBackground, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Notifications")
        .accessibilityValue(hasUnread ? "Unread notifications" : "No unread notifications")
        .help("Notifications")
        .popover(isPresented: $showingNotifications, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Notifications").font(.headline)
                if messages.isEmpty {
                    Text("You’re all caught up.").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                        Text(message).fixedSize(horizontal: false, vertical: true)
                    }
                    if hasUnread {
                        Button("Mark as read") { readNotices.formUnion(messages) }
                    }
                }
            }
            .font(.callout)
            .padding(16)
            .frame(width: 260, alignment: .leading)
        }
        .onChange(of: messages, initial: true) { readNotices.formIntersection(messages) }
    }
}
#endif
