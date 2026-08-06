import FocusDeskCore
import SwiftUI

struct MarkdownText: View {
    var source: String
    var font: Font
    var lineLimit: Int?

    init(_ source: String, font: Font = .body, lineLimit: Int? = nil) {
        self.source = source
        self.font = font
        self.lineLimit = lineLimit
    }

    var body: some View {
        Text(MarkdownFormatting.attributedString(from: source))
            .font(font)
            .lineLimit(lineLimit)
    }
}
