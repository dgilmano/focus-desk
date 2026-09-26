import Foundation
import SwiftData

// Freeze these definitions and their models when introducing a new schema version.
enum FocusDeskSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [FocusTask.self, ProgressEntry.self] }
}

enum FocusDeskSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(2, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [FocusTask.self, ProgressEntry.self, ActivityCategory.self, ActivityInterval.self]
    }
}

enum FocusDeskMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [FocusDeskSchemaV1.self, FocusDeskSchemaV2.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: FocusDeskSchemaV1.self, toVersion: FocusDeskSchemaV2.self)]
    }
}

enum PersistenceController {
    private static let storeName = "FocusDeskStore"
    static var recoveryDirectory: URL { URL.applicationSupportDirectory.appendingPathComponent("FocusDesk", isDirectory: true) }

    @MainActor
    static func makeModelContainer(inMemory: Bool = false, at storeURL: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: FocusDeskSchemaV2.self)
        let configuration: ModelConfiguration
        if let storeURL {
            configuration = ModelConfiguration(storeName, schema: schema, url: storeURL)
        } else if !inMemory, let recovered = try recoveredStoreURL(in: recoveryDirectory) {
            configuration = ModelConfiguration(storeName, schema: schema, url: recovered)
        } else {
            configuration = ModelConfiguration(storeName, schema: schema, isStoredInMemoryOnly: inMemory)
        }
        if !inMemory && storeURL == nil {
            try migrateLegacyStoreIfNeeded(to: configuration.url)
            if FileManager.default.fileExists(atPath: configuration.url.path) {
                try snapshotBeforeOpening(configuration.url)
            }
        }
        let container = try ModelContainer(for: schema, migrationPlan: FocusDeskMigrationPlan.self, configurations: [configuration])
        if !inMemory && storeURL == nil { try pruneStoreSnapshots() }
        return container
    }

    static func recoveredStoreURL(in directory: URL) throws -> URL? {
        let marker = directory.appendingPathComponent("active-store.json")
        guard FileManager.default.fileExists(atPath: marker.path) else { return nil }
        let name = try JSONDecoder().decode(String.self, from: Data(contentsOf: marker))
        guard name.hasPrefix("recovered-"), name.hasSuffix(".store"), URL(fileURLWithPath: name).lastPathComponent == name else {
            throw BackupError.invalid("The workspace location could not be read. Restore a backup to recover it.")
        }
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw BackupError.invalid("The workspace database is missing. Restore a backup to recover it.")
        }
        return url
    }

    /// Recovery creates a separate database and switches only after it has been saved successfully.
    @MainActor static func recover(_ snapshot: WorkspaceBackup, in directory: URL = recoveryDirectory) throws -> ModelContainer {
        _ = try snapshot.validated()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let name = "recovered-\(UUID().uuidString).store"
        let container = try makeModelContainer(at: directory.appendingPathComponent(name))
        try snapshot.apply(to: container.mainContext)
        try container.mainContext.save()
        // Do not overwrite or delete the unreadable original, its WAL, or previous recovered stores.
        try JSONEncoder().encode(name).write(to: directory.appendingPathComponent("active-store.json"), options: .atomic)
        return container
    }

    @MainActor private static func snapshotBeforeOpening(_ source: URL) throws {
        let directory = BackupStore.defaultDirectory.appendingPathComponent("Store snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try StoreSnapshot.copy(from: source, to: directory.appendingPathComponent("startup-\(UUID().uuidString).store"))
    }

    @MainActor private static func pruneStoreSnapshots() throws {
        let directory = BackupStore.defaultDirectory.appendingPathComponent("Store snapshots", isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        // Failed opens must never prune the last usable pre-migration copy.
        let snapshots = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.lastPathComponent.hasPrefix("startup-") && $0.pathExtension == "store" }
            .sorted {
                let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
        for old in snapshots.dropFirst(5) { try FileManager.default.removeItem(at: old) }
    }

    private static func migrateLegacyStoreIfNeeded(to destination: URL) throws {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: destination.path) else { return }
        let legacyName = ["Focus", "Car", "ouselStore"].joined()
        let source = destination.deletingLastPathComponent().appendingPathComponent("\(legacyName).store")
        guard fileManager.fileExists(atPath: source.path) else { return }
        try StoreSnapshot.copy(from: source, to: destination)
    }
}
