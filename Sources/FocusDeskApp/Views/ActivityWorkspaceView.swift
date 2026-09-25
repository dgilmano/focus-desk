import SwiftUI

struct ActivityWorkspaceView: View {
    @Binding var selectedDate: Date?

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = max(0, geometry.size.width - 56)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ActivityPaletteView(availableWidth: contentWidth)

                    Rectangle()
                        .fill(FocusDeskStyle.hairline)
                        .frame(height: 1)
                        .padding(.vertical, 28)

                    TimelineView(.periodic(from: .now, by: 30)) { timeline in
                        ActivityDayMapView(selectedDate: $selectedDate, now: timeline.date,
                                           availableWidth: contentWidth)
                    }
                }
                .frame(width: contentWidth, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, 64)
                .padding(.bottom, 28)
            }
        }
    }
}
