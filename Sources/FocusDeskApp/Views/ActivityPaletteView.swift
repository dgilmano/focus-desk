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
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Text("Activity")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FocusDeskStyle.sectionHeadingForeground)
                Spacer(minLength: 0)
                ActivityIconButton(symbol: "pause", title: "Pause activity") { store.pause() }
                    .disabled(store.activeInterval == nil)
                ActivityIconButton(symbol: "slider.horizontal.3", title: "Manage activities") { showingSettings = true }
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: compact ? 82 : 64), spacing: 6)], spacing: 6) {
                    ForEach(store.availableCategories) { category in
                        activityButton(category)
                    }
                }
                .padding(2)
            }
            .scrollIndicators(.hidden)
            .frame(height: compact ? 124 : 114)

            if let current = store.activeCategory, let interval = store.activeInterval {
                Text("\(current.name) since \(interval.startedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(current.name)
            } else {
                Text("Not tracking")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if let error = store.errorMessage {
                Text(error).font(.system(size: 11)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(isPresented: $showingSettings) { ActivityCategoriesView() }
    }

    private func activityButton(_ category: ActivityCategory) -> some View {
        let palette = TaskTagPalette.palette(for: category.colorName)
        let selected = store.activeCategory?.id == category.id
        return Button { store.start(category.id) } label: {
            HStack(spacing: 4) {
                Image(systemName: selected ? "checkmark" : category.symbol)
                    .font(.system(size: 10))
                    .frame(width: 12)
                Text(category.name)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .foregroundStyle(palette.foreground)
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
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

struct ActivityRailButton: View {
    @Environment(ActivityStore.self) private var store
    @State private var showingPalette = false

    var body: some View {
        Button { showingPalette.toggle() } label: {
            Image(systemName: store.activeCategory?.symbol ?? "square.grid.2x2")
                .font(.system(size: 14))
                .foregroundStyle(TaskTagPalette.palette(for: store.activeCategory?.colorName ?? "gray").foreground)
                .frame(width: 32, height: 32)
                .background(TaskTagPalette.palette(for: store.activeCategory?.colorName ?? "gray").background,
                            in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(store.activeCategory.map { "Activity: \($0.name)" } ?? "Choose activity")
        .accessibilityLabel("Activity")
        .popover(isPresented: $showingPalette, arrowEdge: .trailing) {
            ActivityPaletteView(compact: true).padding(16).frame(width: 270)
        }
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
            TextField("Activity name", text: $name).textFieldStyle(.roundedBorder)
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
    }
}

enum ActivityTimeText {
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(0, seconds) / 60)
        if minutes == 0 { return seconds > 0 ? "<1 min" : "0 min" }
        if minutes < 60 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }
}
