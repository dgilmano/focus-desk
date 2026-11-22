#if DEBUG || FOCUS_DESK_PERSONAL
import AppKit
import SwiftUI

/// Select the existing name as soon as the inline field is installed in the map's window.
struct DeskMapNameField: NSViewRepresentable {
    let label: String
    @Binding var text: String
    let submit: () -> Void
    let cancel: () -> Void

    func makeNSView(context: Context) -> Field {
        let field = Field()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 12)
        field.usesSingleLineMode = true
        field.delegate = context.coordinator
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: Field, context: Context) {
        context.coordinator.editor = self
        if field.stringValue != text { field.stringValue = text }
        field.setAccessibilityLabel(label)
    }

    func makeCoordinator() -> Coordinator { Coordinator(editor: self) }

    final class Field: NSTextField {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, let window, window.makeFirstResponder(self) else { return }
                selectText(nil)
            }
        }
    }

    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var editor: DeskMapNameField
        init(editor: DeskMapNameField) { self.editor = editor }

        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField { editor.text = field.stringValue }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                editor.submit()
            case #selector(NSResponder.cancelOperation(_:)):
                editor.cancel()
            default:
                return false
            }
            return true
        }
    }
}
#endif
