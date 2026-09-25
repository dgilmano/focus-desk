import AppKit
import SwiftUI

struct ActivityIconButton: View {
    var symbol: String
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

struct ActivityPaletteView: View {
    @Environment(ActivityStore.self) private var store
    @State private var showingSettings = false
    @State private var addingCategory = false
    var compact = false
    var availableWidth: CGFloat = 650

    private var workspaceColumns: [GridItem] {
        let count = max(1, min(store.availableCategories.count, Int(max(104, availableWidth - 80) / 112)))
        return Array(repeating: GridItem(.flexible(minimum: 0), spacing: 8), count: count)
    }

    var body: some View {
        Group {
            if compact {
                compactPalette
            } else {
                workspacePalette
            }
        }
        .sheet(isPresented: $showingSettings) { ActivityCategoriesView(focusNewActivity: addingCategory) }
    }

    private var compactPalette: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Text(compact ? "Activity" : "Activities")
                    .font(.system(size: compact ? 11 : 13, weight: compact ? .semibold : .regular))
                    .foregroundStyle(compact ? FocusDeskStyle.sectionHeadingForeground : .primary)
                Spacer(minLength: 0)
                ActivityIconButton(symbol: "pause", title: "Pause activity") { store.pause() }
                    .disabled(store.activeInterval == nil)
                ActivityIconButton(symbol: "slider.horizontal.3", title: "Manage activities") { showingSettings = true }
            }

            if store.availableCategories.isEmpty {
                Text("No activities").font(.system(size: 12)).foregroundStyle(.secondary)
            } else if compact {
                ScrollView {
                    activityGrid
                }
                .scrollIndicators(.hidden)
                .frame(height: 124)
            } else {
                activityGrid
            }

