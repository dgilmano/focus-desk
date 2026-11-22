import Foundation

/// Presents the existing multiline task field as a checklist without rewriting the stored note.
public struct NextStepChecklist {
    public struct Item: Identifiable {
        public let id: Int
        public let text: String
        public let isCompleted: Bool
        fileprivate let textRange: Range<String.Index>
        fileprivate let lineRange: Range<String.Index>
    }

    public let items: [Item]
    private let source: String

    public init(_ source: String) {
        self.source = source
        var items: [Item] = []
        // A list prefix and a Markdown checkbox are both optional for older, plain-text steps.
        let prefix = #/^\h*(?:(?:[-+*•]|[0-9]{1,9}[.)])\h+)?(?:\[([ xX])\](?=\h|$))?/#
        for line in source.split(whereSeparator: \.isNewline) {
            guard let match = line.prefixMatch(of: prefix) else { continue }
            let start = match.range.upperBound
            let text = line[start...].trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, let textRange = line[start...].range(of: text, options: .literal) else { continue }
            let isCompleted = match.output.1?.lowercased() == "x"
            items.append(Item(id: items.count, text: text, isCompleted: isCompleted,
                              textRange: textRange, lineRange: line.startIndex..<line.endIndex))
        }
        self.items = items
    }

    /// Change only the label, preserving the list marker, checkbox, spacing and line endings.
    public func renaming(_ id: Item.ID, to input: String) -> String? {
        let title = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard items.indices.contains(id), !title.isEmpty, !title.contains(where: \.isNewline) else { return nil }
        let item = items[id]
        var label = title
        let line = source[item.lineRange].replacingCharacters(in: item.textRange, with: title)
        let parsed = NextStepChecklist(line).items.first
        if parsed?.text != title || parsed?.isCompleted != item.isCompleted {
            // An explicit checkbox keeps a literal leading “1.” or “[x]” part of the new label.
            label = "[ ] " + title
        }
        return source.replacingCharacters(in: item.textRange, with: label)
    }

    public func removing(_ id: Item.ID) -> String {
        guard items.indices.contains(id) else { return source }
        var range = items[id].lineRange
        if range.upperBound < source.endIndex {
            range = range.lowerBound..<source.index(after: range.upperBound)
        } else if range.lowerBound > source.startIndex {
            range = source.index(before: range.lowerBound)..<range.upperBound
        }
        return source.replacingCharacters(in: range, with: "")
    }
}
