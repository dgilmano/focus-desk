#if DEBUG
import Foundation
import SwiftData
import FocusDeskCore

// Isolated, in-memory data for visual checks; never used in release builds.
@MainActor
enum ActivityPreview {
    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains("--activity-preview") || Bundle.main.bundleIdentifier == "com.focusdesk.preview"
    }

    // Re-create the same sample tasks across launches so UI preferences remain usable in the preview.
    private static func sampleID(_ index: Int) -> UUID {
        UUID(uuid: (0xF0, 0xC0, 0xDE, 0x51, 0x11, 0xED, 0x42, 0x17, 0xAB, 0x04, 0, 0, 0, 0, 0, UInt8(index)))
    }

    static func seed(container: ModelContainer, store: ActivityStore) {
        let context = container.mainContext
        let task = FocusTask(id: sampleID(0), title: "Build a calmer working day", sortOrder: 0,
                             motivation: "Make room for **focused work**, learning and proper breaks.",
                             nextStep: "Review **today's activity** and choose the next useful step.")
        context.insert(task)
        context.insert(ProgressEntry(note: "Reviewed the **weekly plan**.", timestamp: Date().addingTimeInterval(-3600), task: task))
        task.tagRecords = [TaskTagRecord(name: "Design", colorName: "mint")]
        seedDeskTasks(in: context)
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
            store.startTracking(at: start)
            store.start(work.id, at: start.addingTimeInterval(available * 330 / 420))
        }
    }

    private static func seedDeskTasks(in context: ModelContext) {
        let examples = [
            ("Type scale", "Design", "mint", "Check small labels in **dark mode**.", "Keep dense screens **legible**.",
             ["Reviewed **secondary labels**.", "Compared **2 weights**.", "Checked captions.", "Set body size."]),
            ("Export notes", "Build", "purple", "Test a journal export.", "Keep a portable copy of task history.",
             ["Checked the title field.", "Outlined the export format.", "Verified entry order."]),
            ("Shortcuts", "Build", "purple", "Try the shortcut with one hand.", "Make frequent actions easier to reach.",
             ["Listed common actions.", "Drafted bindings."]),
            ("Field notes", "Research", "brown", "Group the last three observations.", "Find friction in daily work.",
             ["Collected observations.", "Tagged the first notes.", "Read the second session."]),
            ("Interviews", "Research", "brown", "Pull out one recurring theme.", "Understand how a working day starts.",
             ["Read the transcript.", "Prepared prompts."]),
            ("Улучшение Focus Desk", "Build", "purple",
             "1. Проверить раскрытие **Next step** на карте.\n2. Сверить отступы в узком окне.\n3. Проверить читаемость в тёмной теме.",
             "Видеть ближайшие действия прямо на карте задач.", [])
        ]
        for (index, example) in examples.enumerated() {
            let (title, tag, color, step, why, notes) = example
            let task = FocusTask(id: sampleID(index + 1), title: title, sortOrder: index + 1, motivation: why, nextStep: step)
            task.tagRecords = [TaskTagRecord(name: tag, colorName: color)]
            context.insert(task)
            for (offset, note) in notes.enumerated() {
                context.insert(ProgressEntry(note: note, timestamp: Date().addingTimeInterval(-3600 * Double(offset + 1)), task: task))
            }
        }
    }

}
#else
enum ActivityPreview {
    static let isActive = false
}
#endif
