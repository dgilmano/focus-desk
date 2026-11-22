import AppKit
import Foundation

// Rasterize the same artwork used by the sidebar for each macOS icon slot.
let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Sources/FocusDeskApp/Brand/FocusDeskMark.svg")
guard let mark = NSImage(contentsOf: source) else {
    throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: source.path])
}
let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var entries: [[String: String]] = []

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        mark.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
                  from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        let filename = "icon_\(points)x\(points)@\(scale)x.png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(filename))
        entries.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": filename])
    }
}
let catalog: [String: Any] = ["images": entries, "info": ["author": "Focus Desk", "version": 1]]
try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("Contents.json"))
