#if DEBUG || FOCUS_DESK_PERSONAL
import CryptoKit
import FocusDeskCore
import SwiftUI

struct DeskMapSteps {
    struct ID: Hashable {
        let task: UUID
        let index: Int
    }

    /// Checklist rows have no persistent ID. Identify their labels without copying note text into preferences.
    struct PlacementKey: Hashable, Codable {
        let task: UUID
        let digest: Data
        let occurrence: Int
        let copies: Int

        static func keys(task: UUID, labels: [String]) -> [Self] {
            let counts = labels.reduce(into: [:]) { $0[$1, default: 0] += 1 }
            var seen: [String: Int] = [:]
            return labels.map { label in
                let ordinal = seen[label, default: 0]
                seen[label] = ordinal + 1
                return Self(task: task, digest: Data(SHA256.hash(data: Data(label.utf8))),
                            occurrence: ordinal, copies: counts[label, default: 1])
            }
        }
    }

    struct Leaf: Identifiable {
        let id: ID
        let key: PlacementKey
        let step: NextStepChecklist.Item
        var frame: CGRect
        let junctionX: CGFloat
        let parent: CGPoint
        let palette: TaskTagPalette
        var isManuallyPlaced = false

        var offsetFromParent: CGSize {
            CGSize(width: frame.midX - parent.x, height: frame.midY - parent.y)
        }

        mutating func move(by delta: CGSize, in size: CGSize) {
            frame.origin.x = min(max(0, frame.minX + delta.width), max(0, size.width - frame.width))
            frame.origin.y = min(max(0, frame.minY + delta.height), max(0, size.height - frame.height))
            isManuallyPlaced = true
        }
    }

    private(set) var leaves: [Leaf]
    let height: CGFloat
    static let rowHeight: CGFloat = 40

    private static func columns(count: Int, width: CGFloat) -> Int {
        count > 1 && width >= 300 ? 2 : 1
    }

    static func reservedHeight(count: Int, width: CGFloat) -> CGFloat {
        let columns = columns(count: count, width: width)
        return CGFloat((count + columns - 1) / columns) * rowHeight
    }

    init(layout: DeskTaskMapLayout, items: [DeskTaskMapLayout.Item], width: CGFloat,
         offsets: [PlacementKey: CGSize] = [:]) {
        var leaves: [Leaf] = []
        var occupied = layout.visibleTaskIndices.map { layout.nodes[$0].chipBounds }
        for group in layout.groups {
            occupied.append(group.hubBounds)
            occupied.append(CGRect(x: group.label.x - group.labelWidth / 2, y: group.label.y - 11, width: group.labelWidth, height: 22))
        }
        var height = layout.mapHeight
        for group in layout.groups {
            for i in group.visibleIndices where !items[i].steps.isEmpty {
                let item = items[i]
                let keys = PlacementKey.keys(task: item.id, labels: item.steps.map(\.text))
                let parent = layout.nodes[i].center
                let columns = Self.columns(count: item.steps.count, width: group.width)
                let gap: CGFloat = 14
                let cardWidth = max(1, min(206, (group.width - 20 - CGFloat(columns - 1) * gap) / CGFloat(columns)))
                let span = CGFloat(columns) * cardWidth + CGFloat(columns - 1) * gap
                let left = min(max(10, parent.x - span / 2), max(0, width - 10 - span))
                let spine = columns == 1 && item.steps.count > 1 ? max(2, left - 7) : left + span / 2
                var y = parent.y + 24
                for start in stride(from: 0, to: item.steps.count, by: columns) {
                    let count = min(columns, item.steps.count - start)
                    let rowWidth = CGFloat(count) * cardWidth + CGFloat(count - 1) * gap
                    let x = left + (span - rowWidth) / 2
                    var row = CGRect(x: x, y: y, width: rowWidth, height: 31)
                    // Saved task and label positions can occupy an otherwise reserved row.
                    while let bottom = occupied.lazy.filter({ $0.insetBy(dx: -4, dy: -4).intersects(row) }).map(\.maxY).max() {
                        row.origin.y = bottom + 5
                    }
                    for column in 0..<count {
                        let step = item.steps[start + column]
                        let frame = CGRect(x: x + CGFloat(column) * (cardWidth + gap), y: row.minY, width: cardWidth, height: row.height)
                        leaves.append(Leaf(id: ID(task: item.id, index: step.id), key: keys[start + column], step: step, frame: frame,
                                           junctionX: spine, parent: parent, palette: item.palette))
                    }
                    occupied.append(row)
                    height = max(height, row.maxY + 10)
                    y = row.minY + Self.rowHeight
                }
            }
        }
        let size = CGSize(width: width, height: height)
        for i in leaves.indices {
            guard let saved = offsets[leaves[i].key] else { continue }
            let current = leaves[i].offsetFromParent
            leaves[i].move(by: CGSize(width: saved.width - current.width, height: saved.height - current.height), in: size)
        }
        self.leaves = leaves
        self.height = height
    }

    func moving(_ drag: DeskMapDrag?, width: CGFloat) -> Self {
        guard let drag, case .step(let key) = drag.target,
              let index = leaves.firstIndex(where: { $0.key == key }) else { return self }
        var moved = self
        moved.leaves[index].move(by: drag.translation, in: CGSize(width: width, height: height))
        return moved
    }
}
#endif
