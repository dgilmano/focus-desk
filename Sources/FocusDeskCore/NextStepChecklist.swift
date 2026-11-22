import Foundation

/// Presents the existing multiline task field as a checklist without rewriting the stored note.
public struct NextStepChecklist {
    public struct Item: Identifiable {
        public let id: Int
        public let text: String
        public let isCompleted: Bool
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
            guard !text.isEmpty else { continue }
            let isCompleted = match.output.1?.lowercased() == "x"
            items.append(Item(id: items.count, text: text, isCompleted: isCompleted,
                              lineRange: line.startIndex..<line.endIndex))
        }
        self.items = items
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
