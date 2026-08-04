import FocusCarouselCore
import Foundation

#if canImport(WidgetKit)
import WidgetKit
#endif

enum WidgetSnapshotWriter {
    static func write(currentTask: FocusTask?, activeTaskCount: Int) {
        let snapshot: WidgetSnapshot

        if let currentTask {
            snapshot = WidgetSnapshot(
                currentTaskTitle: currentTask.title,
                latestProgressNote: currentTask.latestEntry?.note,
                latestProgressTimestamp: currentTask.latestEntry?.timestamp,
                activeTaskCount: activeTaskCount
            )
        } else {
            snapshot = .empty
        }

        WidgetSnapshotStore().write(snapshot)

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
