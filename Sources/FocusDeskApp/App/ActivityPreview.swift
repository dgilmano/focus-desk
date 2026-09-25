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
        let start = max(Calendar.current.startOfDay(for: now), now.addingTimeInterval(-8 * 3600))
        let available = now.timeIntervalSince(start)
        let pieces: [(Int, Double, Double)] = [(0, 0, 0.28), (3, 0.28, 0.35), (1, 0.4, 0.65), (0, 0.65, 0.9)]
        for (index, from, to) in pieces {
            _ = store.saveInterval(id: nil, categoryID: store.categories[index].id,
                                   start: start.addingTimeInterval(available * from),
                                   end: start.addingTimeInterval(available * to),
                                   taskID: index == 0 ? task.id : nil, taskTitle: index == 0 ? task.title : nil)
        }
        store.start(store.categories[0].id, at: start.addingTimeInterval(available * 0.9))
    }
}
#endif
