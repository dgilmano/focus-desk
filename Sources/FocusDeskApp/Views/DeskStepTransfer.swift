import SwiftUI
import UniformTypeIdentifiers

struct DeskStepDrag: Codable, Transferable {
    let taskID: UUID
    let stepID: Int
    let source: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: UTType(exportedAs: "com.focusdesk.next-step"))
            .visibility(.ownProcess)
    }
}

struct DeskJournalDrag: Codable, Transferable {
    let taskID: UUID
    let entryID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: UTType(exportedAs: "com.focusdesk.journal-entry"))
            .visibility(.ownProcess)
    }
}

struct DeskTransferTarget<Item: Transferable>: ViewModifier {
    let move: (Item) -> Bool
    @State private var targeted = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .overlay {
                if targeted {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .allowsHitTesting(false)
                }
            }
            .dropDestination(for: Item.self) { items, _ in
                guard items.count == 1, let item = items.first else { return false }
                return move(item)
            } isTargeted: { targeted = $0 }
    }
}
