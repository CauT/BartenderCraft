import Foundation

/// A user-owned status item with a fixed width in logical display points.
public struct MenuBarSpacer: Codable, Equatable, Identifiable, Sendable {
    public static let widthRange = 4...160
    public var id: UUID
    public var title: String
    public var width: Int
    public var enabled: Bool
    public var showsMarker: Bool

    public var effectiveWidth: Int { min(Self.widthRange.upperBound, max(Self.widthRange.lowerBound, width)) }

    public init(id: UUID = UUID(), title: String, width: Int = 24, enabled: Bool = true, showsMarker: Bool = false) {
        self.id = id
        self.title = title
        self.width = width
        self.enabled = enabled
        self.showsMarker = showsMarker
    }
}
