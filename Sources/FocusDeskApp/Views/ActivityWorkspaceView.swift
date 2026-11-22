import SwiftUI

struct ActivityWorkspaceView: View {
    @Binding var selectedDate: Date?

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = FocusDeskStyle.workspaceContentWidth(for: geometry.size.width)
            let innerWidth = max(0, contentWidth - FocusDeskStyle.panelPadding * 2)
            ScrollView {
                TimelineView(.periodic(from: .now, by: 30)) { timeline in
                    ActivityDayMapView(selectedDate: $selectedDate, now: timeline.date,
                                       availableWidth: innerWidth)
                }
                .workspacePanel()
                .frame(width: contentWidth, alignment: .leading)
                .padding(FocusDeskStyle.workspaceInsets)
                .padding(.bottom, 28)
            }
        }
    }
}
