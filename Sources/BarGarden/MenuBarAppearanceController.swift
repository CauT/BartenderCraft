import AppKit
import IOKit
import BarGardenCore

@MainActor
private final class AppearanceWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func isAccessibilityHidden() -> Bool { true }
}

@MainActor
final class MenuBarAppearanceController {
    private var style: MenuBarAppearance?
    private var windows: [UInt32: AppearanceWindow] = [:]
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var task: Task<Void, Never>?
    private let report: (String) -> Void

    init(report: @escaping (String) -> Void) { self.report = report }

    func apply(_ value: MenuBarAppearance) {
        guard value != style else { return }
        style = value
        guard value.background != .system else { stop(); return }
        guard #available(macOS 26, *) else {
            stop()
            report("This appearance requires macOS 26 or later. Your settings are preserved.")
            return
        }
        if observers.isEmpty {
            observe(.default, NSApplication.didChangeScreenParametersNotification)
            observe(NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification)
        }
        refresh()
        if task == nil {
            task = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    self?.refresh()
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
        removeWindows()
        report("System appearance")
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        observers.append((center, observer))
    }

    private func removeWindows() {
        for window in windows.values { window.orderOut(nil); window.close() }
        windows.removeAll()
    }

    private func consoleUnlocked() -> Bool {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(root) }
        let locked = IORegistryEntryCreateCFProperty(root, "IOConsoleLocked" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
        return locked == false
    }

    private func refresh() {
        guard let style, style.background != .system else { return }
        guard consoleUnlocked() else { removeWindows(); report("Appearance paused while the desktop is locked."); return }
        guard NSMenu.menuBarVisible() else { removeWindows(); report("Appearance paused while the menu bar is hidden."); return }
        var liveIDs: Set<UInt32> = []
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            let id = number.uint32Value
            let height = max(NSStatusBar.system.thickness, screen.safeAreaInsets.top)
            guard let frame = style.frame(in: screen.frame, menuBarHeight: height, menuBarVisible: true, sessionUnlocked: true) else { continue }
            liveIDs.insert(id)
            let window: AppearanceWindow
            if let existing = windows[id] { window = existing }
            else {
                window = AppearanceWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.isOpaque = false
                window.backgroundColor = .clear
                window.hasShadow = false
                window.ignoresMouseEvents = true
                window.isExcludedFromWindowsMenu = true
                window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)))
                window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
                window.contentView = MenuBarAppearanceView(style: style, frame: NSRect(origin: .zero, size: frame.size))
                windows[id] = window
            }
            window.setFrame(frame, display: false)
            (window.contentView as? MenuBarAppearanceView)?.style = style
            window.orderFrontRegardless()
        }
        for id in Array(windows.keys) where !liveIDs.contains(id) {
            if let window = windows.removeValue(forKey: id) { window.orderOut(nil); window.close() }
        }
        report("Appearance active · \(windows.count) displays")
    }
}
