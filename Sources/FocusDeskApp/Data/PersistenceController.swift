import SwiftData

enum PersistenceController {
    @MainActor
    static func makeModelContainer(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema([
            FocusTask.self,
            ProgressEntry.self
        ])

        let configuration = ModelConfiguration(
            "FocusCarouselStore",
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Unable to create Focus Desk SwiftData store: \(error)")
        }
    }
}
