import Foundation

public enum MarkdownFormatting {
    public static func attributedString(from source: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )

        return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
    }
}
