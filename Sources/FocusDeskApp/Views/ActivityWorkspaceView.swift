import SwiftUI

struct ActivityWorkspaceView: View {
    @Binding var selectedDate: Date?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ActivityPaletteView()

                Divider()

                TimelineView(.periodic(from: .now, by: 30)) { timeline in
                    ActivityDayMapView(selectedDate: $selectedDate, now: timeline.date)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 28)
        }
    }
}
