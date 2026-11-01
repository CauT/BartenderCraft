import AppKit
import BarGardenCore

@MainActor
final class SpacerStatusItems: NSObject {
    private var entries: [UUID: NSStatusItem] = [:]
    private let openSettings: () -> Void

    init(openSettings: @escaping () -> Void) {
        self.openSettings = openSettings
    }

    func sync(_ spacers: [MenuBarSpacer]) {
        let enabled = spacers.filter(\.enabled)
        let ids = Set(enabled.map(\.id))
        for id in Array(entries.keys) where !ids.contains(id) {
            if let item = entries.removeValue(forKey: id) { NSStatusBar.system.removeStatusItem(item) }
        }
        for spacer in enabled {
            let item: NSStatusItem
            if let existing = entries[spacer.id] {
                item = existing
            } else {
                item = NSStatusBar.system.statusItem(withLength: CGFloat(spacer.effectiveWidth))
                item.autosaveName = "BarGarden.Spacer.\(spacer.id.uuidString)"
                entries[spacer.id] = item
            }
            item.length = CGFloat(spacer.effectiveWidth)
            item.button?.title = spacer.showsMarker ? "┊" : ""
            item.button?.toolTip = "\(spacer.title) · \(spacer.effectiveWidth) pt · ⌘-drag to reposition · Click to edit"
            item.button?.setAccessibilityLabel("Spacer: \(spacer.title)")
            item.button?.target = self
            item.button?.action = #selector(clicked)
        }
    }

    func remove() {
        for item in entries.values { NSStatusBar.system.removeStatusItem(item) }
        entries.removeAll()
    }

    @objc private func clicked() { openSettings() }
}
