import Foundation
import SQLite3

enum StoreSnapshot {
    static func copy(from source: URL, to destination: URL) throws {
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw BackupError.invalid("A database snapshot already exists at this location.")
        }
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".snapshot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try copyDatabase(from: source, to: temporary)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    private static func copyDatabase(from source: URL, to destination: URL) throws {
        var input: OpaquePointer?
        var output: OpaquePointer?
        defer { sqlite3_close(input); sqlite3_close(output) }
        guard sqlite3_open_v2(source.path, &input, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              sqlite3_open_v2(destination.path, &output, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
              let backup = sqlite3_backup_init(output, "main", input, "main") else {
            throw BackupError.invalid("The database could not be backed up. The original has not been replaced.")
        }
        // Includes committed WAL contents; copying only the main file would omit recent saves.
        var result = sqlite3_backup_step(backup, -1)
        for _ in 0..<10 where result == SQLITE_BUSY || result == SQLITE_LOCKED {
            sqlite3_sleep(50)
            result = sqlite3_backup_step(backup, -1)
        }
        let finished = sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE, finished == SQLITE_OK else {
            throw BackupError.invalid("The database is busy or unavailable. Please try again; no data was replaced.")
        }
    }
}
