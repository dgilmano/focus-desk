#if (DEBUG && !FOCUS_DESK_UPDATES) || FOCUS_DESK_PERSONAL
import SwiftUI

@MainActor enum VoiceTaskPreferences {
    static let instructionsKey = ActivityPreview.isActive ? "previewOpenAITaskInstructions" : "openAITaskInstructions"
}

struct OpenAITaskSettings: View {
    @AppStorage(VoiceTaskPreferences.instructionsKey) private var instructions = ""
    @FocusState private var editing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OpenAI")
                .font(FocusDeskStyle.workspaceSectionFont)
                .accessibilityAddTraits(.isHeader)
            Text("Task instructions")
                .font(.headline)
                .padding(.top, 8)
            ZStack(alignment: .topLeading) {
                if instructions.isEmpty {
                    Text("For example, start each next step with a verb and keep technical terms in their original language.")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                TextEditor(text: $instructions)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .focused($editing)
                    .accessibilityLabel("Task instructions")
            }
            .font(.body)
            .background(FocusDeskStyle.groupedBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(editing ? FocusDeskStyle.deskAccent : FocusDeskStyle.hairline)
                    .allowsHitTesting(false)
            }
            Text("Rules are saved automatically on this Mac and sent to OpenAI when you choose Create draft for a new or existing task.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(minWidth: 380, idealWidth: 480, minHeight: 280, idealHeight: 340)
        .background(FocusDeskStyle.appBackground)
    }
}
#endif
