import Foundation

public enum GroupAppearance: String, Codable, CaseIterable, Sendable {
    case teal, blue, purple
}

/// An independent menu-bar entry opening an ordered subset of the quick bar.
/// Membership does not change an item's physical visibility zone.
public struct MenuBarGroup: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var symbol: String
    public var appearance: GroupAppearance
    public var enabled: Bool
    public var memberIDs: [String]

    public init(id: UUID = UUID(), title: String, symbol: String = "folder", appearance: GroupAppearance = .teal,
                enabled: Bool = true, memberIDs: [String] = []) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.appearance = appearance
        self.enabled = enabled
        self.memberIDs = memberIDs
    }

    public func availableMemberIDs(in liveIDs: Set<String>) -> [String] {
        memberIDs.filter { liveIDs.contains($0) }
    }
}

extension Configuration {
    /// Assigning a member transfers it from its old group, preserving all other
    /// membership order and layout placements. A missing destination is a no-op.
    public mutating func assignItem(_ itemID: String, toGroup groupID: UUID?) {
        guard groupID == nil || groups.contains(where: { $0.id == groupID }) else { return }
        for index in groups.indices {
            if groups[index].id == groupID {
                if !groups[index].memberIDs.contains(itemID) { groups[index].memberIDs.append(itemID) }
            } else {
                groups[index].memberIDs.removeAll { $0 == itemID }
            }
        }
    }

    public mutating func moveGroupMember(_ itemID: String, in groupID: UUID, by offset: Int) {
        guard let group = groups.firstIndex(where: { $0.id == groupID }),
              let source = groups[group].memberIDs.firstIndex(of: itemID) else { return }
        let destination = source + offset
        guard groups[group].memberIDs.indices.contains(destination) else { return }
        groups[group].memberIDs.swapAt(source, destination)
    }
}
