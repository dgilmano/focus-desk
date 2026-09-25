import AppKit
import SwiftUI
import SwiftData

@main
struct FocusDeskApp: App {
    private let modelContainer: ModelContainer
    @State private var activityStore: ActivityStore

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
        modelContainer = PersistenceController.makeModelContainer(inMemory: preview)
        let activity = ActivityStore(container: modelContainer)
        _activityStore = State(initialValue: activity)
        #if DEBUG
        if preview { ActivityPreview.seed(container: modelContainer, store: activity) }
        #endif
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("Focus Desk", id: "desk") {
            MainDeskView()
                .modelContainer(modelContainer)
                .environment(activityStore)
                .preferredColorScheme(isDarkTheme ? .dark : .light)
                .frame(minWidth: 720, minHeight: 520)
                .onAppear {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 920, height: 620)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            FocusDeskCommands()
        }

        Window("Task Manager", id: "task-manager") {
            TaskManagerView()
                .modelContainer(modelContainer)
                .preferredColorScheme(isDarkTheme ? .dark : .light)
                .frame(minWidth: 760, minHeight: 500)
        }
        .defaultSize(width: 820, height: 560)

        MenuBarExtra {
            ActivityMenuView()
                .environment(activityStore)
                .modelContainer(modelContainer)
                .preferredColorScheme(isDarkTheme ? .dark : .light)
        } label: {
            Label {
                Text(activityStore.activeCategory?.name ?? "Focus Desk")
            } icon: {
                Image(systemName: "square.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(TaskTagPalette.palette(for: activityStore.activeCategory?.colorName ?? "gray").foreground)
            }
        }
        .menuBarExtraStyle(.window)
    }
}

struct FocusDeskCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Focus Desk") {
            Button("Task Manager") {
                openWindow(id: "task-manager")
            }
            .keyboardShortcut("m", modifiers: [.command])
        }
    }
}
