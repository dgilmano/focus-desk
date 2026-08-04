import AppKit
import SwiftUI

struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        configureSoon(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configureSoon(from: nsView)
    }

    private func configureSoon(from view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else {
                return
            }

            window.styleMask.insert(.fullSizeContentView)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.toolbar = nil
            window.isMovableByWindowBackground = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.contentView?.wantsLayer = true
            window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
}
