import AppKit
import ApplicationServices

struct IndexedMenuItem: Identifiable {
    let id: String
    let title: String
    let appName: String
    let bundleID: String
    let pid: pid_t
    let frame: CGRect
    let element: AXUIElement

    var icon: NSImage? { NSRunningApplication(processIdentifier: pid)?.icon }
}

@MainActor
final class MenuBarIndex {
    private(set) var items: [IndexedMenuItem] = []
    private(set) var unavailableApps: [String] = []
    private(set) var unpositionedItemCount = 0
    private(set) var unpositionedApps: Set<String> = []
    private var knownMenuBarPIDs: Set<pid_t> = []

    func refresh() -> [IndexedMenuItem] {
        items = []
        unavailableApps = []
        unpositionedItemCount = 0
        unpositionedApps = []
        guard AXIsProcessTrusted() else { return [] }
        let applications = NSWorkspace.shared.runningApplications.filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        knownMenuBarPIDs.formIntersection(applications.map(\.processIdentifier))
        for app in applications {
            let application = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(application, 0.15)
            let (bar, barError): (AXUIElement?, AXError) = readAttribute(application, kAXExtrasMenuBarAttribute)
            guard let bar else {
                // Background helpers also return messaging errors despite having no menu bar.
                // Only label a lost connection as a failure after observing that app's extras.
                if knownMenuBarPIDs.contains(app.processIdentifier),
                   ![AXError.attributeUnsupported, .noValue, .notImplemented].contains(barError) {
                    unavailableApps.append(app.localizedName ?? "Unknown app")
                }
                continue
            }
            knownMenuBarPIDs.insert(app.processIdentifier)
            guard let children: [AXUIElement] = attribute(bar, kAXChildrenAttribute) else {
                unavailableApps.append(app.localizedName ?? "Unknown app")
                continue
            }
            var occurrences: [String: Int] = [:]
            for child in children {
                // Image-only extras commonly expose an empty AXTitle and a useful AXDescription.
                let title = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute].compactMap { name -> String? in
                    guard let value: String = attribute(child, name) else { return nil }
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }.first ?? app.localizedName ?? "Menu bar item"
                let rawIdentifier: String? = attribute(child, kAXIdentifierAttribute)
                let identifier = rawIdentifier.flatMap { $0.isEmpty ? nil : $0 } ?? title
                let ordinal = occurrences[identifier, default: 0]
                occurrences[identifier] = ordinal + 1
                let bundleID = app.bundleIdentifier ?? "process.\(app.processIdentifier)"
                let position: AXValue? = attribute(child, kAXPositionAttribute)
                let size: AXValue? = attribute(child, kAXSizeAttribute)
                var point = CGPoint.zero
                var dimensions = CGSize.zero
                guard let position, let size,
                      AXValueGetValue(position, .cgPoint, &point),
                      AXValueGetValue(size, .cgSize, &dimensions),
                      dimensions.width > 0, dimensions.height > 0 else {
                    // Hidden status items have off-screen coordinates but retain their size.
                    // Missing geometry must not become a fabricated item at (0, 0).
                    unpositionedItemCount += 1
                    unpositionedApps.insert(app.localizedName ?? bundleID)
                    continue
                }
                items.append(.init(id: "\(bundleID)|\(identifier)|\(ordinal)", title: title,
                    appName: app.localizedName ?? bundleID, bundleID: bundleID,
                    pid: app.processIdentifier, frame: CGRect(origin: point, size: dimensions), element: child))
            }
        }
        items.sort { $0.frame.minX < $1.frame.minX }
        return items
    }

    func press(_ item: IndexedMenuItem) -> AXError {
        AXUIElementPerformAction(item.element, kAXPressAction as CFString)
    }

    private func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        readAttribute(element, name).0
    }

    private func readAttribute<T>(_ element: AXUIElement, _ name: String) -> (T?, AXError) {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return (status == .success ? value as? T : nil, status)
    }
}
