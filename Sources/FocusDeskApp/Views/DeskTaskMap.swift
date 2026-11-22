#if DEBUG || FOCUS_DESK_PERSONAL
import FocusDeskCore
import SwiftUI

/// Keep the buttons in task order in both layouts. Only their positions change.
struct DeskTaskMapLayout {
    struct Item: Identifiable {
        let id: UUID
        let title: String
        let tag: String?
        let palette: TaskTagPalette
        var hasChildren = false
        var isSubtask = false
        var steps: [NextStepChecklist.Item] = []
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
            func slotHeight(_ i: Int) -> CGFloat {
                47 + DeskMapSteps.reservedHeight(count: items[i].steps.count, width: columnWidth)
            }
            let tallest = row.map { $0.indices.map(slotHeight).reduce(0, +) }.max() ?? 0
            let height = max(47, tallest) + 39 + (paired ? 20 : 0)
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
                let hubY = members.count <= 1 || members.contains(where: { !items[$0].steps.isEmpty }) ? base + 18 : base + 36 + (CGFloat(members.count / 2) - 0.5) * 47
                groups.append(Group(tag: cluster.name, palette: palette,
                                    center: CGPoint(x: cx, y: hubY),
                                    label: CGPoint(x: cx, y: base), labelToHub: hubY - base,
                                    labelWidth: Self.labelWidth(name, padding: 14, limit: min(columnWidth - 10, 164)), width: columnWidth, indices: members))
                var slots = members
                if paired && column == 0 && slots.count >= 2 && !slots.contains(where: { items[$0].isSubtask }) {
                    slots.swapAt(0, 1)
                }
                var y = base + 36
                var slotY: [Int: CGFloat] = [:]
                for i in slots {
                    slotY[i] = y
                    y += slotHeight(i)
                }
                for (index, item) in members.enumerated() {
                    let side: CGFloat = index.isMultiple(of: 2) ? -1 : 1
                    let dx = members.count == 1 ? 0 : side * spread * direction
                    let limit = max(1, min(188, columnWidth - abs(dx) * 2 - 10))
                    nodes[item] = Node(center: CGPoint(x: cx + dx, y: slotY[item] ?? base + 36),
                                       maxWidth: limit, titleWidth: Self.labelWidth(items[item].title, padding: items[item].hasChildren ? 36 : 24, limit: limit))
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
    var selectedID: UUID?
    var width: CGFloat
    var onTasksChanged: () -> Void
    var onDeleteTask: (UUID, String) -> Void
    var onDeleteProject: (String) -> Void
    var onSelect: (UUID) -> Void

    @AppStorage("openDeskShowsList") private var showsList = false
    @AppStorage(ActivityPreview.isActive ? "previewDeskMapArrangement" : "deskMapArrangement")
    private var storedArrangement = Data()
    @State private var arrangement = DeskMapArrangement()
    @State private var selectedGroupID: String?
    @State private var expandedTasks = Set<UUID>()
    @State private var clicks = DeskMapClicks()
    @State private var editingName: DeskMapRename?
    @State private var nameText = ""
    @State private var nameError: String?
    @State private var addingUnder: FocusTask?
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
        let outline = TaskOutline(tasks.map(TaskOutline.Item.init))
        let byID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        let rows = outline.rows(expanded: showsList ? nil : expandedTasks)
        let displayed = rows.compactMap { byID[$0.id] }
        let items = displayed.map { task in
            let tag = task.deskProjectTag
            let steps = NextStepChecklist(task.nextStep ?? "").items
            return DeskTaskMapLayout.Item(id: task.id, title: task.title,
                                          tag: tag?.name.trimmingCharacters(in: .whitespacesAndNewlines),
                                          palette: .palette(for: tag?.colorName ?? "gray"),
                                          hasChildren: outline.children[task.id] != nil || !steps.isEmpty,
                                          isSubtask: task.parentTaskID != nil,
                                          steps: !showsList && expandedTasks.contains(task.id) ? steps : [])
        }
        let automatic = DeskTaskMapLayout(items: items, width: width, projects: projects, groupOrder: arrangement.groupOrder)
        let placed = automatic.placing(arrangement, items: items, width: width)
        let layout = drag.map { placed.moving($0, items: items, width: width) } ?? placed
        let destinationID = drag.flatMap { placed.dropTarget(for: $0, items: items)?.id }
        let restingBranches = DeskMapSteps(layout: layout, items: items, width: width, offsets: arrangement.stepOffsets)
        let branches = restingBranches.moving(drag, width: width)
        let onDrop = { (finished: DeskMapDrag) in
            commitDrag(finished, placed: placed, branches: restingBranches, items: items)
        }
        let height = showsList ? max(105, CGFloat(items.count) * rowHeight) : branches.height

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
                    backdrop(layout: layout, rows: rows, branches: branches, destinationID: destinationID)
                        .frame(width: width, height: branches.height)
                        .transition(.opacity)
                    ForEach(layout.groups) { group in
                        Button { selectGroup(group, in: displayed) } label: {
                            Ellipse().fill(.clear)
                                .frame(width: group.radius * 2, height: group.radius * 2)
                                .contentShape(Ellipse())
                        }
                        .buttonStyle(.plain)
                        .highPriorityGesture(dragGesture(.group(group.id), onDrop: onDrop) { time in
                            projectClick(group, in: displayed, time: time)
                        })
                        .contextMenu { projectMenu(group) }
                        .position(group.center).accessibilityHidden(true)
                        let selected = selectedGroupID == group.id || destinationID == group.id
                        Button { selectGroup(group, in: displayed) } label: {
                            Text(group.name).font(.system(size: 11, weight: selected ? .semibold : .regular))
                                .foregroundStyle(selected ? group.palette.foreground : Color.secondary)
                                .lineLimit(1).frame(width: group.labelWidth, height: 22)
                                .background { if selected { Capsule().fill(group.palette.background.opacity(0.7)) } }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .highPriorityGesture(dragGesture(.label(group.id), onDrop: onDrop) { time in
                            projectClick(group, in: displayed, time: time)
                        })
                        .contextMenu { projectMenu(group) }
                        .accessibilityAction(named: "Rename project") { beginRename(.project(group.tag), title: group.name) }
                        .help("Click twice with a pause to rename. Drag the name within the cloud, or drag the cloud to move the project.")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .position(group.label)
                        .zIndex(4)
                    }
                }
                ForEach(branches.leaves) { leaf in
                    stepButton(leaf, source: byID[leaf.id.task]?.nextStep ?? "", onDrop: onDrop)
                        .position(x: leaf.frame.midX, y: leaf.frame.midY)
                        .zIndex(drag?.target == .step(leaf.key) ? 6 : 2)
                }
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let node = layout.nodes[index]
                    let cy = (CGFloat(index) + 0.5) * rowHeight
                    let disclosureWidth = min(node.chipWidth, DeskTaskMapLayout.Node.disclosureWidth)
                    if showsList {
                        HStack {
                            Spacer()
                            let parent = displayed[index].parentTaskID.flatMap { byID[$0]?.title }
                            Text([item.tag ?? "Untagged", parent].compactMap { $0 }.joined(separator: " › ")).font(.system(size: 11)).foregroundStyle(.secondary)
                                .lineLimit(1).frame(maxWidth: width * 0.40, alignment: .trailing)
                        }
                        .padding(.trailing, 10).frame(width: width, height: rowHeight)
                        .overlay(alignment: .bottom) { Divider() }
                        .position(x: width / 2, y: cy)
                        .allowsHitTesting(false).accessibilityHidden(true)
                    }
                    DeskMapTaskChip(title: item.title, disclosureWidth: showsList ? nil : disclosureWidth,
                                    canExpand: item.hasChildren, isExpanded: expandedTasks.contains(item.id),
                                    toggle: { toggleBranch(item.id) }) {
                        taskButton(item, width: showsList ? node.titleWidth : node.chipWidth - disclosureWidth)
                            .highPriorityGesture(dragGesture(.task(item.id), onDrop: onDrop) { time in
                                taskClick(item, time: time)
                            })
                            .accessibilityAction(named: "Add subtask") { addingUnder = displayed[index] }
                            .accessibilityAction(named: "Rename task") { beginRename(.task(item.id), title: item.title) }
                    }
                    .contextMenu {
                        Button("Add subtask…", systemImage: "plus") { addingUnder = displayed[index] }
                        if item.hasChildren && !showsList {
                            Button(expandedTasks.contains(item.id) ? "Collapse branch" : "Expand branch") { toggleBranch(item.id) }
                        }
                        Button("Rename…") { beginRename(.task(item.id), title: item.title) }
                        Divider()
                        Button("Delete…", systemImage: "trash", role: .destructive) { onDeleteTask(item.id, item.title) }
                    }
                    .zIndex(drag?.target == .task(item.id) ? 3 : 2)
                    .position(x: showsList ? 8 + min(4, CGFloat(rows[index].depth)) * 12 + node.titleWidth / 2 : node.center.x,
                              y: showsList ? cy : node.center.y)
                }
                if let editingName {
                    Color.clear.contentShape(Rectangle()).onTapGesture { _ = finishRename() }.zIndex(8)
                    let point = editorAnchor(editingName.object, layout: layout, branches: branches, rows: rows)
                    let fieldWidth = min(width, max(148, min(300, width * 0.55)))
                    nameEditor(editingName)
                        .frame(width: fieldWidth)
                        .position(x: min(max(fieldWidth / 2, point.x), width - fieldWidth / 2),
                                  y: min(max(15, point.y), height - 15))
                        .zIndex(9)
                }
            }
            .frame(width: width, height: height, alignment: .topLeading)
            .coordinateSpace(name: mapSpace)
            .clipped()
            if let nameError {
                Text(nameError).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
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
            guard editingName == nil, displayed.count > 1,
                  press.modifiers.intersection([.command, .control, .option, .shift]).isEmpty else {
                return .ignored
            }
            let router = DeskRouter()
            let snapshots = displayed.map(\.snapshot)
            let neighbor = press.key == .leftArrow
                ? router.previousTask(in: snapshots, before: selectedID)
                : router.nextTask(in: snapshots, after: selectedID)
            guard let neighbor else { return .ignored }
            selectTask(neighbor.id)
            return .handled
        }
        .onAppear { mapFocused = true }
        .onChange(of: selectedID) { _, id in
            if !showsList, let id { expandedTasks.formUnion(outline.ancestors(of: id)) }
            if clicks.ownerTask != id && selectedGroupID == nil { clicks = DeskMapClicks() }
        }
        .onChange(of: showsList) {
            if !showsList, let selectedID { expandedTasks.formUnion(outline.ancestors(of: selectedID)) }
        }
        .sheet(item: $addingUnder, onDismiss: { mapFocused = true }) { parent in
            DeskMapSubtaskEditor { name in
                let child = try taskStore.createSubtask(named: name, under: parent.id)
                expandedTasks.formUnion(outline.ancestors(of: parent.id))
                expandedTasks.insert(parent.id)
                selectTask(child.id)
                onTasksChanged()
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

    private func stepButton(_ leaf: DeskMapSteps.Leaf, source: String, onDrop: @escaping (DeskMapDrag) -> Void) -> some View {
        let object = DeskMapObject.step(leaf.id)
        let rename = { beginRename(object, title: leaf.step.text, stepSource: source) }
        return Button { selectTask(leaf.id.task) } label: {
            HStack(spacing: 5) {
                Image(systemName: leaf.step.isCompleted ? "checkmark.circle" : "circle")
                    .font(.system(size: 9)).foregroundStyle(leaf.palette.foreground)
                MarkdownText(leaf.step.text, font: .system(size: 10), lineLimit: 2)
                    .strikethrough(leaf.step.isCompleted)
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, 8)
            .frame(width: leaf.frame.width, height: leaf.frame.height, alignment: .leading)
            .background(FocusDeskStyle.groupedBackground, in: RoundedRectangle(cornerRadius: 9))
            .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(leaf.palette.foreground.opacity(0.23)) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .highPriorityGesture(dragGesture(.step(leaf.key), onDrop: onDrop) { time in
            selectedGroupID = nil
            selectTask(leaf.id.task)
            if click(object, time: time) == .rename { rename() }
        })
        .accessibilityLabel("Next step: \(leaf.step.text)")
        .accessibilityAction(named: "Rename step", rename)
        .contextMenu { Button("Rename…", action: rename) }
        .help(leaf.step.text + "\nDrag to move. Click twice with a pause to rename.")
    }

    private func beginRename(_ object: DeskMapObject, title: String, stepSource: String? = nil) {
        clicks = DeskMapClicks()
        nameError = nil
        mapFocused = false
        nameText = title
        editingName = DeskMapRename(object: object, original: title, stepSource: stepSource)
    }

    private func editorAnchor(_ object: DeskMapObject, layout: DeskTaskMapLayout, branches: DeskMapSteps,
                              rows: [TaskOutline.Row]) -> CGPoint {
        switch object {
        case .project(let tag):
            if let group = layout.groups.first(where: { $0.id == DeskTaskMapLayout.Group.id(for: tag) }) { return group.label }
        case .task(let id):
            if let index = rows.firstIndex(where: { $0.id == id }) {
                if showsList {
                    return CGPoint(x: 8 + min(4, CGFloat(rows[index].depth)) * 12 + layout.nodes[index].titleWidth / 2,
                                   y: (CGFloat(index) + 0.5) * rowHeight)
                }
                return layout.nodes[index].center
            }
        case .step(let id):
            if let frame = branches.leaves.first(where: { $0.id == id })?.frame {
                return CGPoint(x: frame.midX, y: frame.midY)
            }
        }
        return CGPoint(x: width / 2, y: 15)
    }

    private func nameEditor(_ target: DeskMapRename) -> some View {
        HStack(spacing: 4) {
            DeskMapNameField(label: target.field, text: $nameText, submit: { _ = finishRename() }, cancel: endRename)
                .frame(height: 19)
            Button { _ = finishRename() } label: { Image(systemName: "checkmark") }
                .accessibilityLabel("Save name")
            Button(action: endRename) { Image(systemName: "xmark") }
                .accessibilityLabel("Cancel rename")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8).frame(height: 26)
        .background(FocusDeskStyle.groupedBackground, in: RoundedRectangle(cornerRadius: 7))
        .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Color.accentColor).allowsHitTesting(false) }
        .onExitCommand(perform: endRename)
    }

    private func endRename() {
        editingName = nil
        nameError = nil
        mapFocused = true
    }

    @discardableResult private func finishRename() -> Bool {
        guard let edit = editingName else { return true }
        let name = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if name != edit.original {
                switch edit.object {
                case .task(let id):
                    try taskStore.renameTask(id: id, from: edit.original, to: name)
                case .step(let id):
                    guard let source = edit.stepSource else { return false }
                    try taskStore.renameNextStep(id.index, in: id.task, from: source, to: name)
                    var next = arrangement
                    next.renameStep(at: id.index, in: id.task, labels: NextStepChecklist(source).items.map(\.text), to: name)
                    if next != arrangement { save(next) }
                case .project(let original):
                    try taskStore.renameProject(from: original, to: name)
                    let oldID = DeskTaskMapLayout.Group.id(for: original)
                    let newID = DeskTaskMapLayout.Group.projectID(name)
                    var next = arrangement
                    next.renameGroup(from: oldID, to: newID)
                    save(next)
                    if selectedGroupID == oldID { selectedGroupID = newID }
                }
                onTasksChanged()
            }
            endRename()
            return true
        } catch {
            nameError = error.localizedDescription
            return false
        }
    }

