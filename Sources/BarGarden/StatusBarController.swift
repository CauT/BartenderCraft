import AppKit
import BarGardenCore

@MainActor
final class StatusBarController: NSObject {
    private let separator: NSStatusItem
    private let alwaysSeparator: NSStatusItem
    private let control: NSStatusItem
    private let toggle: () -> Void
    private let openSettings: () -> Void
    private let openSearch: () -> Void

    init(toggle: @escaping () -> Void, openSettings: @escaping () -> Void, openSearch: @escaping () -> Void) {
        self.toggle = toggle
        self.openSettings = openSettings
        self.openSearch = openSearch
        control = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        separator = NSStatusBar.system.statusItem(withLength: 14)
        alwaysSeparator = NSStatusBar.system.statusItem(withLength: 14)
        super.init()
        separator.autosaveName = "BarGarden.HiddenBoundary"
        alwaysSeparator.autosaveName = "BarGarden.AlwaysHiddenBoundary"
        control.autosaveName = "BarGarden.Control"
        separator.button?.title = "│"
        separator.button?.toolTip = "Hold ⌘ and drag an icon to the left of this divider to hide it"
        separator.button?.target = self
        separator.button?.action = #selector(toggleItems)
        alwaysSeparator.button?.title = "┊"
        alwaysSeparator.button?.toolTip = "Always hidden · Drag icons to the left of this divider"
        control.button?.image = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: "BartenderCraft")
        control.button?.target = self
        control.button?.action = #selector(clicked)
        control.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    func setCollapsed(_ collapsed: Bool, revealAlwaysHidden: Bool = false) {
        separator.length = collapsed ? 10000 : 14
        alwaysSeparator.length = revealAlwaysHidden ? 14 : 10000
        control.button?.image = NSImage(systemSymbolName: collapsed ? "menubar.dock.rectangle" : "menubar.rectangle", accessibilityDescription: collapsed ? "Show hidden items" : "Hide items")
        control.button?.toolTip = collapsed ? "BartenderCraft · Click to show · Right-click for menu" : "BartenderCraft · Click to hide · Right-click for menu"
    }

    func remove() {
        separator.length = 14
        alwaysSeparator.length = 14
        NSStatusBar.system.removeStatusItem(separator)
        NSStatusBar.system.removeStatusItem(alwaysSeparator)
        NSStatusBar.system.removeStatusItem(control)
    }

    func boundary(for zone: ItemZone) -> CGRect? {
        let item = zone == .alwaysHidden ? alwaysSeparator : separator
        guard let rect = item.button?.window?.frame else { return nil }
        let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
        return CGRect(x: rect.minX, y: mainHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    func zone(for frame: CGRect) -> ItemZone {
        if let boundary = boundary(for: .alwaysHidden), frame.midX < boundary.midX { return .alwaysHidden }
        if let boundary = boundary(for: .hidden), frame.midX < boundary.midX { return .hidden }
        return .visible
    }

    @objc private func toggleItems() { toggle() }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let entries: [(String, Selector)] = [("Show / hide items", #selector(toggleItems)), ("Search menu bar…", #selector(search)), ("BartenderCraft Settings…", #selector(settings))]
            for (title, action) in entries {
                let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
                item.target = self
                menu.addItem(item)
            }
            menu.addItem(.separator())
            let quit = NSMenuItem(title: "Quit BartenderCraft", action: #selector(quitApp), keyEquivalent: "q")
            quit.target = self
            menu.addItem(quit)
            control.menu = menu
            control.button?.performClick(nil)
            control.menu = nil
        } else if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            openSettings()
        } else {
            toggle()
        }
    }

    @objc private func settings() { openSettings() }
    @objc private func search() { openSearch() }
    @objc private func quitApp() { NSApp.terminate(nil) }
}
