import FocusDeskCore
import SwiftUI

struct TaskTagsView: View {
    @Bindable var task: FocusTask
    var availableTags: [TaskTagRecord]
    var onTagsChanged: () -> Void

    var body: some View {
        TaskTagsEditorView(
            tags: tagBinding,
            availableTags: availableTags,
            onTagsChanged: onTagsChanged
        )
    }

    private var tagBinding: Binding<[TaskTagRecord]> {
        Binding(
            get: {
                task.tagRecords
            },
            set: { newValue in
                task.tagRecords = newValue
                task.updatedAt = Date()
            }
        )
    }
}

struct TaskTagsEditorView: View {
    @Binding var tags: [TaskTagRecord]
    var availableTags: [TaskTagRecord] = []
    var onTagsChanged: () -> Void = {}

    @State private var editingTagID: UUID?
    @State private var draftName = ""
    @State private var draftColorName = TaskTagPalette.gray.rawValue
    @State private var isAddPopoverPresented = false
    @State private var isEditPopoverPresented = false
    @FocusState private var tagNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TagFlowLayout(spacing: 7, rowSpacing: 22) {
                ForEach(tags) { tag in
                    TaskTagChip(
                        tag: tag,
                        onEdit: {
                            beginEditing(tag)
                        },
                        onDelete: {
                            delete(tag)
                        }
                    )
                }

                addTagButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
        .animation(.smooth(duration: 0.18), value: tags)
        .popover(isPresented: $isEditPopoverPresented) {
            tagEditor(title: "Edit tag")
                .frame(width: 360)
                .padding(14)
        }
    }

