import AppKit
import SwiftUI
import SwiftData

@main
struct FocusCarouselApp: App {
    private let modelContainer: ModelContainer

    @AppStorage("isDarkTheme")
    private var isDarkTheme = false

    @MainActor
    init() {
        modelContainer = PersistenceController.makeModelContainer()
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("Focus Desk") {
            MainCarouselView()
                .modelContainer(modelContainer)
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
            FocusCarouselCommands()
        }

        Window("Task Manager", id: "task-manager") {
            TaskManagerView()
                .modelContainer(modelContainer)
                .preferredColorScheme(isDarkTheme ? .dark : .light)
                .frame(minWidth: 760, minHeight: 500)
        }
        .defaultSize(width: 820, height: 560)
    }
}

struct FocusCarouselCommands: Commands {
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