    @ViewBuilder private func projectMenu(_ group: DeskTaskMapLayout.Group) -> some View {
        Button("Rename…") { beginRename(.project(group.tag), title: group.name) }
        if let name = group.tag {
            Divider()
            Button("Delete…", systemImage: "trash", role: .destructive) { onDeleteProject(name) }
        }
    }

    private func projectClick(_ group: DeskTaskMapLayout.Group, in displayed: [FocusTask], time: TimeInterval) {
        selectGroup(group, in: displayed)
        if click(.project(group.tag), time: time) == .rename {
            beginRename(.project(group.tag), title: group.name)
        }
    }

    private func selectGroup(_ group: DeskTaskMapLayout.Group, in displayed: [FocusTask]) {
        selectedGroupID = group.id
        if !group.indices.isEmpty, let firstTask = displayed.first(where: group.includes) {
            selectTask(firstTask.id)
        }
    }

    private func selectTask(_ id: UUID) {
        onSelect(id)
        mapFocused = true
    }

    private func dragGesture(_ target: DeskMapDrag.Target, onDrop: @escaping (DeskMapDrag) -> Void,
                             onClick: @escaping (TimeInterval) -> Void) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(mapSpace))
            .updating($drag) { value, state, transaction in
                guard !showsList, state != nil || hypot(value.translation.width, value.translation.height) >= 4 else { return }
                transaction.animation = nil
                state = DeskMapDrag(target: target, translation: value.translation, location: value.location)
            }
            .onEnded { value in
                if hypot(value.translation.width, value.translation.height) < 4 && drag == nil {
                    onClick(value.time.timeIntervalSinceReferenceDate)
                    return
                }
                guard !showsList else { return }
                clicks = DeskMapClicks()
                onDrop(DeskMapDrag(target: target, translation: value.translation, location: value.location))
            }
    }

    private func commitDrag(_ finished: DeskMapDrag, placed: DeskTaskMapLayout, branches: DeskMapSteps,
                            items: [DeskTaskMapLayout.Item]) {
        let target = finished.target
        var next = arrangement
        if case .step(let key) = target {
            guard let leaf = branches.moving(finished, width: width).leaves.first(where: { $0.key == key }) else { return }
            next.stepOffsets[key] = leaf.offsetFromParent
            save(next)
            return
        }
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
            if case .group(let id) = target,
               let before = placed.groups.first(where: { $0.id == id }),
               let after = moved.groups.first(where: { $0.id == id }) {
                let visible = Set(before.indices.map { items[$0].id })
                let hidden = tasks.filter { !visible.contains($0.id) && DeskTaskMapLayout.Group.id(for: $0.deskProjectTag?.name) == id }
                for task in hidden {
                    guard let point = next.tasks[task.id] else { continue }
                    next.tasks[task.id] = CGPoint(x: point.x + (after.center.x - before.center.x) / width,
                                                 y: point.y + (after.center.y - before.center.y) / placed.mapHeight)
                }
            }
            next.remember(target, in: moved, items: items, width: width)
        }
        save(next)
    }

    private func save(_ next: DeskMapArrangement) {
        guard let data = try? JSONEncoder().encode(next) else { return }
        arrangement = next
        storedArrangement = data
    }

    private func modeButton(_ title: String, list: Bool) -> some View {
        Button {
            guard finishRename() else { return }
            mapFocused = true
            withAnimation(reduceMotion ? nil : .timingCurve(0.23, 0.78, 0.18, 1, duration: 0.54)) {
                clicks = DeskMapClicks()
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
                if item.hasChildren && !showsList {
                    Image(systemName: expandedTasks.contains(item.id) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold)).accessibilityHidden(true)
                }
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
        .help(showsList ? "Click twice with a pause to rename." : (item.hasChildren ? "Double-click to show or hide subtasks and next steps. " : "") + "Click twice with a pause to rename. Right-click to add a subtask.")
        .accessibilityLabel(item.title)
        .accessibilityValue([item.tag ?? "Untagged", item.hasChildren && !showsList ? (expandedTasks.contains(item.id) ? "Branch expanded" : "Branch collapsed") : nil]
            .compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func taskClick(_ item: DeskTaskMapLayout.Item, time: TimeInterval) {
        selectedGroupID = nil
        selectTask(item.id)
        switch click(.task(item.id), time: time) {
        case .doubleClick:
            if !showsList && item.hasChildren { toggleBranch(item.id) }
        case .rename: beginRename(.task(item.id), title: item.title)
        case .select: break
        }
    }

    private func click(_ object: DeskMapObject, time: TimeInterval) -> DeskMapClicks.Action {
        clicks.record(object, at: time, doubleClickInterval: NSEvent.doubleClickInterval)
    }

    private func toggleBranch(_ id: UUID) {
        if !expandedTasks.insert(id).inserted { expandedTasks.remove(id) }
        selectTask(id)
    }

    private func backdrop(layout: DeskTaskMapLayout, rows: [TaskOutline.Row], branches: DeskMapSteps, destinationID: String?) -> some View {
        let byID = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.element.id, $0.offset) })
        return Canvas { context, _ in
            for leaf in branches.leaves where leaf.isManuallyPlaced {
                let center = CGPoint(x: leaf.frame.midX, y: leaf.frame.midY)
                var link = Path()
                link.move(to: leaf.parent)
                link.addQuadCurve(to: center, control: CGPoint(x: (leaf.parent.x + center.x) / 2, y: leaf.parent.y))
                context.stroke(link, with: .color(leaf.palette.foreground.opacity(0.55)), lineWidth: 1)
            }
            let clustered = branches.leaves.filter { !$0.isManuallyPlaced }
            for leaves in Dictionary(grouping: clustered, by: { $0.id.task }).values {
                guard let first = leaves.first else { continue }
                let spine = first.junctionX
                var link = Path()
                link.move(to: first.parent)
                let junction = CGPoint(x: spine, y: first.parent.y + 17)
                link.addQuadCurve(to: junction, control: CGPoint(x: first.parent.x, y: junction.y))
                var bottom = junction.y
                for leaf in leaves {
                    let frame = leaf.frame
                    if spine >= frame.minX && spine <= frame.maxX {
                        bottom = max(bottom, frame.minY)
                    } else {
                        let y = frame.midY
                        bottom = max(bottom, y - 4)
                        link.move(to: CGPoint(x: spine, y: y - 4))
                        link.addQuadCurve(to: CGPoint(x: spine < frame.minX ? frame.minX : frame.maxX, y: y),
                                          control: CGPoint(x: spine, y: y))
                    }
                }
                link.move(to: junction)
                link.addLine(to: CGPoint(x: spine, y: bottom))
                context.stroke(link, with: .color(first.palette.foreground.opacity(0.55)), lineWidth: 1)
            }
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
                    let parent = rows[index].depth > 0 ? rows[index].item.parentID.flatMap { byID[$0] } : nil
                    let origin = parent.map { layout.nodes[$0].center } ?? group.center
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

enum DeskMapObject: Hashable {
    case project(String?)
    case task(UUID)
    case step(DeskMapSteps.ID)
}

struct DeskMapClicks {
    enum Action { case select, doubleClick, rename }
    private var previous: DeskMapObject?
    private var time: TimeInterval = 0

    var ownerTask: UUID? {
        switch previous {
        case .task(let id): return id
        case .step(let step): return step.task
        default: return nil
        }
    }

    mutating func record(_ object: DeskMapObject, at now: TimeInterval, doubleClickInterval: TimeInterval) -> Action {
        let elapsed = now - time
        if previous == object, elapsed >= 0, elapsed <= doubleClickInterval + 0.85 {
            previous = nil
            return elapsed <= doubleClickInterval ? .doubleClick : .rename
        }
        previous = object
        time = now
        return .select
    }
}

private struct DeskMapRename {
    let object: DeskMapObject
    let original: String
    let stepSource: String?
    var field: String {
        switch object {
        case .project: return "Project name"
        case .task: return "Task name"
        case .step: return "Step name"
        }
    }
}

private struct DeskMapSubtaskEditor: View {
    let save: (String) throws -> Void
    @State private var name = ""
    @State private var errorMessage: String?
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Subtask name").font(.headline)
            TextField("Subtask name", text: $name).textFieldStyle(.roundedBorder).focused($focused)
            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add subtask") {
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

private struct DeskMapTaskChip<Content: View>: View {
    let title: String
    let disclosureWidth: CGFloat?
    let canExpand: Bool
    let isExpanded: Bool
    let toggle: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var isHovered = false
    @FocusState private var disclosureFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            content()
            if let disclosureWidth {
                if canExpand {
                    Button(action: toggle) {
                        Image(systemName: isExpanded ? "minus.circle" : "plus.circle")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                            .opacity(isHovered || isExpanded || disclosureFocused ? 1 : 0)
                            .frame(width: disclosureWidth, height: 22).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).focused($disclosureFocused)
                    .accessibilityLabel("Subtasks and next steps for \(title)")
                    .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                    .help(isExpanded ? "Collapse branch" : "Expand branch")
                } else {
                    Color.clear.frame(width: disclosureWidth, height: 22).allowsHitTesting(false)
                }
            }
        }
        .onHover { isHovered = $0 }
    }
}
#endif