    private var addTagButton: some View {
        Button {
            if !isAddPopoverPresented {
                beginAdding()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .regular))

                Text("Tag")
                    .font(.system(size: 11, weight: .regular))
            }
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 2)
            .frame(height: 22)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Add tag")
        .overlay(alignment: .bottom) {
            addTagPopoverAnchor
                .offset(y: 10)
        }
    }

    private var addTagPopoverAnchor: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityHidden(true)
            .popover(
                isPresented: $isAddPopoverPresented,
                attachmentAnchor: .point(.center),
                arrowEdge: .bottom
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    if !availableTagsToAdd.isEmpty {
                        existingTagsPicker
                    }

                    tagEditor(title: "New tag")
                }
                .frame(width: 360)
                .padding(14)
            }
    }

    private var existingTagsPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Existing tags")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)

            TagFlowLayout(spacing: 7, rowSpacing: 7) {
                ForEach(availableTagsToAdd) { tag in
                    Button {
                        addExisting(tag)
                    } label: {
                        StaticTaskTagChip(tag: tag)
                    }
                    .buttonStyle(.plain)
                    .help("Add \(tag.name)")
                }
            }
        }
    }

    private func tagEditor(title: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)

            HStack(alignment: .center, spacing: 9) {
                TextField("Tag name", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)
                    .focused($tagNameFocused)
                    .onSubmit {
                        saveDraft()
                    }
                    .padding(.horizontal, 10)
                    .frame(minWidth: 120, maxWidth: .infinity, minHeight: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor).opacity(0.68))
                    )

                Button {
                    saveDraft()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(canSaveDraft ? .secondary : .tertiary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canSaveDraft)
                .help("Save tag")
            }

            TagFlowLayout(spacing: 7, rowSpacing: 7) {
                ForEach(TaskTagPalette.allCases) { palette in
                    Button {
                        draftColorName = palette.rawValue
                    } label: {
                        Circle()
                            .fill(palette.background)
                            .overlay {
                                Circle()
                                    .stroke(
                                        palette.foreground.opacity(draftColorName == palette.rawValue ? 0.78 : 0.0),
                                        lineWidth: 1.5
                                    )
                            }
                            .overlay {
                                if draftColorName == palette.rawValue {
                                    Circle()
                                        .fill(palette.foreground)
                                        .frame(width: 5, height: 5)
                                }
                            }
                            .frame(width: 18, height: 18)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(palette.displayName)
                }
            }
        }
        .onAppear {
            tagNameFocused = true
        }
    }

    private var availableTagsToAdd: [TaskTagRecord] {
        let currentNames = Set(tags.map { normalizedTagName($0.name) })
        var seenNames = Set<String>()
        var results: [TaskTagRecord] = []

        for tag in availableTags {
            let normalizedName = normalizedTagName(tag.name)

            guard !normalizedName.isEmpty, !currentNames.contains(normalizedName), !seenNames.contains(normalizedName) else {
                continue
            }

            seenNames.insert(normalizedName)
            results.append(tag)
        }

        return results
    }

    private var canSaveDraft: Bool {
        !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func beginAdding() {
        editingTagID = nil
        draftName = ""
        draftColorName = TaskTagPalette.gray.rawValue

        isAddPopoverPresented = true
        tagNameFocused = true
    }

    private func beginEditing(_ tag: TaskTagRecord) {
        editingTagID = tag.id
        draftName = tag.name
        draftColorName = TaskTagPalette.palette(for: tag.colorName).rawValue

        isEditPopoverPresented = true
        tagNameFocused = true
    }

    private func saveDraft() {
        let trimmedName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            return
        }

        var updatedTags = tags

        if let editingTagID, let index = updatedTags.firstIndex(where: { $0.id == editingTagID }) {
            updatedTags[index].name = trimmedName
            updatedTags[index].colorName = draftColorName
        } else {
            let nextOrder = (updatedTags.map(\.sortOrder).max() ?? -1) + 1
            updatedTags.append(
                TaskTagRecord(
                    name: trimmedName,
                    colorName: draftColorName,
                    isEnabled: true,
                    sortOrder: nextOrder
                )
            )
        }

        updateTags(updatedTags)
        dismissPopovers()
    }

    private func addExisting(_ tag: TaskTagRecord) {
        let nextOrder = (tags.map(\.sortOrder).max() ?? -1) + 1
        var tagCopy = TaskTagRecord(
            name: tag.name,
            colorName: TaskTagPalette.palette(for: tag.colorName).rawValue,
            isEnabled: true,
            sortOrder: nextOrder
        )
        tagCopy.name = tagCopy.name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !tagCopy.name.isEmpty else {
            return
        }

        updateTags(tags + [tagCopy])
        dismissPopovers()
    }

    private func dismissPopovers() {
        isAddPopoverPresented = false
        isEditPopoverPresented = false
        editingTagID = nil
        draftName = ""
        draftColorName = TaskTagPalette.gray.rawValue

        tagNameFocused = false
    }

    private func delete(_ tag: TaskTagRecord) {
        updateTags(tags.filter { $0.id != tag.id })

        if editingTagID == tag.id {
            dismissPopovers()
        }
    }

    private func updateTags(_ newTags: [TaskTagRecord]) {
        tags = newTags
        onTagsChanged()
    }

    private func normalizedTagName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private struct TaskTagChip: View {
    var tag: TaskTagRecord
    var onEdit: () -> Void
    var onDelete: () -> Void

    @State private var isHovered = false
    @State private var isActionHovered = false

    var body: some View {
        StaticTaskTagChip(tag: tag)
            .overlay(alignment: .bottom) {
                tagActionButtons
                    .opacity(actionsVisible ? 1 : 0)
                    .allowsHitTesting(actionsVisible)
                    .offset(y: 18)
                    .onHover { hovered in
                        withAnimation(.smooth(duration: 0.12)) {
                            isActionHovered = hovered
                        }
                    }
            }
            .contentShape(Rectangle())
            .onHover { hovered in
                withAnimation(.smooth(duration: 0.12)) {
                    isHovered = hovered
                }
            }
    }

    private var tagActionButtons: some View {
        HStack(spacing: 5) {
            tagActionButton(
                systemName: "pencil",
                help: "Edit tag",
                action: onEdit
            )

            tagActionButton(
                systemName: "xmark",
                help: "Delete tag",
                isDestructive: true,
                action: onDelete
            )
        }
        .fixedSize()
    }

    private func tagActionButton(
        systemName: String,
        help: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(isDestructive ? Color.red.opacity(0.72) : Color.secondary)
                .frame(width: 18, height: 18)
                .background(
                    Circle()
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.78))
                        .overlay(
                            Circle()
                                .stroke(Color.secondary.opacity(0.12), lineWidth: 0.6)
                        )
                        .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var palette: TaskTagPalette {
        TaskTagPalette.palette(for: tag.colorName)
    }

    private var actionsVisible: Bool {
        isHovered || isActionHovered
    }
}

