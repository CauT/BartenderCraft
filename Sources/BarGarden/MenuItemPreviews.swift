import AppKit
import ScreenCaptureKit

@MainActor
enum MenuItemPreviews {
    static func capture(_ items: [IndexedMenuItem]) async -> [String: NSImage] {
        guard CGPreflightScreenCaptureAccess(), !items.isEmpty else { return [:] }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            var result: [String: NSImage] = [:]
            for item in items {
                guard !Task.isCancelled else { break }
                guard let window = content.windows.filter({ $0.owningApplication?.processID == item.pid })
                    .min(by: { distance($0.frame, item.frame) < distance($1.frame, item.frame) }),
                      distance(window.frame, item.frame) < 30 else { continue }
                let configuration = SCStreamConfiguration()
                configuration.width = max(1, Int(item.frame.width * 2))
                configuration.height = max(1, Int(item.frame.height * 2))
                configuration.showsCursor = false
                configuration.ignoreShadowsSingleWindow = true
                let filter = SCContentFilter(desktopIndependentWindow: window)
                if let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) {
                    result[item.id] = NSImage(cgImage: image, size: item.frame.size)
                }
            }
            return result
        } catch { return [:] }
    }

    private static func distance(_ first: CGRect, _ second: CGRect) -> CGFloat {
        abs(first.midX - second.midX) + abs(first.midY - second.midY) + abs(first.width - second.width)
    }
}
