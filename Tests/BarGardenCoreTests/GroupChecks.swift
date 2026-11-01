import Foundation
import BarGardenCore

@MainActor func groupChecks() throws {
    let legacy = Data("""
    {"version":1,"collapsed":false,"autoHideSeconds":0,"placements":[],"rules":[],
     "presets":[{"id":"89CB8C39-7E4C-44AE-B67A-101EAE26BA4C","name":"旧预设","placements":[],"collapsed":true}]}
    """.utf8)
    var configuration = try JSONDecoder().decode(Configuration.self, from: legacy)
    try expect(configuration.groups.isEmpty && configuration.presets[0].groups == nil,
               "Pre-group configuration and presets load without losing their legacy meaning")
    let work = MenuBarGroup(title: "工作", memberIDs: ["editor", "offline", "backup"])
    let tools = MenuBarGroup(title: "工具", symbol: "wrench.and.screwdriver", appearance: .purple, memberIDs: ["network"])
    configuration.groups = [work, tools]
    _ = configuration.applyPreset(id: configuration.presets[0].id)
    try expect(configuration.groups == [work, tools], "Legacy preset leaves existing groups unchanged")

    configuration.placements = [.init(id: "editor", zone: .alwaysHidden, order: 0)]
    let placements = configuration.placements
    configuration.assignItem("editor", toGroup: tools.id)
    try expect(configuration.groups[0].memberIDs == ["offline", "backup"]
        && configuration.groups[1].memberIDs == ["network", "editor"] && configuration.placements == placements,
        "Transferring a member preserves other members' order and all physical zone placements")
    configuration.assignItem("editor", toGroup: tools.id)
    try expect(configuration.groups[1].memberIDs == ["network", "editor"], "Repeated membership assignment keeps its place without duplicates")
    let beforeMissing = configuration
    configuration.assignItem("editor", toGroup: UUID())
    try expect(configuration == beforeMissing, "A missing destination does not silently remove membership")

    configuration.moveGroupMember("editor", in: tools.id, by: -1)
    try expect(configuration.groups[1].memberIDs == ["editor", "network"], "Member ordering can be changed independently of physical layout")
    configuration.assignItem("editor", toGroup: nil)
    try expect(configuration.groups[1].memberIDs == ["network"] && configuration.placements == placements,
               "Removing a member leaves the real item and its layout in place")
    try expect(work.availableMemberIDs(in: ["backup", "editor"]) == ["editor", "backup"]
        && work.memberIDs == ["editor", "offline", "backup"],
        "Available members keep group order; an offline member remains stored for its return")

    var savedGroup = tools
    savedGroup.enabled = false
    let snapshot = LayoutPreset(name: "带分组", placements: placements, collapsed: false, groups: [savedGroup, work])
    configuration.presets.append(snapshot)
    _ = configuration.applyPreset(id: snapshot.id)
    try expect(configuration.groups == [savedGroup, work], "Preset restores exact titles, symbols, styles, enablement and member order")
    let decoded = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(configuration))
    try expect(decoded == configuration, "Groups and preset snapshots survive a complete configuration round trip")
    let clear = LayoutPreset(name: "无分组", placements: [], collapsed: false, groups: [])
    configuration.presets.append(clear)
    _ = configuration.applyPreset(id: clear.id)
    try expect(configuration.groups.isEmpty, "An explicitly empty group snapshot removes entries rather than acting as a legacy preset")
}
