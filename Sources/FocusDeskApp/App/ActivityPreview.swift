#if DEBUG
import Foundation
import SwiftData

// Isolated, in-memory data for visual checks; never used in release builds.
@MainActor
enum ActivityPreview {
    static func seed(container: ModelContainer, store: ActivityStore) {
        let context = container.mainContext
        let task = FocusTask(title: "Build a calmer working day", sortOrder: 0,
                             motivation: "Make room for focused work, learning and proper breaks.",
                             nextStep: "Review today's activity and choose the next useful step.")
        context.insert(task)
        context.insert(ProgressEntry(note: "Reviewed the weekly plan.", timestamp: Date().addingTimeInterval(-3600), task: task))
        try? context.save()
        let now = Date()
        for (name, color, symbol) in [("Work", "mint", "briefcase"), ("Study", "blue", "book"),
                                       ("Rest", "green", "leaf"), ("Leisure", "pink", "gamecontroller")] {
            _ = store.saveCategory(id: store.categories.first { $0.name == name }?.id,
                                   name: name, color: color, symbol: symbol)
        }
        let start = max(Calendar.current.startOfDay(for: now), now.addingTimeInterval(-7 * 3600))
        let available = now.timeIntervalSince(start)
        let pieces: [(String, Double, Double)] = [
            ("Work", 0, 110), ("Rest", 110, 130), ("Study", 130, 200),
            ("Life", 200, 245), ("Leisure", 245, 275), ("Other", 275, 285), ("Rest", 315, 330)
        ]
        for (name, from, to) in pieces {
            guard let category = store.categories.first(where: { $0.name == name }) else { continue }
            _ = store.saveInterval(id: nil, categoryID: category.id,
                                   start: start.addingTimeInterval(available * from / 420),
                                   end: start.addingTimeInterval(available * to / 420),
                                   taskID: name == "Work" ? task.id : nil,
                                   taskTitle: name == "Work" ? task.title : nil)
        }
        if let work = store.categories.first(where: { $0.name == "Work" }) {
            store.start(work.id, at: start.addingTimeInterval(available * 330 / 420))
        }
    }
}
#endif
