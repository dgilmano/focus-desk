#if DEBUG || FOCUS_DESK_PERSONAL
import Foundation

struct DeskMapDrag: Equatable {
    enum Target: Equatable {
        case task(UUID)
        case step(DeskMapSteps.PlacementKey)
        case group(String)
        case label(String)
    }

    let target: Target
    let translation: CGSize
    var location: CGPoint?
}

/// Store only manual placements. Steps stay at a point offset from their owning task.
struct DeskMapArrangement: Codable, Equatable {
    var tasks: [UUID: CGPoint] = [:]
    var stepOffsets: [DeskMapSteps.PlacementKey: CGSize] = [:]
    var groups: [String: CGPoint] = [:]
    // Relative to the hub in units of the cloud radius, independent of the cloud's placement.
    var labels: [String: CGPoint] = [:]
    var groupOrder: [String] = []
    var isEmpty: Bool { tasks.isEmpty && stepOffsets.isEmpty && groups.isEmpty && labels.isEmpty && groupOrder.isEmpty }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        tasks = try values.decode([UUID: CGPoint].self, forKey: .tasks)
        stepOffsets = try values.decodeIfPresent([DeskMapSteps.PlacementKey: CGSize].self, forKey: .stepOffsets) ?? [:]
        groups = try values.decode([String: CGPoint].self, forKey: .groups)
        labels = try values.decodeIfPresent([String: CGPoint].self, forKey: .labels) ?? [:]
        groupOrder = try values.decodeIfPresent([String].self, forKey: .groupOrder) ?? []
    }

    mutating func renameStep(at index: Int, in task: UUID, labels: [String], to name: String) {
        guard labels.indices.contains(index), stepOffsets.keys.contains(where: { $0.task == task }) else { return }
        var renamed = labels
        renamed[index] = name
        let oldKeys = DeskMapSteps.PlacementKey.keys(task: task, labels: labels)
        let newKeys = DeskMapSteps.PlacementKey.keys(task: task, labels: renamed)
        let previous = stepOffsets
        // A rename to or from a duplicate label can also change its siblings' occurrence numbers.
        for key in oldKeys { stepOffsets.removeValue(forKey: key) }
        for (old, new) in zip(oldKeys, newKeys) { stepOffsets[new] = previous[old] }
    }

    mutating func renameGroup(from oldID: String, to newID: String) {
        guard oldID != newID else { return }
        groups[newID] = groups.removeValue(forKey: oldID)
        labels[newID] = labels.removeValue(forKey: oldID)
        groupOrder.removeAll { $0 == newID }
        if let index = groupOrder.firstIndex(of: oldID) { groupOrder[index] = newID }
    }

    mutating func remember(_ target: DeskMapDrag.Target, in layout: DeskTaskMapLayout,
                           items: [DeskTaskMapLayout.Item], width: CGFloat) {
        guard width > 0, layout.mapHeight > 0 else { return }
        func normalized(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x / width, y: point.y / layout.mapHeight)
        }
        switch target {
        case .step: break
        case .task(let id):
            guard let index = items.firstIndex(where: { $0.id == id }) else { return }
            tasks[id] = normalized(layout.nodes[index].center)
        case .group(let id):
            guard let group = layout.groups.first(where: { $0.id == id }) else { return }
            groups[id] = normalized(group.placementAnchor)
            for index in group.indices {
                tasks[items[index].id] = normalized(layout.nodes[index].center)
            }
        case .label(let id):
            guard let group = layout.groups.first(where: { $0.id == id }), group.radius > 0 else { return }
            labels[id] = CGPoint(x: (group.label.x - group.center.x) / group.radius,
                                 y: (group.label.y - group.center.y) / group.radius)
        }
    }
}

