import FocusDeskCore
import SwiftUI
import WidgetKit

struct FocusDeskTimelineEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot
}

struct FocusDeskTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> FocusDeskTimelineEntry {
        FocusDeskTimelineEntry(
            date: Date(),
            snapshot: WidgetSnapshot(
                currentTaskTitle: "Configure EVPN Export Policy",
                latestProgressNote: "Need to verify CSC routes on PE2.",
                latestProgressTimestamp: Date(),
                activeTaskCount: 4
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (FocusDeskTimelineEntry) -> Void) {
        completion(FocusDeskTimelineEntry(date: Date(), snapshot: WidgetSnapshotStore().read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FocusDeskTimelineEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore().read()
        let entry = FocusDeskTimelineEntry(date: Date(), snapshot: snapshot)
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct FocusDeskWidgetView: View {
    var entry: FocusDeskTimelineEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "rectangle.stack.fill")
                    .foregroundStyle(Color.accentColor)

                Spacer()

                Text("\(entry.snapshot.activeTaskCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(entry.snapshot.currentTaskTitle)
                .font(.headline)
                .lineLimit(3)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 4)

            if let note = entry.snapshot.latestProgressNote, !note.isEmpty {
                Text(MarkdownFormatting.attributedString(from: note))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            } else {
                Text("Ready")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(.background, for: .widget)
    }
}

struct FocusDeskWidget: Widget {
    let kind = "FocusDeskWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FocusDeskTimelineProvider()) { entry in
            FocusDeskWidgetView(entry: entry)
        }
        .configurationDisplayName("Focus Desk")
        .description("Shows the next active task and latest progress note.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#if FOCUS_DESK_WIDGET_EXTENSION
@main
struct FocusDeskWidgetBundle: WidgetBundle {
    var body: some Widget {
        FocusDeskWidget()
    }
}
#endif
