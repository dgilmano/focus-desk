import FocusDeskCore
import SwiftUI

struct MarkdownText: View {
    var source: String
    var font: Font
    var lineLimit: Int?
    var emphasisColor: Color?

    init(_ source: String, font: Font = .body, lineLimit: Int? = nil, emphasisColor: Color? = nil) {
        self.source = source
        self.font = font
        self.lineLimit = lineLimit
        self.emphasisColor = emphasisColor
    }

    var body: some View {
        Text(formattedText)
            .font(font)
            .lineLimit(lineLimit)
    }

    private var formattedText: AttributedString {
        var text = MarkdownFormatting.attributedString(from: source)
        guard let emphasisColor else { return text }
        for run in text.runs {
            guard run.link == nil, let intent = run.inlinePresentationIntent,
                  !intent.intersection([.stronglyEmphasized, .code]).isEmpty else { continue }
            text[run.range].foregroundColor = emphasisColor
        }
        return text
    }
}