extension DeskTaskMapLayout {
    func placing(_ arrangement: DeskMapArrangement, items: [Item], width: CGFloat) -> Self {
        guard !arrangement.isEmpty else { return self }
        let area = CGRect(x: 0, y: 0, width: width, height: mapHeight)
        var result = self
        for g in groups.indices {
            let group = groups[g]
            var groupShift = CGSize.zero
            if let saved = arrangement.groups[group.id] {
                let requested = translation(to: saved, from: group.placementAnchor, in: area)
                let bounds = arrangement.labels[group.id] == nil ? group.handleBounds : group.hubBounds
                groupShift = limited(requested, moving: bounds, in: area)
                result.groups[g].center = group.center.offset(by: groupShift)
                result.groups[g].label = group.label.offset(by: groupShift)
            }
            if let offset = arrangement.labels[group.id] {
                let placed = result.groups[g]
                let point = placed.center.offset(by: CGSize(width: offset.x * placed.radius, height: offset.y * placed.radius))
                result.groups[g].label = placed.labelPosition(nearest: point, in: area)
            }
            for i in group.indices {
                let node = nodes[i]
                let shift = arrangement.tasks[items[i].id].map { translation(to: $0, from: node.center, in: area) } ?? groupShift
                result.nodes[i].center = node.center.offset(by: limited(shift, moving: node.chipBounds, in: area))
            }
        }
        return result
    }

    func moving(_ drag: DeskMapDrag, items: [Item], width: CGFloat) -> Self {
        let area = CGRect(x: 0, y: 0, width: width, height: mapHeight)
        var result = self
        switch drag.target {
        case .step: return self
        case .label(let id):
            guard let g = groups.firstIndex(where: { $0.id == id }) else { return self }
            let group = groups[g]
            result.groups[g].label = group.labelPosition(nearest: group.label.offset(by: drag.translation), in: area)
        case .task(let id):
            guard let i = items.firstIndex(where: { $0.id == id }) else { return self }
            result.nodes[i].center = nodes[i].center.offset(by: limited(drag.translation, moving: nodes[i].chipBounds, in: area))
        case .group(let id):
            guard let g = groups.firstIndex(where: { $0.id == id }) else { return self }
            let group = groups[g]
            let bounds = group.indices.reduce(group.handleBounds) { $0.union(nodes[$1].chipBounds) }
            let shift = limited(drag.translation, moving: bounds, in: area)
            result.groups[g].label = group.label.offset(by: shift)
            result.groups[g].center = group.center.offset(by: shift)
            for i in group.indices {
                result.nodes[i].center = nodes[i].center.offset(by: shift)
            }
        }
        return result
    }

    private func translation(to normalized: CGPoint, from origin: CGPoint, in area: CGRect) -> CGSize {
        CGSize(width: normalized.x * area.width - origin.x, height: normalized.y * area.height - origin.y)
    }

    private func limited(_ shift: CGSize, moving bounds: CGRect, in area: CGRect) -> CGSize {
        CGSize(width: min(max(shift.width, area.minX - bounds.minX), area.maxX - bounds.maxX),
               height: min(max(shift.height, area.minY - bounds.minY), area.maxY - bounds.maxY))
    }
}

private extension DeskTaskMapLayout.Group {
    func labelPosition(nearest point: CGPoint, in area: CGRect) -> CGPoint {
        // Reserve space for the text rectangle at the edge of the circular halo.
        let halfWidth = labelWidth / 2
        let halfHeight: CGFloat = 11
        func clamp(_ value: CGFloat, around origin: CGFloat, range: CGFloat, inset: CGFloat, size: CGFloat) -> CGFloat {
            let insideCloud = min(max(value, origin - range), origin + range)
            return min(max(insideCloud, inset), max(inset, size - inset))
        }
        let verticalInset = max(halfHeight, 2 * halfHeight - center.y, 2 * halfHeight + center.y - area.height)
        let dx = max(0, sqrt(max(0, radius * radius - verticalInset * verticalInset)) - halfWidth)
        let x = clamp(point.x, around: center.x, range: dx, inset: halfWidth, size: area.width)
        let edge = abs(x - center.x) + halfWidth
        let dy = max(0, sqrt(max(0, radius * radius - edge * edge)) - halfHeight)
        let y = clamp(point.y, around: center.y, range: dy, inset: halfHeight, size: area.height)
        return CGPoint(x: x, y: y)
    }

    var handleBounds: CGRect {
        CGRect(x: label.x - labelWidth / 2, y: label.y - 11, width: labelWidth, height: 22)
            .union(hubBounds)
    }
}

extension DeskTaskMapLayout.Node {
    var chipBounds: CGRect {
        CGRect(x: center.x - chipWidth / 2, y: center.y - 11, width: chipWidth, height: 22)
    }
}

private extension CGPoint {
    func offset(by shift: CGSize) -> CGPoint { CGPoint(x: x + shift.width, y: y + shift.height) }
}
#endif
