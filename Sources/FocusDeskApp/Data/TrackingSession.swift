import Foundation
import SwiftData

@Model
final class TrackingSession {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var lastObservedAt: Date

    init(id: UUID = UUID(), start: Date, end: Date? = nil) {
        self.id = id
        self.startedAt = start
        self.endedAt = end
        self.lastObservedAt = end ?? start
    }
}
