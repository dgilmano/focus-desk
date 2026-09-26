import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DataBackupView: View {
    var session: WorkspaceSession
    @State private var importing = false
    @State private var pendingBackup: WorkspaceBackup?
    @State private var showingRestoreConfirmation = false
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Data & Backups").font(.title2.weight(.semibold))
            LabeledContent("Storage", value: "On this Mac")
            LabeledContent("Automatic backups") {
                if let date = session.backups.lastBackupAt {
                    Text(date, format: .dateTime.day().month().hour().minute())
                } else {
                    Text("Pending")
                }
            }
            Divider()
            HStack {
                Button { export() } label: { Label("Export Backup", systemImage: "square.and.arrow.up") }
                Button { importing = true } label: { Label("Restore Backup...", systemImage: "arrow.counterclockwise") }
            }
            HStack {
                Button("Back Up Now") {
                    perform {
                        guard session.tasks.save() else { throw BackupError.invalid(session.tasks.errorMessage!) }
                        try session.backups.safetyCopy()
                        message = "Backup saved."
                    }
                }
                Button("Show Backups in Finder") {
                    NSWorkspace.shared.open(session.backups.directory)
                }
            }
            Text("Backup files contain your tasks, journal, tags and Day map. They are not encrypted.")
                .font(.callout).foregroundStyle(.secondary)
            Text("Local backups do not protect against losing this Mac. Keep an exported copy in a separate safe location.")
                .font(.callout).foregroundStyle(.secondary)
            if let error = session.backups.errorMessage {
                Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
            if let message {
                Text(message).font(.callout).foregroundStyle(isError ? .red : .secondary).textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(minWidth: 520, minHeight: 400)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            perform {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                pendingBackup = try WorkspaceBackup.read(from: url)
                showingRestoreConfirmation = true
            }
        }
        .alert("Replace this workspace?", isPresented: $showingRestoreConfirmation) {
            Button("Cancel", role: .cancel) { pendingBackup = nil }
            Button("Restore", role: .destructive) {
                perform {
                    guard let pendingBackup else { return }
                    try session.restore(pendingBackup)
                    self.pendingBackup = nil
                    message = "Backup restored. The previous workspace is saved in the Backups folder."
                }
            }
        } message: {
            if let backup = pendingBackup {
                Text("This backup contains \(backup.tasks.count) tasks, \(backup.entries.count) journal entries and \(backup.intervals.count) activity intervals. Current data will be replaced after a recovery copy is saved. Active recording will stop.")
            }
        }
    }

    private func export() {
        perform {
            // Include unsaved bound text too, allowing rescue when the database itself cannot be written.
            let snapshot = try session.exportSnapshot()
            let data = try snapshot.encoded()
            _ = try WorkspaceBackup.decode(data)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = "FocusDesk-backup-\(Date().formatted(.iso8601.year().month().day())).json"
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                perform {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    try data.write(to: url, options: .atomic)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                    message = "Backup exported."
                }
            }
        }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action(); isError = false } catch { isError = true; message = error.localizedDescription }
    }
}

struct DataProtectionStatus: View {
    @Environment(TaskStore.self) private var tasks
    @Environment(BackupStore.self) private var backups
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let error = tasks.errorMessage ?? backups.errorMessage {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                Text(error).font(.callout).textSelection(.enabled)
                Spacer(minLength: 0)
                Button("Retry") { tasks.save(); backups.schedule(); backups.flush() }
                Button("Backups") { openWindow(id: "data-backups") }
            }
            .padding(12).background(.bar)
        } else if let message = tasks.deletionMessage {
            HStack {
                Text(message).font(.callout)
                Button("Undo") { tasks.undoDeletion() }
                Spacer()
                Button { tasks.clearDeletionHistory() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help("Dismiss undo history")
            }
            .padding(12).background(.bar)
        }
    }
}

struct StoreRecoveryView: View {
    var workspace: WorkspaceBootstrap
    @State private var importing = false
    @State private var pendingBackup: WorkspaceBackup?
    @State private var confirming = false
    @State private var errorMessage: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Your workspace could not be opened", systemImage: "externaldrive.badge.exclamationmark")
                .font(.title2)
            Text("Focus Desk has not replaced your database with an empty workspace.")
            Text(workspace.errorMessage ?? "Please try again.").foregroundStyle(.secondary).textSelection(.enabled)
            HStack {
                Button("Retry") { workspace.open() }
                Button("Restore Backup...") { importing = true }
                Button("Show Backups") { NSWorkspace.shared.open(BackupStore.defaultDirectory) }
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red).textSelection(.enabled) }
        }
        .padding(32).frame(minWidth: 520, minHeight: 260)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                pendingBackup = try WorkspaceBackup.read(from: url)
                confirming = true
            } catch { errorMessage = error.localizedDescription }
        }
        .alert("Recover from this backup?", isPresented: $confirming) {
            Button("Cancel", role: .cancel) { pendingBackup = nil }
            Button("Recover") {
                do {
                    if let pendingBackup { try workspace.recover(pendingBackup) }
                } catch { errorMessage = error.localizedDescription }
            }
        } message: {
            Text("Focus Desk will create a new workspace from this backup and keep the original database untouched.")
        }
    }
}
