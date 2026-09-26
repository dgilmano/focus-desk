import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class BackupStore {
    private(set) var lastBackupAt: Date?
    private(set) var errorMessage: String?
    let directory: URL
    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var dirty = false

    init(container: ModelContainer, directory: URL) {
        self.container = container
        self.directory = directory
    }

    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "FocusDesk/Backups", directoryHint: .isDirectory)
    }

    func schedule() {
        dirty = true
        guard pending == nil else { return }
        let delay = max(2, 30 - Date().timeIntervalSince(lastBackupAt ?? .distantPast))
        pending = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            self?.flush()
        }
    }

    func flush() {
        pending?.cancel()
        pending = nil
        guard dirty else { return }
        do {
            let snapshot = try snapshot()
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd-HH"
            try write(snapshot, to: directory.appendingPathComponent("automatic-\(formatter.string(from: Date())).json"))
            dirty = false
            lastBackupAt = Date()
            errorMessage = nil
            try prune(prefix: "automatic-", keeping: 48)
        } catch {
            errorMessage = "Automatic backup failed: \(error.localizedDescription)"
        }
    }

    func snapshot() throws -> WorkspaceBackup {
        // A fresh context reads committed data from both the task and activity stores.
        try WorkspaceBackup.capture(from: ModelContext(container)).validated()
    }

    @discardableResult
    func safetyCopy() throws -> URL {
        let url = directory.appendingPathComponent("recovery-\(UUID().uuidString).json")
        do {
            try write(snapshot(), to: url)
            lastBackupAt = Date()
            errorMessage = nil
            try prune(prefix: "recovery-", keeping: 20)
            return url
        } catch {
            errorMessage = "Recovery copy failed: \(error.localizedDescription)"
            throw error
        }
    }

    func files() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
            .filter { $0.pathExtension == "json" && ($0.lastPathComponent.hasPrefix("automatic-") || $0.lastPathComponent.hasPrefix("recovery-")) }
            .sorted { modificationDate($0) > modificationDate($1) }
    }

    private func write(_ snapshot: WorkspaceBackup, to url: URL) throws {
        let data = try snapshot.encoded()
        guard data.count <= WorkspaceBackup.maximumFileSize else {
            throw BackupError.invalid("The workspace exceeds the 64 MB backup limit. No existing backup was replaced.")
        }
        _ = try WorkspaceBackup.decode(data)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func prune(prefix: String, keeping count: Int) throws {
        for file in try files().filter({ $0.lastPathComponent.hasPrefix(prefix) }).dropFirst(count) {
            try FileManager.default.removeItem(at: file)
        }
    }

    private func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
