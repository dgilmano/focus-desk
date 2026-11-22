#if DEBUG
import FocusDeskCore
import SwiftUI

/// Keep the buttons in task order in both layouts. Only their positions change.
struct DeskTaskMapLayout {
    struct Item: Identifiable {
        let id: UUID
        let title: String
        let tag: String?
        let palette: TaskTagPalette
    }

    struct Group: Identifiable {
        let tag: String?
        static func projectID(_ name: String) -> String { "tag:" + DeskProject.key(for: name) }
        static func id(for tag: String?) -> String { tag.map(projectID) ?? "untagged" }
        var id: String { Self.id(for: tag) }
        var name: String { tag ?? "Untagged" }
        var radius: CGFloat { min(106, width * 0.43) }
        let palette: TaskTagPalette
        var center: CGPoint
        var hubBounds: CGRect { CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8) }
        var label: CGPoint
        // Saved group positions in earlier versions used the original label location.
        let labelToHub: CGFloat
        var placementAnchor: CGPoint { CGPoint(x: center.x, y: center.y - labelToHub) }
        let labelWidth: CGFloat
        let width: CGFloat
        let indices: [Int]

        func includes(_ task: FocusTask) -> Bool {
            if task.projectName != nil {
                return task.deskProjectTag.map { DeskProject.key(for: $0.name) } == tag.map(DeskProject.key)
            }
            let tags = task.enabledTagRecords.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard let tag else { return tags.isEmpty }
            return tags.contains { $0.lowercased() == tag.lowercased() }
        }
    }

    struct Node {
        static let disclosureWidth: CGFloat = 22

        var center: CGPoint
        let maxWidth: CGFloat
        let titleWidth: CGFloat
        var chipWidth: CGFloat { min(maxWidth, titleWidth + Self.disclosureWidth) }
    }

    var groups: [Group]
    var nodes: [Node]
    let mapHeight: CGFloat

    init(items: [Item], width: CGFloat, projects: [String] = [], groupOrder: [String] = []) {
        // Tag IDs belong to individual tasks. Group by normalized name, as the sidebar does.
        var clusters = Dictionary(grouping: items.indices) { Group.id(for: items[$0].tag) }
            .values.sorted { $0[0] < $1[0] }
            .map { (name: items[$0[0]].tag, indices: $0) }
        var projectIDs = Set(clusters.map { Group.id(for: $0.name) })
        for project in projects where projectIDs.insert(Group.projectID(project)).inserted {
            clusters.append((name: project, indices: []))
        }
        // Keep a drop target in its column when moving the first or last member of a cloud.
        let rank = Dictionary(groupOrder.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: min)
        clusters.sort { (rank[Group.id(for: $0.name)] ?? .max) < (rank[Group.id(for: $1.name)] ?? .max) }
        var groups: [Group] = []
        var nodes = Array(repeating: Node(center: .zero, maxWidth: 0, titleWidth: 0), count: items.count)
        var top: CGFloat = 0
        var start = 0
        while start < clusters.count {
            // Two clusters above and one centered below, as in the prototype.
            let paired = width >= 380 && start % 3 != 2 && start + 1 < clusters.count
            let count = paired ? 2 : 1
            let columnWidth = width / CGFloat(count)
            let row = clusters[start ..< start + count]
            let tallest = max(1, row.map(\.indices.count).max() ?? 1)
            let height = CGFloat(tallest) * 47 + 39 + (paired ? 20 : 0)
            for (column, cluster) in row.enumerated() {
                let members = cluster.indices
                let cx = columnWidth * (CGFloat(column) + 0.5)
                let stagger: CGFloat = column == 1 ? 20 : 0
                let base = top + 16 + stagger
                let direction: CGFloat = paired && column == 0 ? -1 : 1
                let spread = min(columnWidth * 0.14, 76)
                let palette = members.first.map { items[$0].palette } ?? .blue
                let name = cluster.name ?? "Untagged"
                // Keep the junction in the gap between rows (or between a lone task and its label).
                let hubY = members.count <= 1 ? base + 18 : base + 36 + (CGFloat(members.count / 2) - 0.5) * 47
                groups.append(Group(tag: cluster.name, palette: palette,
                                    center: CGPoint(x: cx, y: hubY),
                                    label: CGPoint(x: cx, y: base), labelToHub: hubY - base,
                                    labelWidth: Self.labelWidth(name, padding: 14, limit: min(columnWidth - 10, 164)), width: columnWidth, indices: members))
                for (index, item) in members.enumerated() {
                    // Mirror the first pair so the two upper groups are staggered.
                    let slot = paired && column == 0 && members.count >= 2 && index < 2 ? 1 - index : index
                    let side: CGFloat = index.isMultiple(of: 2) ? -1 : 1
                    let dx = members.count == 1 ? 0 : side * spread * direction
                    let limit = max(1, min(188, columnWidth - abs(dx) * 2 - 10))
                    nodes[item] = Node(center: CGPoint(x: cx + dx, y: base + 36 + CGFloat(slot) * 47),
                                       maxWidth: limit, titleWidth: Self.labelWidth(items[item].title, padding: 24, limit: limit))
                }
            }
            top += height
            start += count
        }
        self.groups = groups
        self.nodes = nodes
        mapHeight = max(220, top + 10)
    }

    func dropTarget(for drag: DeskMapDrag, items: [Item]) -> Group? {
        guard case .task(let id) = drag.target, let point = drag.location,
              let item = items.first(where: { $0.id == id }) else { return nil }
        let label = groups.last { abs(point.y - $0.label.y) <= 11 && abs(point.x - $0.label.x) <= $0.labelWidth / 2 }
        let hit = label ?? groups.reversed().compactMap { group -> (Group, CGFloat)? in
            let distance = hypot(point.x - group.center.x, point.y - group.center.y)
            return distance <= group.radius ? (group, distance) : nil
        }.min { $0.1 < $1.1 }?.0
        return hit?.id == Group.id(for: item.tag) ? nil : hit
    }

    private static func labelWidth(_ title: String, padding: CGFloat, limit: CGFloat) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11)]
        return max(1, min(limit, ceil((title as NSString).size(withAttributes: attributes).width) + padding))
    }
}

