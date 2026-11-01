import Foundation

public struct LayoutPlan: Equatable, Sendable {
    public let operations: [ItemPlacement]
    public let missingItemIDs: [String]

    /// Hidden regions append to the left of a boundary; visible items prepend to its right.
    public var executionOrder: [ItemPlacement] {
        operations.filter { $0.zone != .visible } + operations.filter { $0.zone == .visible }.reversed()
    }

    /// Boundary drops append in hidden regions and prepend in the visible region.
    /// Retain the desired prefix (or visible suffix) already in relative order;
    /// moving the remaining items to the boundary completes that sequence.
    public func moves(from actual: [ItemPlacement]) -> [ItemPlacement] {
        var retained: Set<String> = []
        for zone in ItemZone.allCases {
            var desired = operations.filter { $0.zone == zone }.map(\.id)
            var current = actual.filter { $0.zone == zone }.sorted { $0.order < $1.order }.map(\.id)
            if zone == .visible { desired.reverse(); current.reverse() }
            var next = 0
            for id in current where next < desired.count {
                if id == desired[next] {
                    retained.insert(id)
                    next += 1
                }
            }
        }
        return executionOrder.filter { !retained.contains($0.id) }
    }

    public func isSatisfied(by actual: [ItemPlacement]) -> Bool {
        let selected = Set(operations.map(\.id))
        for zone in ItemZone.allCases {
            let expectedIDs = operations.filter { $0.zone == zone }.map(\.id)
            let actualIDs = actual.filter { $0.zone == zone && selected.contains($0.id) }.sorted { $0.order < $1.order }.map(\.id)
            if expectedIDs != actualIDs { return false }
        }
        return true
    }

    /// Persisted order is left-to-right within each region. Live IDs are refreshed before execution.
    public init(placements: [ItemPlacement], liveItemIDs: Set<String>) {
        var seen = Set<String>()
        let unique = placements.filter { seen.insert($0.id).inserted }
        missingItemIDs = unique.filter { !liveItemIDs.contains($0.id) }.map(\.id)
        let zoneOrder: [ItemZone: Int] = [.alwaysHidden: 0, .hidden: 1, .visible: 2]
        operations = unique.filter { liveItemIDs.contains($0.id) }.sorted {
            if $0.zone != $1.zone { return zoneOrder[$0.zone]! < zoneOrder[$1.zone]! }
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.id < $1.id
        }
    }
}

public struct RuleTransition: Sendable {
    public private(set) var lastRuleID: UUID?
    public init() {}

    /// Fires on entering a matching rule; manual choices persist until context changes.
    public mutating func evaluate(configuration: Configuration, context: TriggerContext) -> LayoutRule? {
        let rule = configuration.matchingRule(context: context)
        defer { lastRuleID = rule?.id }
        guard rule?.id != lastRuleID else { return nil }
        return rule
    }

    public mutating func reset() { lastRuleID = nil }
}
