import Foundation
import BarGardenCore

@MainActor func incrementalLayoutChecks() throws {
    func placements(_ ids: [String], _ zone: ItemZone) -> [ItemPlacement] {
        ids.enumerated().map { .init(id: $0.element, zone: zone, order: $0.offset) }
    }
    let ids: Set<String> = ["a", "b", "c", "d"]
    let hidden = LayoutPlan(placements: placements(["a", "b", "c", "d"], .hidden), liveItemIDs: ids)
    try expect(hidden.moves(from: hidden.operations).isEmpty, "Matching layout needs no drag")
    try expect(hidden.moves(from: placements(["c", "a", "b", "d"], .hidden)).map(\.id) == ["c", "d"],
               "Hidden boundary retains ordered prefix instead of dragging every item")
    let visible = LayoutPlan(placements: placements(["a", "b", "c", "d"], .visible), liveItemIDs: ids)
    try expect(visible.moves(from: placements(["a", "c", "d", "b"], .visible)).map(\.id) == ["b", "a"],
               "Visible boundary retains ordered suffix and prepends remaining items in reverse")
    let mixed = LayoutPlan(placements: placements(["a", "b"], .hidden) + placements(["c", "d"], .visible), liveItemIDs: ids)
    try expect(mixed.moves(from: placements(["b", "a"], .hidden) + placements(["c", "d"], .visible)).map(\.id) == ["b"],
               "A hidden reorder leaves already-correct visible items untouched")

    // Enumerate every ordered partition of three items into three regions.
    // Replay only the physical boundary operation (remove, then prepend/append),
    // independently of the planner's retained-sequence algorithm.
    let permutations = [["a", "b", "c"], ["a", "c", "b"], ["b", "a", "c"],
                        ["b", "c", "a"], ["c", "a", "b"], ["c", "b", "a"]]
    var layouts: [[ItemPlacement]] = []
    for permutation in permutations {
        for first in 0...3 {
            for second in first...3 {
                layouts.append(placements(Array(permutation[..<first]), .alwaysHidden)
                    + placements(Array(permutation[first..<second]), .hidden)
                    + placements(Array(permutation[second...]), .visible))
            }
        }
    }
    var cases = 0
    for desired in layouts {
        let plan = LayoutPlan(placements: desired + [.init(id: "offline", zone: .hidden, order: 9)], liveItemIDs: ["a", "b", "c"])
        for initial in layouts {
            // An unrelated live item is outside this preset and must not be moved.
            var regions = Dictionary(uniqueKeysWithValues: ItemZone.allCases.map { zone in
                (zone, ["unselected-\(zone.rawValue)"] + initial.filter { $0.zone == zone }.map(\.id))
            })
            let observed = ItemZone.allCases.flatMap { placements(regions[$0]!, $0) }
            let moves = plan.moves(from: observed)
            guard Set(moves.map(\.id)).count == moves.count,
                  moves.allSatisfy({ ["a", "b", "c"].contains($0.id) }) else {
                throw CheckFailure.failed("Planner moved an unrelated, absent or duplicate item")
            }
            for move in moves {
                for zone in ItemZone.allCases { regions[zone]!.removeAll { $0 == move.id } }
                if move.zone == .visible { regions[move.zone]!.insert(move.id, at: 0) }
                else { regions[move.zone]!.append(move.id) }
            }
            for zone in ItemZone.allCases {
                let result = regions[zone]!.filter { !$0.hasPrefix("unselected-") }
                guard result == desired.filter({ $0.zone == zone }).map(\.id) else {
                    throw CheckFailure.failed("Boundary replay failed: \(initial) → \(desired)")
                }
            }
            cases += 1
        }
    }
    try expect(cases == 3600, "All 3,600 three-item region/order transitions reach the requested layout")
}
