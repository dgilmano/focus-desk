import AppKit
import SwiftUI

/// A project heading followed by its tasks and indented subtasks. Selection always uses the task ID.
struct ProjectTaskPicker: NSViewRepresentable {
    let tasks: [TaskOutline.Item]
    @Binding var selection: UUID?
    var label: String
    var emptyChoice: String? = nil
    var placeholder: String = "Choose task"

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let picker = NSPopUpButton(frame: .zero, pullsDown: false)
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.choose(_:))
        picker.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        (picker.cell as? NSPopUpButtonCell)?.lineBreakMode = .byTruncatingTail
        return picker
    }

    func updateNSView(_ picker: NSPopUpButton, context: Context) {
        let coordinator = context.coordinator
        coordinator.selection = $selection
        if coordinator.tasks != tasks || coordinator.emptyChoice != emptyChoice || coordinator.placeholder != placeholder {
            let outline = TaskOutline(tasks)
            let groups = Dictionary(grouping: outline.rows()) { DeskProject.key(for: $0.item.project) }
            let names = groups.keys.filter { !$0.isEmpty }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            let menu = NSMenu()
            menu.autoenablesItems = false
            let none = menu.addItem(withTitle: emptyChoice ?? placeholder, action: nil, keyEquivalent: "")
            none.isEnabled = emptyChoice != nil
            for key in names + (groups[""] == nil ? [] : [""]) {
                guard let rows = groups[key], let first = rows.first else { continue }
                menu.addItem(.sectionHeader(title: key.isEmpty ? "Untagged" : first.item.project))
                for row in rows {
                    let item = NSMenuItem(title: row.item.title, action: nil, keyEquivalent: "")
                    item.indentationLevel = min(15, row.depth + 1)
                    if row.item.parentID != nil {
                        item.image = NSImage(systemSymbolName: "arrow.turn.down.right", accessibilityDescription: "Subtask")
                    }
                    item.toolTip = outline.path(to: row.id)
                    item.representedObject = row.id
                    menu.addItem(item)
                }
            }
            picker.menu = menu
            coordinator.tasks = tasks
            coordinator.emptyChoice = emptyChoice
            coordinator.placeholder = placeholder
        }
        let index = selection.map { picker.indexOfItem(withRepresentedObject: $0) } ?? -1
        picker.selectItem(at: max(0, index))
        picker.setAccessibilityLabel(label)
        picker.isEnabled = context.environment.isEnabled
    }

    @MainActor final class Coordinator: NSObject {
        var tasks: [TaskOutline.Item]?
        var emptyChoice: String?
        var placeholder = ""
        var selection: Binding<UUID?>

        init(selection: Binding<UUID?>) { self.selection = selection }

        @objc func choose(_ sender: NSPopUpButton) {
            selection.wrappedValue = sender.selectedItem?.representedObject as? UUID
        }
    }
}
