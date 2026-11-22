#if (DEBUG && !FOCUS_DESK_UPDATES) || FOCUS_DESK_PERSONAL
import AppKit
import SwiftUI

struct VoiceProjectTaskPicker: NSViewRepresentable {
    let tasks: [VoiceTaskContext]
    @Binding var selection: UUID?

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let picker = NSPopUpButton(frame: .zero, pullsDown: false)
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.choose(_:))
        picker.setAccessibilityLabel("Task to update")
        picker.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        (picker.cell as? NSPopUpButtonCell)?.lineBreakMode = .byTruncatingTail
        return picker
    }

    func updateNSView(_ picker: NSPopUpButton, context: Context) {
        let coordinator = context.coordinator
        coordinator.selection = $selection
        if coordinator.tasks != tasks {
            let groups = Dictionary(grouping: tasks) { DeskProject.key(for: $0.project) }
            let names = groups.keys.filter { !$0.isEmpty }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            let menu = NSMenu()
            for key in names + (groups[""] == nil ? [] : [""]) {
                guard let members = groups[key], let first = members.first else { continue }
                menu.addItem(.sectionHeader(title: key.isEmpty ? "Untagged" : first.project))
                for task in members {
                    let item = NSMenuItem(title: task.title, action: nil, keyEquivalent: "")
                    item.indentationLevel = 1
                    item.representedObject = task.id
                    menu.addItem(item)
                }
            }
            picker.menu = menu
            coordinator.tasks = tasks
        }
        picker.selectItem(at: selection.map { picker.indexOfItem(withRepresentedObject: $0) } ?? -1)
        picker.isEnabled = context.environment.isEnabled
    }

    @MainActor final class Coordinator: NSObject {
        var tasks: [VoiceTaskContext] = []
        var selection: Binding<UUID?>

        init(selection: Binding<UUID?>) { self.selection = selection }

        @objc func choose(_ sender: NSPopUpButton) {
            if let id = sender.selectedItem?.representedObject as? UUID { selection.wrappedValue = id }
        }
    }
}
#endif