private struct StaticTaskTagChip: View {
    var tag: TaskTagRecord

    var body: some View {
        HStack(spacing: 0) {
            Text(tag.name)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(palette.foreground)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.background)
        )
    }

    private var palette: TaskTagPalette {
        TaskTagPalette.palette(for: tag.colorName)
    }
}

private struct TagFlowLayout: Layout {
    var spacing: CGFloat
    var rowSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let availableWidth = proposal.width ?? CGFloat.greatestFiniteMagnitude
        let rows = rows(for: subviews, availableWidth: availableWidth)
        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { partialResult, row in
            partialResult + row.height
        } + CGFloat(max(0, rows.count - 1)) * rowSpacing

        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = rows(for: subviews, availableWidth: bounds.width)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX

            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }

            y += row.height + rowSpacing
        }
    }

    private func rows(for subviews: Subviews, availableWidth: CGFloat) -> [TagFlowLayoutRow] {
        var rows: [TagFlowLayoutRow] = []
        var currentItems: [TagFlowLayoutItem] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let proposedWidth = currentItems.isEmpty ? size.width : currentWidth + spacing + size.width

            if !currentItems.isEmpty && proposedWidth > availableWidth {
                rows.append(TagFlowLayoutRow(items: currentItems, width: currentWidth, height: currentHeight))
                currentItems = []
                currentWidth = 0
                currentHeight = 0
            }

            currentItems.append(TagFlowLayoutItem(index: index, size: size))
            currentWidth = currentItems.count == 1 ? size.width : currentWidth + spacing + size.width
            currentHeight = max(currentHeight, size.height)
        }

        if !currentItems.isEmpty {
            rows.append(TagFlowLayoutRow(items: currentItems, width: currentWidth, height: currentHeight))
        }

        return rows
    }
}

private struct TagFlowLayoutRow {
    var items: [TagFlowLayoutItem]
    var width: CGFloat
    var height: CGFloat
}

private struct TagFlowLayoutItem {
    var index: Int
    var size: CGSize
}

private enum TaskTagPalette: String, CaseIterable, Identifiable {
    case gray
    case pink
    case rose
    case green
    case mint
    case yellow
    case blue
    case purple
    case orange
    case brown

    var id: String {
        rawValue
    }

    var displayName: String {
        rawValue.capitalized
    }

