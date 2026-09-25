import SwiftUI

struct WorkspaceColumns<Leading: View, Trailing: View>: View {
    var availableWidth: CGFloat
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        if availableWidth >= FocusDeskStyle.workspaceCompactBreakpoint {
            let columnWidth = (availableWidth - FocusDeskStyle.workspaceColumnSpacing) / 2
            HStack(alignment: .top, spacing: FocusDeskStyle.workspaceColumnSpacing) {
                leading().frame(width: columnWidth, alignment: .topLeading)
                trailing().frame(width: columnWidth, alignment: .topLeading)
            }
            .overlay {
                Rectangle().fill(FocusDeskStyle.hairline).frame(width: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        } else {
            VStack(alignment: .leading, spacing: 28) {
                leading()
                Divider()
                trailing()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
