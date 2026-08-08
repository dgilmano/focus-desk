import Foundation
import SwiftData

enum PersistenceController {
    private static let storeName = "FocusDeskStore"

    @MainActor
    static func makeModelContainer(inMemory: Bool = false) -> ModelContainer {
        if !inMemory {
            migrateLegacyStoreIfNeeded()
        }

        let schema = Schema([
            FocusTask.self,
            ProgressEntry.self
        ])

        let configuration = ModelConfiguration(
            storeName,
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Unable to create Focus Desk SwiftData store: \(error)")
        }
    }

    private static func migrateLegacyStoreIfNeeded(fileManager: FileManager = .default) {
        guard let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }

        let newStoreURL = applicationSupportURL.appendingPathComponent("\(storeName).store")

        guard !fileManager.fileExists(atPath: newStoreURL.path) else {
            return
        }

        let legacyStoreName = ["Focus", "Car", "ouselStore"].joined()
        let legacyStoreURL = applicationSupportURL.appendingPathComponent("\(legacyStoreName).store")

        guard fileManager.fileExists(atPath: legacyStoreURL.path) else {
            return
        }

        for suffix in ["", "-shm", "-wal"] {
            let sourceURL = applicationSupportURL.appendingPathComponent("\(legacyStoreName).store\(suffix)")
            let destinationURL = applicationSupportURL.appendingPathComponent("\(storeName).store\(suffix)")

            guard fileManager.fileExists(atPath: sourceURL.path), !fileManager.fileExists(atPath: destinationURL.path) else {
                continue
            }

            try? fileManager.copyItem(at: sourceURL, to: destinationURL)
        }
    }
}
