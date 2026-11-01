import Foundation
import BarGardenCore

@MainActor func spacerChecks() throws {
    let legacy = Data("""
    {"version":1,"collapsed":false,"autoHideSeconds":0,"placements":[],"presets":[],"rules":[]}
    """.utf8)
    var configuration = try JSONDecoder().decode(Configuration.self, from: legacy)
    try expect(configuration.spacers.isEmpty, "Existing configuration starts without adding any spacer")
    let normal = MenuBarSpacer(title: "工作区", width: 32)
    let small = MenuBarSpacer(title: "最小", width: -1)
    let large = MenuBarSpacer(title: "最大", width: 200)
    try expect(normal.effectiveWidth == 32 && small.effectiveWidth == 4 && large.effectiveWidth == 160,
               "Spacer width stays in fixed-length display-point bounds")

    var marked = normal
    marked.showsMarker = true
    marked.enabled = false
    let group = MenuBarGroup(title: "保留的组", memberIDs: ["editor"])
    configuration.groups = [group]
    configuration.spacers = [marked, large]
    let saved = LayoutPreset(name: "有空白项", placements: [], collapsed: false, groups: [group], spacers: configuration.spacers)
    configuration.presets = [saved]
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ConfigurationStore(url: directory.appendingPathComponent("configuration.json"))
    try store.save(configuration)
    try expect(try store.load() == configuration,
               "Store round trip preserves spacer identity, title, width, enablement, marker and preset snapshot")

    configuration.spacers = []
    _ = configuration.applyPreset(id: saved.id)
    try expect(configuration.spacers == [marked, large], "Applying a new preset restores all spacer settings")
    let old = LayoutPreset(name: "旧预设", placements: [], collapsed: true)
    configuration.presets.append(old)
    _ = configuration.applyPreset(id: old.id)
    try expect(configuration.spacers == [marked, large], "Legacy preset leaves current spacers intact")
    let clear = LayoutPreset(name: "无空白项", placements: [], collapsed: false, spacers: [])
    configuration.presets.append(clear)
    _ = configuration.applyPreset(id: clear.id)
    try expect(configuration.spacers.isEmpty && configuration.groups == [group],
               "Explicitly empty spacer snapshot clears spacers while preserving unsnapshotted groups")
}
