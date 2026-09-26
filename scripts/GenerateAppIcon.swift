import AppKit
import Foundation

// Original, provisional Focus Desk artwork. No system symbols or external assets.
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
        let transform = AffineTransform(scale: CGFloat(pixels) / 1024)
        (transform as NSAffineTransform).concat()

        func fill(_ rect: NSRect, radius: CGFloat, color: NSColor) {
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        }
        fill(NSRect(x: 64, y: 64, width: 896, height: 896), radius: 196,
             color: NSColor(srgbRed: 0.14, green: 0.16, blue: 0.18, alpha: 1))
        fill(NSRect(x: 196, y: 218, width: 136, height: 588), radius: 32,
             color: NSColor(srgbRed: 0.30, green: 0.65, blue: 0.61, alpha: 1))
        fill(NSRect(x: 396, y: 470, width: 432, height: 336), radius: 40,
             color: NSColor(srgbRed: 0.97, green: 0.97, blue: 0.96, alpha: 1))
        fill(NSRect(x: 396, y: 218, width: 432, height: 188), radius: 36,
             color: NSColor(srgbRed: 0.76, green: 0.80, blue: 0.79, alpha: 1))
        NSGraphicsContext.restoreGraphicsState()

        let filename = "icon_\(points)x\(points)@\(scale)x.png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(filename))
        entries.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": filename])
    }
}
let catalog: [String: Any] = ["images": entries, "info": ["author": "Focus Desk", "version": 1]]
try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("Contents.json"))
