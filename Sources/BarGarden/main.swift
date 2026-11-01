import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var window: NSWindow?
    private var searchPanel: NSPanel?
    private var hotKeys: HotKeys?
    private var smoke: StatusBarSmoke?
    private var groupItems: GroupStatusItems?
    private var spacerItems: SpacerStatusItems?
    private var widgetItems: WidgetStatusItems?
    private var appearance: MenuBarAppearanceController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let arguments = ProcessInfo.processInfo.arguments
        let smokeOutput = arguments.firstIndex(of: "--statusbar-smoke").flatMap { index in
            arguments.indices.contains(index + 1) ? URL(fileURLWithPath: arguments[index + 1]) : nil
        }
        if smokeOutput != nil { smoke = StatusBarSmoke() }
        let menu = NSMenu()
        let application = NSMenuItem()
        let submenu = NSMenu()
        submenu.addItem(withTitle: "Quit BartenderCraft", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        application.submenu = submenu
        menu.addItem(application)
        NSApp.mainMenu = menu
        model.statusBar = StatusBarController(toggle: { [weak self] in self?.model.toggle() },
            openSettings: { [weak self] in self?.showSettings() },
            openSearch: { [weak self] in self?.showSearch() })
        if let smokeOutput, let controller = model.statusBar {
            smoke?.run(controller: controller, output: smokeOutput)
            return
        }
        model.setCollapsed(model.configuration.collapsed)
        groupItems = GroupStatusItems { [weak self] id in self?.showSearch(groupID: id) }
        model.groupsDidChange = { [weak self] groups in self?.groupItems?.sync(groups) }
        groupItems?.sync(model.configuration.groups)
        spacerItems = SpacerStatusItems { [weak self] in
            self?.model.section = .spacing
            self?.showSettings()
        }
        model.spacersDidChange = { [weak self] spacers in self?.spacerItems?.sync(spacers) }
        spacerItems?.sync(model.configuration.spacers)
        widgetItems = WidgetStatusItems(openEditor: { [weak self] id in
            self?.model.section = .widgets
            self?.model.selectedWidgetID = id
            self?.showSettings()
        }, report: { [weak self] results in self?.model.widgetResults = results })
        model.widgetsDidChange = { [weak self] widgets in self?.widgetItems?.sync(widgets) }
        widgetItems?.sync(model.configuration.widgets)
        appearance = MenuBarAppearanceController { [weak self] status in self?.model.appearanceStatus = status }
        model.appearanceDidChange = { [weak self] style in self?.appearance?.apply(style) }
        appearance?.apply(model.configuration.appearance)
        model.openQuickBar = { [weak self] in self?.showSearch() }
        hotKeys = HotKeys { [weak self] id in
            if id == 1 { self?.model.toggle() }
            else { self?.showSearch() }
        }
        if let error = hotKeys?.register() { model.message = error }
        model.ruleRuntime.start(model: model)
        showSettings()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) { model.checkPermissions() }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeys?.unregister()
        model.ruleRuntime.stop()
        groupItems?.remove()
        spacerItems?.remove()
        widgetItems?.stop()
        appearance?.stop()
        model.statusBar?.remove()
    }

    private func showSettings() {
        if window == nil {
            let result = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 780),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            result.title = CraftBrand.name
            result.minSize = NSSize(width: 960, height: 660)
            result.titlebarAppearsTransparent = true
            result.contentView = NSHostingView(rootView: SettingsView(model: model))
            result.isReleasedWhenClosed = false
            result.center()
            window = result
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        model.refresh()
    }

    private func showSearch(groupID: UUID? = nil) {
        model.activeGroupID = groupID
        model.query = ""
        model.refresh()
        if searchPanel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 610, height: 420),
                styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            panel.title = "Quick Access"
            panel.titlebarAppearsTransparent = true
            panel.level = .floating
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: QuickBarView(model: model) { [weak self] item in
                self?.searchPanel?.orderOut(nil)
                self?.model.activate(item)
            })
            panel.center()
            searchPanel = panel
        }
        NSApp.activate(ignoringOtherApps: true)
        searchPanel?.title = model.activeGroup?.title ?? "Quick Access"
        searchPanel?.makeKeyAndOrderFront(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
