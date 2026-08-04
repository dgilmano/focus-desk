import SwiftUI

struct CompletionToastView: View {
    var toast: CompletionToast
    var undo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            OrbIcon(systemName: "checkmark.circle", filled: true)

            Text("Task completed")
                .font(.system(size: 14, weight: .semibold))

            Button("Undo") {
                undo()
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("z", modifiers: [.command])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(OrbStyle.groupedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Task completed. Undo available.")
    }
}