            if let current = store.activeCategory, let interval = store.activeInterval {
                Text("\(current.name) since \(interval.startedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: compact ? 11 : 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(current.name)
            } else {
                Text("Not tracking")
                    .font(.system(size: compact ? 11 : 12))
                    .foregroundStyle(.secondary)
            }

            if let error = store.errorMessage {
                Text(error).font(.system(size: 11)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var workspacePalette: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Circle()
                    .fill(ActivityAppearance.accent(store.activeCategory?.colorName ?? "gray"))
                    .frame(width: 11, height: 11)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { currentName; currentStart }
                    VStack(alignment: .leading, spacing: 3) { currentName; currentStart }
                }
                Spacer(minLength: 8)
                ActivityIconButton(symbol: "pause.fill", title: "Pause activity") { store.pause() }
                    .padding(3)
                    .background(FocusDeskStyle.focusSurface, in: Circle())
                    .disabled(store.activeInterval == nil)
            }

            HStack(alignment: .top, spacing: 8) {
                if store.availableCategories.isEmpty {
                    Text("No activities").font(.system(size: 13)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                } else {
                    LazyVGrid(columns: workspaceColumns, spacing: 8) {
                        ForEach(store.availableCategories) { category in
                            workspaceActivityButton(category)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1)
                }
                paletteAction(symbol: "plus", title: "Add activity") {
                    addingCategory = true
                    showingSettings = true
                }
                paletteAction(symbol: "gearshape", title: "Manage activities") {
                    addingCategory = false
                    showingSettings = true
                }
            }
        }
    }

    private var currentName: some View {
        Text(store.activeCategory?.name ?? "Not tracking")
            .font(.system(size: 16, weight: .semibold))
            .lineLimit(1)
            .help(store.activeCategory?.name ?? "Not tracking")
    }

    @ViewBuilder private var currentStart: some View {
        if let interval = store.activeInterval {
            Text("Since \(interval.startedAt.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }

    private func workspaceActivityButton(_ category: ActivityCategory) -> some View {
        let accent = ActivityAppearance.accent(category.colorName)
        let selected = store.activeCategory?.id == category.id
        return Button { store.start(category.id) } label: {
            HStack(spacing: 8) {
                Image(systemName: category.symbol)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(accent)
                    .frame(width: 30, height: 30)
                    .background(accent.opacity(0.08), in: Circle())
                Text(category.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .frame(height: 58)
            .background(accent.opacity(selected ? 0.08 : 0.035), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(selected ? accent : FocusDeskStyle.hairline, lineWidth: selected ? 1.5 : 0.7)
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(category.name)
        .accessibilityLabel(category.name)
        .accessibilityValue(selected ? "Active" : "Inactive")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func paletteAction(symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .frame(width: 36, height: 58)
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(FocusDeskStyle.hairline, lineWidth: 0.7) }
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }

    private var activityGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: compact ? 82 : 150), spacing: 8)], spacing: 8) {
            ForEach(store.availableCategories) { category in
                activityButton(category)
            }
        }
        .padding(2)
    }

    private func activityButton(_ category: ActivityCategory) -> some View {
        let palette = TaskTagPalette.palette(for: category.colorName)
        let selected = store.activeCategory?.id == category.id
        return Button { store.start(category.id) } label: {
            HStack(spacing: compact ? 4 : 8) {
                Image(systemName: selected ? "checkmark" : category.symbol)
                    .font(.system(size: compact ? 10 : 12))
                    .frame(width: compact ? 12 : 16)
                Text(category.name)
                    .font(.system(size: compact ? 11 : 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .foregroundStyle(palette.foreground)
            .padding(.horizontal, compact ? 7 : 12)
            .frame(maxWidth: .infinity)
            .frame(height: compact ? 32 : 40)
            .background(palette.background, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(selected ? palette.foreground.opacity(0.8) : .clear, lineWidth: 1.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(category.name)
        .accessibilityLabel(category.name)
        .accessibilityValue(selected ? "Active" : "Inactive")
    }
}

struct ActivityMenuView: View {
    @Environment(ActivityStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Focus Desk").font(.system(size: 13, weight: .semibold))
                Spacer()
                if let interval = store.activeInterval {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(ActivityTimeText.duration(context.date.timeIntervalSince(interval.startedAt)))
                            .font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            ActivityPaletteView(compact: true)
            if let notice = store.notice {
                Text(notice).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Divider()
            Button("Open Focus Desk") {
                openWindow(id: "desk")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.plain)
            Button("Quit Focus Desk") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .font(.system(size: 12))
        .padding(16)
        .frame(width: 286)
    }
}

struct ActivityCategoriesView: View {
    @Environment(ActivityStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var editingID: UUID?
    @State private var name = ""
    @State private var color = "blue"
    @State private var symbol = "briefcase"
    @FocusState private var nameFocused: Bool
    var focusNewActivity = false
    private let symbols = ["briefcase", "book", "house", "cup.and.saucer", "figure.walk", "music.note", "phone", "moon", "gamecontroller", "ellipsis"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Activities").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(store.categories) { category in
                        HStack(spacing: 10) {
                            Image(systemName: category.symbol)
                                .foregroundStyle(TaskTagPalette.palette(for: category.colorName).foreground)
                                .frame(width: 24, height: 24)
                                .background(TaskTagPalette.palette(for: category.colorName).background,
                                            in: RoundedRectangle(cornerRadius: 5))
                            Text(category.name).lineLimit(1)
                            if category.isArchived { Text("Archived").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            ActivityIconButton(symbol: "pencil", title: "Edit \(category.name)") {
                                editingID = category.id
                                name = category.name
                                color = category.colorName
                                symbol = category.symbol
                            }
                            ActivityIconButton(symbol: category.isArchived ? "arrow.uturn.backward" : "archivebox",
                                               title: category.isArchived ? "Restore activity" : "Archive activity") {
                                store.setArchived(category.id, !category.isArchived)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .frame(maxHeight: 200)
            Divider()
            HStack {
                Text(editingID == nil ? "New activity" : "Edit activity").font(.subheadline)
                Spacer()
                if editingID != nil {
                    ActivityIconButton(symbol: "plus", title: "New activity") { editingID = nil; name = "" }
                }
            }
            TextField("Activity name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
            HStack(spacing: 8) {
                ForEach(TaskTagPalette.allCases) { palette in
                    Button { color = palette.rawValue } label: {
                        Circle().fill(palette.background)
                            .overlay { Circle().strokeBorder(color == palette.rawValue ? palette.foreground : .clear, lineWidth: 2) }
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain).help(palette.displayName).accessibilityLabel(palette.displayName)
                    .accessibilityValue(color == palette.rawValue ? "Selected" : "")
                }
            }
            HStack(spacing: 6) {
                ForEach(symbols, id: \.self) { item in
                    ActivityIconButton(symbol: item, title: item.replacingOccurrences(of: ".", with: " ")) { symbol = item }
                        .background(symbol == item ? FocusDeskStyle.selectedBackground : .clear,
                                    in: RoundedRectangle(cornerRadius: 4))
                }
            }
            if let error = store.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button(editingID == nil ? "Add activity" : "Save changes") {
                    if store.saveCategory(id: editingID, name: name, color: color, symbol: symbol) {
                        editingID = nil
                        name = ""
                    }
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .font(.system(size: 12))
        .padding(20)
        .frame(width: 390)
        .onAppear { nameFocused = focusNewActivity }
    }
}

enum ActivityTimeText {
    static func clock(_ date: Date, dayEnd: Date) -> String {
        date == dayEnd ? "24:00" : date.formatted(date: .omitted, time: .shortened)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(0, seconds) / 60)
        if minutes == 0 { return seconds > 0 ? "<1 min" : "0 min" }
        if minutes < 60 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }
}
