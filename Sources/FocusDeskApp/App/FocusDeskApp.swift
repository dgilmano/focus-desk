import AppKit
import SwiftUI
import SwiftData

@main
struct FocusDeskApp: App {
    @NSApplicationDelegateAdaptor(FocusDeskAppDelegate.self) private var appDelegate
    @State private var workspace: WorkspaceBootstrap
    #if FOCUS_DESK_UPDATES
    @State private var updates = AppUpdateService()
    #endif

    @AppStorage("isDarkTheme")
    private var isDarkTheme = false

    @MainActor
    init() {
        #if DEBUG
        let preview = ProcessInfo.processInfo.arguments.contains("--activity-preview") ||
            Bundle.main.bundleIdentifier == "com.focusdesk.preview"
        #else
        let preview = false
        #endif
        _workspace = State(initialValue: WorkspaceBootstrap(preview: preview))
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("Focus Desk", id: "desk") {
            workspaceContent { MainDeskView() }
                .preferredColorScheme(isDarkTheme ? .dark : .light)
                .frame(minWidth: 720, minHeight: 520)
                .onAppear {
                    appDelegate.session = workspace.session
                    #if FOCUS_DESK_UPDATES
                    updates.installationStateChanged = { [weak delegate = appDelegate] pending in
                        delegate?.isInstallingUpdate = pending
                    }
                    updates.workspaceAvailable = { [weak workspace = workspace] in workspace?.session != nil }
                    #endif
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                .onChange(of: workspace.session != nil) { appDelegate.session = workspace.session }
        }
        .defaultSize(width: 920, height: 620)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            #if FOCUS_DESK_UPDATES
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") { updates.checkForUpdates() }
                    .disabled(!updates.canCheckForUpdates && updates.startupError == nil)
                Divider()
            }
            #endif
            FocusDeskCommands(tasks: workspace.session?.tasks)
        }

        Window("Task Manager", id: "task-manager") {
            workspaceContent { TaskManagerView() }
                .preferredColorScheme(isDarkTheme ? .dark : .light)
                .frame(minWidth: 760, minHeight: 500)
        }
        .defaultSize(width: 820, height: 560)

        Window("Data & Backups", id: "data-backups") {
            if let session = workspace.session {
                DataBackupView(session: session)
                    .preferredColorScheme(isDarkTheme ? .dark : .light)
            } else {
                StoreRecoveryView(workspace: workspace)
            }
        }
        .defaultSize(width: 560, height: 460)

        MenuBarExtra {
            workspaceContent { ActivityMenuView() }
                .preferredColorScheme(isDarkTheme ? .dark : .light)
        } label: {
            Label {
                Text(workspace.session?.activity.activeCategory?.name ?? "Focus Desk")
            } icon: {
                Image(systemName: "square.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(TaskTagPalette.palette(for: workspace.session?.activity.activeCategory?.colorName ?? "gray").foreground)
            }
        }
        .menuBarExtraStyle(.window)
    }

    @ViewBuilder private func workspaceContent<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if let session = workspace.session {
            content()
                .id(session.revision)
                .modelContainer(session.container)
                .environment(session.activity)
                .environment(session.tasks)
                .environment(session.backups)
        } else {
            StoreRecoveryView(workspace: workspace)
        }
    }
}

struct FocusDeskCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    var tasks: TaskStore?

    var body: some Commands {
        CommandMenu("Focus Desk") {
            Button("Task Manager") {
                openWindow(id: "task-manager")
            }
            .keyboardShortcut("m", modifiers: [.command])

            Button("Data & Backups...") { openWindow(id: "data-backups") }
            Divider()
            Button("Undo Last Deletion") { tasks?.undoDeletion() }
                .disabled(tasks?.deletionMessage == nil)
        }
    }
}