    var background: Color {
        switch self {
        case .gray:
            return adaptiveColor(
                light: NSColor(calibratedWhite: 0.91, alpha: 1),
                dark: NSColor(calibratedWhite: 0.26, alpha: 1)
            )
        case .pink:
            return adaptiveColor(
                light: NSColor(red: 0.96, green: 0.84, blue: 0.89, alpha: 1),
                dark: NSColor(red: 0.36, green: 0.18, blue: 0.27, alpha: 1)
            )
        case .rose:
            return adaptiveColor(
                light: NSColor(red: 0.98, green: 0.84, blue: 0.82, alpha: 1),
                dark: NSColor(red: 0.38, green: 0.17, blue: 0.15, alpha: 1)
            )
        case .green:
            return adaptiveColor(
                light: NSColor(red: 0.80, green: 0.89, blue: 0.82, alpha: 1),
                dark: NSColor(red: 0.15, green: 0.31, blue: 0.22, alpha: 1)
            )
        case .mint:
            return adaptiveColor(
                light: NSColor(red: 0.80, green: 0.91, blue: 0.88, alpha: 1),
                dark: NSColor(red: 0.13, green: 0.32, blue: 0.30, alpha: 1)
            )
        case .yellow:
            return adaptiveColor(
                light: NSColor(red: 0.95, green: 0.88, blue: 0.68, alpha: 1),
                dark: NSColor(red: 0.38, green: 0.30, blue: 0.12, alpha: 1)
            )
        case .blue:
            return adaptiveColor(
                light: NSColor(red: 0.80, green: 0.89, blue: 0.98, alpha: 1),
                dark: NSColor(red: 0.13, green: 0.25, blue: 0.39, alpha: 1)
            )
        case .purple:
            return adaptiveColor(
                light: NSColor(red: 0.88, green: 0.82, blue: 0.95, alpha: 1),
                dark: NSColor(red: 0.28, green: 0.19, blue: 0.39, alpha: 1)
            )
        case .orange:
            return adaptiveColor(
                light: NSColor(red: 0.96, green: 0.84, blue: 0.75, alpha: 1),
                dark: NSColor(red: 0.39, green: 0.22, blue: 0.13, alpha: 1)
            )
        case .brown:
            return adaptiveColor(
                light: NSColor(red: 0.88, green: 0.82, blue: 0.77, alpha: 1),
                dark: NSColor(red: 0.31, green: 0.25, blue: 0.21, alpha: 1)
            )
        }
    }

    var foreground: Color {
        switch self {
        case .gray:
            return adaptiveColor(
                light: NSColor(calibratedWhite: 0.18, alpha: 1),
                dark: NSColor(calibratedWhite: 0.88, alpha: 1)
            )
        case .pink:
            return adaptiveColor(
                light: NSColor(red: 0.43, green: 0.20, blue: 0.32, alpha: 1),
                dark: NSColor(red: 0.96, green: 0.77, blue: 0.86, alpha: 1)
            )
        case .rose:
            return adaptiveColor(
                light: NSColor(red: 0.47, green: 0.20, blue: 0.17, alpha: 1),
                dark: NSColor(red: 0.98, green: 0.76, blue: 0.72, alpha: 1)
            )
        case .green:
            return adaptiveColor(
                light: NSColor(red: 0.18, green: 0.38, blue: 0.27, alpha: 1),
                dark: NSColor(red: 0.72, green: 0.91, blue: 0.78, alpha: 1)
            )
        case .mint:
            return adaptiveColor(
                light: NSColor(red: 0.14, green: 0.39, blue: 0.36, alpha: 1),
                dark: NSColor(red: 0.70, green: 0.92, blue: 0.88, alpha: 1)
            )
        case .yellow:
            return adaptiveColor(
                light: NSColor(red: 0.43, green: 0.34, blue: 0.13, alpha: 1),
                dark: NSColor(red: 0.96, green: 0.86, blue: 0.55, alpha: 1)
            )
        case .blue:
            return adaptiveColor(
                light: NSColor(red: 0.16, green: 0.34, blue: 0.53, alpha: 1),
                dark: NSColor(red: 0.72, green: 0.86, blue: 0.99, alpha: 1)
            )
        case .purple:
            return adaptiveColor(
                light: NSColor(red: 0.31, green: 0.22, blue: 0.47, alpha: 1),
                dark: NSColor(red: 0.87, green: 0.76, blue: 0.98, alpha: 1)
            )
        case .orange:
            return adaptiveColor(
                light: NSColor(red: 0.48, green: 0.27, blue: 0.16, alpha: 1),
                dark: NSColor(red: 0.98, green: 0.79, blue: 0.64, alpha: 1)
            )
        case .brown:
            return adaptiveColor(
                light: NSColor(red: 0.36, green: 0.28, blue: 0.23, alpha: 1),
                dark: NSColor(red: 0.88, green: 0.78, blue: 0.70, alpha: 1)
            )
        }
    }

    static func palette(for rawValue: String) -> TaskTagPalette {
        TaskTagPalette(rawValue: rawValue) ?? .gray
    }

    private func adaptiveColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let matchedAppearance = appearance.bestMatch(from: [.aqua, .darkAqua])
            return matchedAppearance == .darkAqua ? dark : light
        })
    }
}
