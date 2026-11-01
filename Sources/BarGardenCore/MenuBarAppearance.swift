import Foundation
import CoreGraphics

public enum MenuBarBackground: String, Codable, CaseIterable, Sendable {
    case system, solid, gradient
}

public enum MenuBarTone: String, Codable, CaseIterable, Sendable {
    case teal, blue, violet, graphite
}

public struct MenuBarAppearance: Codable, Equatable, Sendable {
    public var background: MenuBarBackground
    public var primary: MenuBarTone
    public var secondary: MenuBarTone
    public var opacity: Double
    public var cornerRadius: Int
    public var borderWidth: Int

    public init(background: MenuBarBackground = .system, primary: MenuBarTone = .teal,
                secondary: MenuBarTone = .blue, opacity: Double = 0.35, cornerRadius: Int = 0, borderWidth: Int = 0) {
        self.background = background
        self.primary = primary
        self.secondary = secondary
        self.opacity = opacity
        self.cornerRadius = cornerRadius
        self.borderWidth = borderWidth
    }

    public var effectiveOpacity: Double { min(0.9, max(0.1, opacity)) }
    public var effectiveBorderWidth: Int { min(3, max(0, borderWidth)) }
    public func effectiveRadius(height: Double) -> Double { min(max(0, Double(cornerRadius)), max(0, height / 2)) }

    /// Cocoa screen coordinates are retained, including displays above or to
    /// the left of the main screen. No whole-screen cover is created.
    public func frame(in screen: CGRect, menuBarHeight: Double, menuBarVisible: Bool, sessionUnlocked: Bool) -> CGRect? {
        guard background != .system, menuBarVisible, sessionUnlocked,
              screen.width > 0, screen.height > 0, menuBarHeight > 0 else { return nil }
        let height = min(screen.height, menuBarHeight)
        return CGRect(x: screen.minX, y: screen.maxY - height, width: screen.width, height: height)
    }
}
