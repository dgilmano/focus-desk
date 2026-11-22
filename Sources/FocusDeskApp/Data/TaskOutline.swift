import Foundation

/// The same ordered hierarchy drives map disclosure, task menus and parent breadcrumbs.
struct TaskOutline {
    struct Item: Identifiable, Equatable {
        let id: UUID
        let parentID: UUID?
        let title: String
        let project: String

        init(id: UUID, parentID: UUID?, title: String, project: String) {
            self.id = id
            self.parentID = parentID
            self.title = title
            self.project = project.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        init(_ task: FocusTask) {
            self.init(id: task.id, parentID: task.parentTaskID, title: task.title, project: task.deskProjectTag?.name ?? "")
        }
    }

    struct Row: Identifiable {
        let item: Item
        let depth: Int
        var id: UUID { item.id }
    }

    let items: [UUID: Item]
    let roots: [UUID]
    let children: [UUID: [UUID]]
    private let parents: [UUID: UUID]

    init(_ ordered: [Item]) {
        items = Dictionary(uniqueKeysWithValues: ordered.map { ($0.id, $0) })
        var links = [UUID: UUID]()
        for item in ordered {
            if let id = item.parentID, let parent = items[id], DeskProject.key(for: parent.project) == DeskProject.key(for: item.project) {
                links[item.id] = id
            }
        }
        // A filtered-out parent makes the child a root. Break invalid cycles for display only.
        var checked = Set<UUID>()
        for item in ordered where !checked.contains(item.id) {
            var path = Set<UUID>()
            var id = item.id
            while let parent = links[id], !checked.contains(id) {
                guard path.insert(id).inserted else { links.removeValue(forKey: id); break }
                id = parent
            }
            checked.formUnion(path)
        }
        parents = links
        roots = ordered.compactMap { links[$0.id] == nil ? $0.id : nil }
        var grouped = [UUID: [UUID]]()
        for item in ordered {
            if let parent = links[item.id] { grouped[parent, default: []].append(item.id) }
        }
        children = grouped
    }

    func rows(expanded: Set<UUID>? = nil) -> [Row] {
        var result = [Row]()
        var stack = roots.reversed().map { (id: $0, depth: 0) }
        while let (id, depth) = stack.popLast() {
            guard let item = items[id] else { continue }
            result.append(Row(item: item, depth: depth))
            if expanded?.contains(id) != false, let branch = children[id] {
                stack.append(contentsOf: branch.reversed().map { ($0, depth + 1) })
            }
        }
        return result
    }

    func ancestors(of id: UUID) -> [UUID] {
        var result = [UUID]()
        var next = parents[id]
        while let id = next {
            result.append(id)
            next = parents[id]
        }
        return result.reversed()
    }

    func path(to id: UUID) -> String {
        (ancestors(of: id) + [id]).compactMap { items[$0]?.title }.joined(separator: " › ")
    }
}
