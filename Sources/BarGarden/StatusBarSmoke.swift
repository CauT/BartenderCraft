import AppKit

/// Exercises the real WindowServer/AppKit behavior using only this app's own test items.
@MainActor
final class StatusBarSmoke {
    private let visible = NSStatusBar.system.statusItem(withLength: 46)
    private var hidden: NSStatusItem?

    init() { visible.button?.title = "BG-V" }

    func run(controller: StatusBarController, output: URL) {
        hidden = NSStatusBar.system.statusItem(withLength: 46)
        hidden?.button?.title = "BG-H"
        controller.setCollapsed(false, revealAlwaysHidden: true)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            let expanded = snapshot()
            controller.setCollapsed(true, revealAlwaysHidden: true)
            try? await Task.sleep(for: .seconds(1))
            let collapsed = snapshot()
            controller.setCollapsed(false, revealAlwaysHidden: true)
            try? await Task.sleep(for: .seconds(1))
            let restored = snapshot()
            let payload: [String: Any] = ["expanded": expanded, "collapsed": collapsed, "restored": restored]
            do {
                let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: output, options: .atomic)
            } catch { print("Status bar smoke failed: \(error)") }
            if let hidden { NSStatusBar.system.removeStatusItem(hidden) }
            NSStatusBar.system.removeStatusItem(visible)
            NSApp.terminate(nil)
        }
    }

    private func snapshot() -> [String: Any] {
        func frame(_ item: NSStatusItem?) -> [String: Any] {
            guard let window = item?.button?.window else { return ["available": false] }
            let frame = window.frame
            let onScreen = NSScreen.screens.contains { screen in
                screen.frame.intersection(frame).width >= 20 && screen.frame.intersection(frame).height > 0
            }
            let axFrame = item?.button?.accessibilityFrame() ?? .zero
            return ["available": true, "windowNumber": window.windowNumber,
                    "accessibilityFrame": ["x": axFrame.minX, "y": axFrame.minY, "width": axFrame.width, "height": axFrame.height],
                    "x": frame.minX, "y": frame.minY, "width": frame.width,
                    "height": frame.height, "onScreen": onScreen, "windowVisible": window.isVisible]
        }
        // Retain only our own windows. No titles, other applications, or session credentials.
        let windows = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let ownWindows: [[String: Any]] = windows.filter {
            ($0[kCGWindowOwnerPID as String] as? Int) == Int(ProcessInfo.processInfo.processIdentifier)
        }.map { window in
            var result: [String: Any] = [:]
            for key in [kCGWindowNumber, kCGWindowBounds, kCGWindowLayer, kCGWindowIsOnscreen] {
                if let value = window[key as String] { result[key as String] = value }
            }
            return result
        }
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let locked: Any = session?["CGSSessionScreenIsLocked"] as? Bool ?? NSNull() as Any
        return ["visibleItem": frame(visible), "hiddenItem": frame(hidden),
                "ownWindowServerWindows": ownWindows, "screenLockedReported": locked,
                "screens": NSScreen.screens.map { ["x": $0.frame.minX, "y": $0.frame.minY, "width": $0.frame.width, "height": $0.frame.height] }]
    }
}
