import AppKit
import BarGardenCore

@MainActor
final class GroupStatusItems: NSObject {
    private var entries: [UUID: NSStatusItem] = [:]
    private let openGroup: (UUID) -> Void

    init(openGroup: @escaping (UUID) -> Void) {
        self.openGroup = openGroup
    }

    func sync(_ groups: [MenuBarGroup]) {
        let enabled = groups.filter(\.enabled)
        let ids = Set(enabled.map(\.id))
        for id in Array(entries.keys) where !ids.contains(id) {
            if let item = entries.removeValue(forKey: id) { NSStatusBar.system.removeStatusItem(item) }
        }
        for group in enabled {
            let item: NSStatusItem
            if let existing = entries[group.id] {
                item = existing
            } else {
                item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.autosaveName = "BarGarden.Group.\(group.id.uuidString)"
                entries[group.id] = item
            }
            item.button?.title = group.title
            item.button?.image = NSImage(systemSymbolName: group.symbol, accessibilityDescription: group.title)
            item.button?.imagePosition = .imageLeading
            item.button?.toolTip = "\(group.title) · \(group.memberIDs.count) items"
            item.button?.identifier = NSUserInterfaceItemIdentifier(group.id.uuidString)
            item.button?.target = self
            item.button?.action = #selector(clicked(_:))
        }
    }

    func remove() {
        for item in entries.values { NSStatusBar.system.removeStatusItem(item) }
        entries.removeAll()
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let value = sender.identifier?.rawValue, let id = UUID(uuidString: value) else { return }
        openGroup(id)
    }
}
