import Foundation
import BarGardenCore

@MainActor func widgetChecks() throws {
    let context = WidgetContext(date: Date(timeIntervalSince1970: 0), timeZone: TimeZone(secondsFromGMT: 0)!, batteryPercent: 42, onBattery: false)
    let clock = try WidgetEvaluator.evaluate(.clock(), context: context)
    try expect(clock.text == "00:00", "Clock graph respects supplied date and time zone")
    let battery = WidgetDefinition.battery()
    let batteryResult = try WidgetEvaluator.evaluate(battery, context: context)
    try expect(batteryResult.text == "42%" && Array(batteryResult.graphSamples.values) == [42],
               "Battery graph passes its numeric sample through formatting to the output")
    do { _ = try WidgetEvaluator.evaluate(battery, context: .init(date: context.date)); throw CheckFailure.failed("Unknown battery became a value") }
    catch WidgetGraphError.batteryUnavailable { }
    try expect(true, "Unavailable battery is explicit rather than zero")

    let a = WidgetNode(kind: .number, value: "2"), b = WidgetNode(kind: .number, value: "3")
    let add = WidgetNode(kind: .add), multiply = WidgetNode(kind: .multiply)
    let format = WidgetNode(kind: .format, value: "结果：{value}")
    let output = WidgetNode(kind: .output)
    var math = WidgetDefinition(title: "计算", nodes: [a, b, add, multiply, format, output], connections: [
        .init(source: a.id, target: add.id, input: "a"), .init(source: b.id, target: add.id, input: "b"),
        .init(source: add.id, target: multiply.id, input: "a"), .init(source: b.id, target: multiply.id, input: "b"),
        .init(source: multiply.id, target: format.id, input: "value"), .init(source: format.id, target: output.id, input: "value")])
    try expect(try WidgetEvaluator.evaluate(math, context: context).text == "结果：15", "Connected arithmetic and formatting follow dependency order")

    let condition = WidgetNode(kind: .onBattery), select = WidgetNode(kind: .select)
    let absent = WidgetNode(kind: .battery), ac = WidgetNode(kind: .text, value: "外接电源")
    let selection = WidgetDefinition(title: "选择", nodes: [condition, select, absent, ac, output], connections: [
        .init(source: condition.id, target: select.id, input: "condition"),
        .init(source: absent.id, target: select.id, input: "true"), .init(source: ac.id, target: select.id, input: "false"),
        .init(source: select.id, target: output.id, input: "value")])
    try expect(try WidgetEvaluator.evaluate(selection, context: .init(date: context.date, onBattery: false)).text == "外接电源",
               "Conditional evaluation does not read an unavailable unselected branch")
    try expect(try WidgetEvaluator.evaluate(selection, context: .init(date: context.date, batteryPercent: 18, onBattery: true)).text == "18",
               "Changing the condition evaluates the newly selected branch")

    let less = WidgetNode(kind: .lessThan)
    let comparison = WidgetDefinition(title: "比较", nodes: [a, b, less, output], connections: [
        .init(source: a.id, target: less.id, input: "a"), .init(source: b.id, target: less.id, input: "b"),
        .init(source: less.id, target: output.id, input: "value")])
    try expect(try WidgetEvaluator.evaluate(comparison, context: context).text == "Yes", "Comparison produces an English Boolean value for logic and output")

    func fails(_ widget: WidgetDefinition, with error: WidgetGraphError) throws {
        do { _ = try WidgetEvaluator.evaluate(widget, context: context); throw CheckFailure.failed("Invalid graph accepted: \(error)") }
        catch let actual as WidgetGraphError { try expect(actual == error, "Invalid graph reports \(error)") }
    }
    var broken = math
    broken.connections.append(.init(source: multiply.id, target: add.id, input: "a"))
    broken.connections.removeAll { $0.source == a.id && $0.target == add.id }
    try fails(broken, with: .cycle)
    broken = math
    broken.connections.removeAll { $0.target == multiply.id && $0.input == "b" }
    try fails(broken, with: .missingInput(node: WidgetNodeKind.multiply.title, input: "b"))
    broken = math
    broken.connections.append(.init(source: UUID(), target: output.id, input: "value"))
    try fails(broken, with: .missingNode)
    broken = math
    broken.connections.append(.init(source: a.id, target: output.id, input: "absent"))
    try fails(broken, with: .invalidInput)
    broken = math
    broken.connections.append(.init(source: b.id, target: output.id, input: "value"))
    try fails(broken, with: .duplicateInput)
    broken = math
    broken.nodes[0].kind = .text
    try fails(broken, with: .typeMismatch(node: WidgetNodeKind.add.title))
    broken = math
    broken.nodes[0].value = "inf"
    try fails(broken, with: .invalidNumber)
    broken = math
    broken.nodes[0].value = "1e308"
    try fails(broken, with: .invalidNumber)
    broken = battery
    if let index = broken.nodes.firstIndex(where: { $0.kind == .graph }) { broken.nodes[index].value = "0" }
    try fails(broken, with: .invalidSampleCount)
    broken = math
    broken.nodes.append(.init(kind: .output))
    try fails(broken, with: .outputCount)
    broken = math
    broken.nodes.append(a)
    try fails(broken, with: .duplicateNode)

    math.connect(source: a.id, target: multiply.id, input: "b")
    try expect(try WidgetEvaluator.evaluate(math, context: context).text == "结果：10"
        && math.connections.filter { $0.target == multiply.id && $0.input == "b" }.count == 1,
        "Rewiring replaces an input's old source and changes the actual result")
    math.removeNode(add.id)
    try expect(!math.connections.contains { $0.source == add.id || $0.target == add.id }, "Removing a node removes all attached connections")

    var configuration = Configuration()
    configuration.widgets = [battery, .clock()]
    let preset = LayoutPreset(name: "组件", placements: [], collapsed: false, widgets: configuration.widgets)
    configuration.presets = [preset]
    try expect(try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(configuration)) == configuration,
               "Widget node positions, parameters, edges, lifecycle settings and preset snapshots round trip")
    configuration.widgets = []
    _ = configuration.applyPreset(id: preset.id)
    try expect(configuration.widgets == preset.widgets, "Preset restores the complete saved widget graphs")
    let old = LayoutPreset(name: "旧", placements: [], collapsed: false)
    let clear = LayoutPreset(name: "空", placements: [], collapsed: false, widgets: [])
    configuration.presets += [old, clear]
    _ = configuration.applyPreset(id: old.id)
    try expect(configuration.widgets == preset.widgets, "Legacy preset keeps current widgets")
    _ = configuration.applyPreset(id: clear.id)
    try expect(configuration.widgets.isEmpty, "Explicit empty widget snapshot removes widgets")
    let legacy = Data("{\"version\":1,\"collapsed\":false,\"autoHideSeconds\":0,\"placements\":[],\"presets\":[],\"rules\":[]}".utf8)
    try expect(try JSONDecoder().decode(Configuration.self, from: legacy).widgets.isEmpty,
               "Existing configuration does not automatically enable any widget")
}