struct DeskTaskMap: View {
    var tasks: [FocusTask]
    var projects: [String]
    var selectedID: UUID
    var width: CGFloat
    var onTaskRenamed: () -> Void
    var onSelect: (UUID) -> Void

    @AppStorage("openDeskShowsList") private var showsList = false
    @AppStorage(ActivityPreview.isActive ? "previewDeskMapArrangement" : "deskMapArrangement")
    private var storedArrangement = Data()
    @State private var arrangement = DeskMapArrangement()
    @State private var selectedGroupID: String?
    @State private var editingName: DeskMapName?
    @State private var moveError: String?
    @Environment(TaskStore.self) private var taskStore
    @FocusState private var mapFocused: Bool
    @GestureState private var drag: DeskMapDrag?
    @Namespace private var mapSpace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    private let rowHeight: CGFloat = 39
    private var selectedFill: Color { scheme == .dark ? .white : Color(white: 0.16) }

    var body: some View {
        let byID = Dictionary(uniqueKeysWithValues: tasks.enumerated().map { ($0.element.id, $0.offset) })
        let items = tasks.map { task in
            let tag = task.deskProjectTag
            return DeskTaskMapLayout.Item(id: task.id, title: task.title,
                                          tag: tag?.name.trimmingCharacters(in: .whitespacesAndNewlines),
                                          palette: .palette(for: tag?.colorName ?? "gray"))
        }
        let automatic = DeskTaskMapLayout(items: items, width: width, projects: projects, groupOrder: arrangement.groupOrder)
        let placed = automatic.placing(arrangement, items: items, width: width)
        let layout = drag.map { placed.moving($0, items: items, width: width) } ?? placed
        let destinationID = drag.flatMap { placed.dropTarget(for: $0, items: items)?.id }
        let height = showsList ? max(105, CGFloat(items.count) * rowHeight) : layout.mapHeight

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(showsList ? "Task list" : "Task map")
                    .font(.system(size: 13, weight: .semibold)).accessibilityAddTraits(.isHeader)
                Spacer()
                if !showsList && !arrangement.isEmpty {
                    Button {
                        save(DeskMapArrangement())
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.plain)
                    .help("Reset map layout")
                    .accessibilityLabel("Reset map layout")
                }
                HStack(spacing: 2) {
                    modeButton("Map", list: false)
                    modeButton("List", list: true)
                }
                .padding(2)
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(FocusDeskStyle.hairline) }
            }
            ZStack(alignment: .topLeading) {
                if !showsList {
                    backdrop(layout: layout, byID: byID, destinationID: destinationID)
                        .frame(width: width, height: layout.mapHeight)
                        .transition(.opacity)
                    ForEach(layout.groups) { group in
                        Button { selectGroup(group) } label: {
                            Ellipse().fill(.clear)
                                .frame(width: group.radius * 2, height: group.radius * 2)
                                .contentShape(Ellipse())
                        }
                        .buttonStyle(.plain)
                        .highPriorityGesture(dragGesture(.group(group.id), placed: placed, items: items))
                        .contextMenu { projectMenu(group) }
                        .position(group.center).accessibilityHidden(true)
                        let selected = selectedGroupID == group.id || destinationID == group.id
                        Button { selectGroup(group) } label: {
                            Text(group.name).font(.system(size: 11, weight: selected ? .semibold : .regular))
                                .foregroundStyle(selected ? group.palette.foreground : Color.secondary)
                                .lineLimit(1).frame(width: group.labelWidth, height: 22)
                                .background { if selected { Capsule().fill(group.palette.background.opacity(0.7)) } }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .highPriorityGesture(dragGesture(.label(group.id), placed: placed, items: items))
                        .simultaneousGesture(TapGesture(count: 2).onEnded { editingName = .project(group.tag) })
                        .contextMenu { projectMenu(group) }
                        .accessibilityAction(named: "Rename project") { editingName = .project(group.tag) }
                        .help("Double-click to rename. Drag the name within the cloud, or drag the cloud to move the project.")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .position(group.label)
                        .zIndex(4)
                    }
                }
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let node = layout.nodes[index]
                    let cy = (CGFloat(index) + 0.5) * rowHeight
                    let disclosureWidth = min(node.chipWidth, DeskTaskMapLayout.Node.disclosureWidth)
                    if showsList {
                        HStack {
                            Spacer()
                            let parent = tasks[index].parentTaskID.flatMap { byID[$0] }.map { tasks[$0].title }
                            Text([item.tag ?? "Untagged", parent].compactMap { $0 }.joined(separator: " › ")).font(.system(size: 11)).foregroundStyle(.secondary)
                                .lineLimit(1).frame(maxWidth: width * 0.40, alignment: .trailing)
                        }
                        .padding(.trailing, 10).frame(width: width, height: rowHeight)
                        .overlay(alignment: .bottom) { Divider() }
                        .position(x: width / 2, y: cy)
                        .allowsHitTesting(false).accessibilityHidden(true)
                    }
                    DeskMapTaskChip(task: tasks[index], disclosureWidth: showsList ? nil : disclosureWidth) {
                        taskButton(item, width: showsList ? node.titleWidth : node.chipWidth - disclosureWidth)
                            .highPriorityGesture(dragGesture(.task(item.id), placed: placed, items: items),
                                                 including: showsList ? .subviews : .all)
                            .simultaneousGesture(TapGesture(count: 2).onEnded { editingName = .task(item.id, item.title) })
                            .accessibilityAction(named: "Rename task") { editingName = .task(item.id, item.title) }
                    }
                    .contextMenu {
                        Button("Edit") { editingName = .task(item.id, item.title) }
                    }
                    .zIndex(drag?.target == .task(item.id) ? 3 : 2)
                    .position(x: showsList ? 8 + node.titleWidth / 2 : node.center.x,
                              y: showsList ? cy : node.center.y)
                }
            }
            .frame(width: width, height: height, alignment: .topLeading)
            .coordinateSpace(name: mapSpace)
            .clipped()
            HStack {
                if showsList { Text("Task / Project") }
                Spacer()
                Text("\(tasks.count) \(tasks.count == 1 ? "task" : "tasks")")
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .background {
            Color.clear.contentShape(Rectangle()).onTapGesture { mapFocused = true }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($mapFocused)
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
            guard editingName == nil, tasks.count > 1,
                  press.modifiers.intersection([.command, .control, .option, .shift]).isEmpty else {
                return .ignored
            }
            let router = DeskRouter()
            let snapshots = tasks.map(\.snapshot)
            let neighbor = press.key == .leftArrow
                ? router.previousTask(in: snapshots, before: selectedID)
                : router.nextTask(in: snapshots, after: selectedID)
            guard let neighbor else { return .ignored }
            selectTask(neighbor.id)
            return .handled
        }
        .onAppear { mapFocused = true }
        .sheet(item: $editingName, onDismiss: { mapFocused = true }) { target in
            DeskMapNameEditor(target: target) { name in
                switch target {
                case .task(let id, let original):
                    try taskStore.renameTask(id: id, from: original, to: name)
                    onTaskRenamed()
                case .project(let original):
                    try taskStore.renameProject(from: original, to: name)
                    let oldID = DeskTaskMapLayout.Group.id(for: original)
                    let newID = DeskTaskMapLayout.Group.projectID(name)
                    var next = arrangement
                    next.renameGroup(from: oldID, to: newID)
                    save(next)
                    if selectedGroupID == oldID { selectedGroupID = newID }
                }
            }
        }
        .alert("Could not move task", isPresented: Binding(get: { moveError != nil }, set: { if !$0 { moveError = nil } })) {
            Button("OK") { moveError = nil }
        } message: { Text(moveError ?? "") }
        .onChange(of: storedArrangement, initial: true) {
            arrangement = (try? JSONDecoder().decode(DeskMapArrangement.self, from: storedArrangement)) ?? DeskMapArrangement()
        }
        .onChange(of: automatic.groups.map(\.id)) { _, ids in
            if let selectedGroupID, !ids.contains(selectedGroupID) { self.selectedGroupID = nil }
        }
    }

    private func projectMenu(_ group: DeskTaskMapLayout.Group) -> some View {
        Button("Edit") { editingName = .project(group.tag) }
    }

    private func selectGroup(_ group: DeskTaskMapLayout.Group) {
        selectedGroupID = group.id
        if !group.indices.isEmpty, let firstTask = tasks.first(where: group.includes) {
            selectTask(firstTask.id)
        }
    }

    private func selectTask(_ id: UUID) {
        onSelect(id)
        mapFocused = true
    }

    private func dragGesture(_ target: DeskMapDrag.Target, placed: DeskTaskMapLayout,
                             items: [DeskTaskMapLayout.Item]) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(mapSpace))
            .updating($drag) { value, state, transaction in
                transaction.animation = nil
                state = DeskMapDrag(target: target, translation: value.translation, location: value.location)
            }
            .onEnded { value in
                let finished = DeskMapDrag(target: target, translation: value.translation, location: value.location)
                var next = arrangement
                if case .task(let id) = target, let destination = placed.dropTarget(for: finished, items: items),
                   let item = items.first(where: { $0.id == id }) {
                    do {
                        let movedIDs = try taskStore.moveMapTask(id: id, from: item.tag, to: destination.tag)
                        for moved in movedIDs { next.tasks.removeValue(forKey: moved) }
                        next.groupOrder = placed.groups.map(\.id)
                        selectedGroupID = destination.id
                    } catch { moveError = error.localizedDescription; return }
                } else {
                    let moved = placed.moving(finished, items: items, width: width)
                    next.remember(target, in: moved, items: items, width: width)
                }
                save(next)
            }
    }

    private func save(_ next: DeskMapArrangement) {
        guard let data = try? JSONEncoder().encode(next) else { return }
        arrangement = next
        storedArrangement = data
    }

    private func modeButton(_ title: String, list: Bool) -> some View {
        Button {
            mapFocused = true
            withAnimation(reduceMotion ? nil : .timingCurve(0.23, 0.78, 0.18, 1, duration: 0.54)) {
                showsList = list
            }
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(showsList == list ? FocusDeskStyle.groupedBackground : Color.primary)
                .padding(.horizontal, 9).frame(height: 20)
                .background { if showsList == list { RoundedRectangle(cornerRadius: 4).fill(selectedFill) } }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(showsList == list ? .isSelected : [])
    }

    private func taskButton(_ item: DeskTaskMapLayout.Item, width: CGFloat) -> some View {
        let selected = item.id == selectedID
        let shape = RoundedRectangle(cornerRadius: showsList ? 4 : 12)
        return Button { selectTask(item.id) } label: {
            HStack(spacing: 5) {
                Circle().fill(selected ? item.palette.background : item.palette.foreground).frame(width: 6, height: 6)
                Text(item.title).font(.system(size: 11)).lineLimit(1)
            }
            .padding(.horizontal, 6)
            .frame(width: width, height: 22)
            .foregroundStyle(selected ? FocusDeskStyle.groupedBackground : Color.primary)
            .background(shape.fill(selected ? selectedFill : FocusDeskStyle.groupedBackground))
            .overlay { if !selected { shape.strokeBorder(item.palette.foreground.opacity(0.25)) } }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help("\(item.title) — Double-click to rename")
        .accessibilityLabel(item.title)
        .accessibilityValue(item.tag ?? "Untagged")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func backdrop(layout: DeskTaskMapLayout, byID: [UUID: Int], destinationID: String?) -> some View {
        Canvas { context, _ in
            for group in layout.groups {
                let color = group.palette.foreground
                let radius = group.radius
                let halo = CGRect(x: group.center.x - radius, y: group.center.y - radius,
                                  width: radius * 2, height: radius * 2)
                if destinationID == group.id {
                    context.stroke(Path(ellipseIn: halo), with: .color(Color.accentColor.opacity(0.8)), lineWidth: 1.5)
                }
                context.fill(Path(ellipseIn: halo), with: .radialGradient(Gradient(colors: [color.opacity(0.15), .clear]),
                                                                         center: group.center, startRadius: 0, endRadius: radius))
                for index in group.indices {
                    let node = layout.nodes[index].center
                    var link = Path()
                    let origin = tasks[index].parentTaskID.flatMap { byID[$0] }.map { layout.nodes[$0].center } ?? group.center
                    link.move(to: origin)
                    let bend = min(9, abs(origin.x - node.x) / 4)
                    link.addQuadCurve(to: node, control: CGPoint(x: (origin.x + node.x) / 2, y: origin.y - bend))
                    context.stroke(link, with: .color(color.opacity(0.55)), lineWidth: 1)
                }
                let hub = Path(ellipseIn: group.hubBounds)
                context.fill(hub, with: .color(color))
                context.stroke(hub, with: .color(FocusDeskStyle.groupedBackground), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

}

private enum DeskMapName: Identifiable, Hashable {
    case project(String?)
    case task(UUID, String)

    var id: Self { self }
    var name: String {
        switch self {
        case .project(let name): return name ?? "Untagged"
        case .task(_, let name): return name
        }
    }
    var field: String {
        switch self {
        case .project: return "Project name"
        case .task: return "Task name"
        }
    }
}

private struct DeskMapNameEditor: View {
    let target: DeskMapName
    let save: (String) throws -> Void
    @State private var name: String
    @State private var errorMessage: String?
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    init(target: DeskMapName, save: @escaping (String) throws -> Void) {
        self.target = target
        self.save = save
        _name = State(initialValue: target.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(target.field).font(.headline)
            TextField(target.field, text: $name).textFieldStyle(.roundedBorder).focused($focused)
            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    do {
                        try save(name)
                        dismiss()
                    } catch { errorMessage = error.localizedDescription }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18).frame(width: 340).onAppear { focused = true }
    }
}

private struct DeskMapTaskChip<Title: View>: View {
    let task: FocusTask
    let disclosureWidth: CGFloat?
    @ViewBuilder let title: () -> Title
    @State private var isHovered = false
    @State private var isExpanded = false
    @FocusState private var disclosureFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            title()
                .onHover { inside in
                    if inside && disclosureWidth != nil { isHovered = true }
                }
            if let disclosureWidth {
                nextStepButton(width: disclosureWidth)
            }
        }
        .contentShape(Rectangle())
        .onHover { inside in
            if !inside { isHovered = false }
        }
    }

    private func nextStepButton(width: CGFloat) -> some View {
        let isVisible = isHovered || isExpanded || disclosureFocused
        return Button { isExpanded.toggle() } label: {
            Image(systemName: isExpanded ? "minus.circle" : "plus.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isExpanded ? FocusDeskStyle.deskAccent : .secondary)
                .opacity(isVisible ? 1 : 0)
                .frame(width: width, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($disclosureFocused)
        .allowsHitTesting(isVisible)
        .accessibilityLabel("Next step for \(task.title)")
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .help("Show next step for \(task.title)")
        .popover(isPresented: $isExpanded) {
            let steps = (task.nextStep ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            VStack(alignment: .leading, spacing: 8) {
                Text(task.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                Text("Next step")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                if steps.isEmpty {
                    Text("No next step yet.")
                        .font(FocusDeskStyle.workspaceBodyFont)
                        .foregroundStyle(.secondary)
                } else {
                    let content = MarkdownText(steps, font: FocusDeskStyle.workspaceBodyFont,
                                               emphasisColor: FocusDeskStyle.deskAccent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    ViewThatFits(in: .vertical) {
                        content
                        ScrollView { content }.frame(height: 220)
                    }
                    .frame(maxHeight: 220, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(width: 280, alignment: .leading)
        }
    }
}
#endif
