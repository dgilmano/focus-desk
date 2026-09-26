import FocusDeskCore
import Foundation

#if FOCUS_DESK_WIDGET_HOST && canImport(WidgetKit)
import WidgetKit
#endif

enum WidgetSnapshotWriter {
    static func write(currentTask: FocusTask?, activeTaskCount: Int) {
        // Enable only together with a signed widget extension and a real App Group.
        #if FOCUS_DESK_WIDGET_HOST
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
        #endif
    }
}
