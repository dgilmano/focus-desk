import SwiftUI

struct EmptyDeskView: View {
    var createTask: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            OrbIcon(systemName: "rectangle.stack", filled: true)
                .scaleEffect(1.35)

            Text("No active tasks")
                .font(.system(size: 30, weight: .semibold))

            Button {
                createTask()
            } label: {
                Label("New Task", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("n", modifiers: [.command])
        }
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(OrbStyle.groupedBackground)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }
}
