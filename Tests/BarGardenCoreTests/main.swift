import Foundation
import BarGardenCore

enum CheckFailure: Error { case failed(String) }
var count = 0
@MainActor func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try value() else { throw CheckFailure.failed(message) }
    count += 1
}

@MainActor func persistedPresetRoundTrip() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ConfigurationStore(url: directory.appendingPathComponent("configuration.json"))
    var configuration = try store.load()
    try expect(!configuration.collapsed, "New install starts expanded")
    let preset = LayoutPreset(name: "专注", placements: [.init(id: "example.status", zone: .hidden, order: 0)], collapsed: true)
    configuration.presets = [preset]
    try expect(configuration.applyPreset(id: preset.id), "Existing preset applies")
    configuration.rules = [.init(name: "工作", condition: .frontmostApp(bundleID: "example.editor"), presetID: preset.id)]
    try store.save(configuration)
    try expect(try store.load() == configuration, "Configuration round trip preserves placements, rules and preset")
    let before = configuration
    try expect(!configuration.applyPreset(id: UUID()), "Missing preset rejected")
    try expect(configuration == before, "Missing preset does not mutate configuration")
}

@MainActor func timeAndBatteryConditions() throws {
    let condition = TriggerCondition.timeRange(startMinute: 22 * 60, endMinute: 6 * 60)
    func context(_ minute: Int) -> TriggerContext {
        .init(frontmostBundleID: nil, batteryPercent: nil, onBattery: nil, minuteOfDay: minute)
    }
    try expect(condition.matches(context(23 * 60)), "Overnight range includes evening")
    try expect(condition.matches(context(5 * 60)), "Overnight range includes morning")
    try expect(!condition.matches(context(6 * 60)), "Range end is exclusive")
    try expect(!condition.matches(context(12 * 60)), "Overnight range excludes noon")
    let battery = TriggerCondition.batteryBelow(percent: 30)
    try expect(battery.matches(.init(frontmostBundleID: nil, batteryPercent: 20, onBattery: true, minuteOfDay: 0)), "Low discharging battery matches")
    try expect(!battery.matches(.init(frontmostBundleID: nil, batteryPercent: nil, onBattery: nil, minuteOfDay: 0)), "Unknown battery is not zero")
    try expect(!battery.matches(.init(frontmostBundleID: nil, batteryPercent: 20, onBattery: false, minuteOfDay: 0)), "AC power does not match battery rule")
}

@MainActor func rulePriority() throws {
    var configuration = Configuration()
    let first = LayoutPreset(name: "工作", placements: [], collapsed: true)
    let second = LayoutPreset(name: "夜间", placements: [], collapsed: false)
    configuration.presets = [first, second]
    let condition = TriggerCondition.timeRange(startMinute: 0, endMinute: 0)
    let valid = LayoutRule(name: "有效", condition: condition, presetID: second.id)
    configuration.rules = [
        .init(name: "删除的预设", condition: condition, presetID: UUID()),
        .init(name: "已停用", enabled: false, condition: condition, presetID: first.id), valid
    ]
    let context = TriggerContext(frontmostBundleID: nil, batteryPercent: nil, onBattery: nil, minuteOfDay: 100)
    try expect(configuration.matchingRule(context: context)?.id == valid.id, "Priority ignores disabled rules and missing presets")
}

try persistedPresetRoundTrip()
try timeAndBatteryConditions()
try rulePriority()
try incrementalLayoutChecks()
try await dragTransactionChecks()
try groupChecks()
try spacerChecks()
try widgetChecks()
try appearanceChecks()
try globalSpacingChecks()

let placements: [ItemPlacement] = [
    .init(id: "visible", zone: .visible, order: 0), .init(id: "hidden-b", zone: .hidden, order: 1),
    .init(id: "hidden-a", zone: .hidden, order: 0), .init(id: "absent", zone: .hidden, order: 2),
    .init(id: "always", zone: .alwaysHidden, order: 0), .init(id: "visible", zone: .hidden, order: 9)
]
let plan = LayoutPlan(placements: placements, liveItemIDs: ["visible", "hidden-a", "hidden-b", "always"])
try expect(plan.operations.map(\.id) == ["always", "hidden-a", "hidden-b", "visible"], "Region order and within-region order are stable; duplicate ID is not moved twice")
try expect(plan.missingItemIDs == ["absent"], "Missing apps remain explicit")
try expect(plan.isSatisfied(by: plan.operations), "Matching layout satisfies plan")
var reordered = plan.operations
reordered[1].order = 7
try expect(!plan.isSatisfied(by: reordered), "Region verification includes order, not only zone membership")
let visiblePlan = LayoutPlan(placements: [.init(id: "a", zone: .visible, order: 0), .init(id: "b", zone: .visible, order: 1)], liveItemIDs: ["a", "b"])
try expect(visiblePlan.executionOrder.map(\.id) == ["b", "a"], "Visible prepend execution preserves requested left-to-right order")

var ruleConfiguration = Configuration()
let rulePreset = LayoutPreset(name: "工作", placements: [], collapsed: true)
ruleConfiguration.presets = [rulePreset]
let transitionRule = LayoutRule(name: "前台应用", condition: .frontmostApp(bundleID: "example.editor"), presetID: rulePreset.id)
ruleConfiguration.rules = [transitionRule]
let matched = TriggerContext(frontmostBundleID: "example.editor", batteryPercent: nil, onBattery: nil, minuteOfDay: 0)
let unmatched = TriggerContext(frontmostBundleID: "example.browser", batteryPercent: nil, onBattery: nil, minuteOfDay: 0)
var transition = RuleTransition()
try expect(transition.evaluate(configuration: ruleConfiguration, context: matched)?.id == transitionRule.id, "Entering matching context triggers rule")
try expect(transition.evaluate(configuration: ruleConfiguration, context: matched) == nil, "Unchanged context does not override manual choices repeatedly")
try expect(transition.evaluate(configuration: ruleConfiguration, context: unmatched) == nil, "Leaving condition does not apply another preset")
try expect(transition.evaluate(configuration: ruleConfiguration, context: matched)?.id == transitionRule.id, "Re-entering condition triggers again")
print("Passed \(count) core checks: persistence, presets, timing, battery, layout planning, drag cleanup, groups, spacers, widgets, appearance, global spacing and rule transitions.")
