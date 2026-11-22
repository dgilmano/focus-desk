import AppKit

@MainActor
enum FocusDeskBrand {
    static let mark: NSImage = {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "FocusDeskMark", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else {
            return NSApplication.shared.applicationIconImage
        }
        return image
    }()
}
