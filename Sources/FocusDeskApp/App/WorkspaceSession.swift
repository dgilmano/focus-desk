import AppKit
import Observation
import SwiftData

@MainActor
@Observable
final class WorkspaceSession {
    let container: ModelContainer
    let tasks: TaskStore
    let activity: ActivityStore
    let backups: BackupStore
    private(set) var revision = UUID()

    init(container: ModelContainer, backupDirectory: URL, observeLifecycle: Bool = true) {
        self.container = container
        let backups = BackupStore(container: container, directory: backupDirectory)
        self.backups = backups
        tasks = TaskStore(context: container.mainContext, didSave: { backups.schedule() },
                          beforeDeletion: { try backups.safetyCopy() })
        activity = ActivityStore(container: container, observeLifecycle: observeLifecycle,
                                 didSave: { backups.schedule() }, beforeDeletion: { try backups.safetyCopy() })
    }

    func restore(_ snapshot: WorkspaceBackup) throws {
        _ = try snapshot.validated()
        let rollback = try WorkspaceBackup.rollbackAction(in: container.mainContext)
        guard tasks.perform(rollback: rollback, {
            try backups.safetyCopy()
            try snapshot.apply(to: container.mainContext)
        }) else {
            throw BackupError.invalid(tasks.errorMessage ?? "The backup was not restored.")
        }
        tasks.clearDeletionHistory()
        activity.reloadAfterRestore()
        revision = UUID()
        backups.flush()
    }

    func prepareToQuit() -> Bool {
        guard tasks.save(), activity.pause() else { return false }
        backups.flush()
        return true
    }

    func prepareForUpdate() throws {
        guard tasks.save(), activity.pause() else { throw UpdatePreparationError.saveFailed }
        try backups.safetyCopy()
        backups.flush()
    }

    func exportSnapshot() throws -> WorkspaceBackup {
        // Tasks may have unsaved edits; Day map lives in its own context and must be read fresh.
        var snapshot = try WorkspaceBackup.capture(from: container.mainContext)
        let committed = try backups.snapshot()
        snapshot.categories = committed.categories
        snapshot.intervals = committed.intervals
        return try snapshot.validated()
    }
}

@MainActor
@Observable
final class WorkspaceBootstrap {
    private(set) var session: WorkspaceSession?
    private(set) var errorMessage: String?
    private let preview: Bool

    init(preview: Bool) {
        self.preview = preview
        open()
    }

    func open() {
        guard session == nil else { return }
        do {
            let container = try PersistenceController.makeModelContainer(inMemory: preview)
            let directory = preview
                ? FileManager.default.temporaryDirectory.appendingPathComponent("FocusDeskPreviewBackups-\(UUID().uuidString)")
                : BackupStore.defaultDirectory
            let workspace = WorkspaceSession(container: container, backupDirectory: directory)
            #if DEBUG
            if preview { ActivityPreview.seed(container: container, store: workspace.activity) }
            #endif
            session = workspace
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func recover(_ snapshot: WorkspaceBackup) throws {
        guard session == nil, !preview else { return }
        let container = try PersistenceController.recover(snapshot)
        session = WorkspaceSession(container: container, backupDirectory: BackupStore.defaultDirectory)
        errorMessage = nil
    }
}

@MainActor
final class FocusDeskAppDelegate: NSObject, NSApplicationDelegate {
    var session: WorkspaceSession?
    var isInstallingUpdate = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isInstallingUpdate {
            do {
                guard let session else { throw UpdatePreparationError.workspaceUnavailable }
                try session.prepareForUpdate()
                return .terminateNow
            } catch {
                let alert = NSAlert()
                alert.messageText = "Update postponed"
                alert.informativeText = "Focus Desk must save your changes and create a recovery copy before updating. \(error.localizedDescription)"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Keep Open")
                alert.runModal()
                return .terminateCancel
            }
        }
        guard let session, !session.prepareToQuit() else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Some changes have not been saved"
        alert.informativeText = "Keep Focus Desk open to retry saving or export your data before quitting."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Keep Open")
        alert.addButton(withTitle: "Quit Without Saving")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}
