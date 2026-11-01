import Foundation

public enum WidgetNodeKind: String, Codable, CaseIterable, Sendable {
    case text, number, clock, battery, onBattery, add, multiply, format, lessThan, select, graph, output

    public var title: String {
        switch self {
        case .text: "Text"
        case .number: "Number"
        case .clock: "Clock"
        case .battery: "Battery"
        case .onBattery: "On battery"
        case .add: "Add"
        case .multiply: "Multiply"
        case .format: "Format"
        case .lessThan: "Less than"
        case .select: "Choose"
        case .graph: "Chart"
        case .output: "Menu bar output"
        }
    }

    public var inputs: [String] {
        switch self {
        case .add, .multiply, .lessThan: ["a", "b"]
        case .format, .graph, .output: ["value"]
        case .select: ["condition", "true", "false"]
        default: []
        }
    }
}

public struct WidgetNode: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: WidgetNodeKind
    public var value: String
    public var x: Double
    public var y: Double

    public init(id: UUID = UUID(), kind: WidgetNodeKind, value: String = "", x: Double = 20, y: Double = 20) {
        self.id = id
        self.kind = kind
        self.value = value
        self.x = x
        self.y = y
    }
}

public struct WidgetConnection: Codable, Equatable, Sendable {
    public var source: UUID
    public var target: UUID
    public var input: String

    public init(source: UUID, target: UUID, input: String) {
        self.source = source
        self.target = target
        self.input = input
    }
}

public struct WidgetDefinition: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var enabled: Bool
    public var refreshSeconds: Int
    public var nodes: [WidgetNode]
    public var connections: [WidgetConnection]

    public init(id: UUID = UUID(), title: String, enabled: Bool = true, refreshSeconds: Int = 1,
                nodes: [WidgetNode], connections: [WidgetConnection]) {
        self.id = id
        self.title = title
        self.enabled = enabled
        self.refreshSeconds = refreshSeconds
        self.nodes = nodes
        self.connections = connections
    }

    public mutating func connect(source: UUID, target: UUID, input: String) {
        connections.removeAll { $0.target == target && $0.input == input }
        connections.append(.init(source: source, target: target, input: input))
    }

    public mutating func removeNode(_ id: UUID) {
        nodes.removeAll { $0.id == id }
        connections.removeAll { $0.source == id || $0.target == id }
    }

    public static func clock() -> Self {
        let clock = WidgetNode(kind: .clock, value: "HH:mm", x: 20, y: 40)
        let output = WidgetNode(kind: .output, x: 280, y: 40)
        return .init(title: "Clock", nodes: [clock, output], connections: [.init(source: clock.id, target: output.id, input: "value")])
    }

    public static func battery() -> Self {
        let battery = WidgetNode(kind: .battery, x: 20, y: 40)
        let graph = WidgetNode(kind: .graph, value: "30", x: 260, y: 40)
        let format = WidgetNode(kind: .format, value: "{value}%", x: 500, y: 40)
        let output = WidgetNode(kind: .output, x: 740, y: 40)
        return .init(title: "Battery", refreshSeconds: 15, nodes: [battery, graph, format, output], connections: [
            .init(source: battery.id, target: graph.id, input: "value"),
            .init(source: graph.id, target: format.id, input: "value"),
            .init(source: format.id, target: output.id, input: "value")])
    }
}

public struct WidgetContext: Sendable {
    public var date: Date
    public var timeZone: TimeZone
    public var batteryPercent: Int?
    public var onBattery: Bool?

    public init(date: Date, timeZone: TimeZone = .current, batteryPercent: Int? = nil, onBattery: Bool? = nil) {
        self.date = date
        self.timeZone = timeZone
        self.batteryPercent = batteryPercent
        self.onBattery = onBattery
    }
}

public enum WidgetGraphError: Error, LocalizedError, Equatable {
    case duplicateNode, missingNode, invalidInput, duplicateInput, cycle, outputCount
    case missingInput(node: String, input: String), invalidNumber, invalidSampleCount, typeMismatch(node: String), batteryUnavailable

    public var errorDescription: String? {
        switch self {
        case .duplicateNode: "Duplicate nodes found. Remove and re-add them."
        case .missingNode: "A connection refers to a deleted node."
        case .invalidInput: "A connection uses an unknown input port."
        case .duplicateInput: "An input port has multiple sources."
        case .cycle: "The graph contains a cycle. Remove a cyclic connection."
        case .outputCount: "Each widget needs exactly one menu bar output node."
        case .missingInput(let node, let input): "The \(input) input of “\(node)” is not connected."
        case .invalidNumber: "Invalid number or calculation out of range."
        case .invalidSampleCount: "The chart sample count must be an integer from 2–100."
        case .typeMismatch(let node): "“\(node)” received an incompatible value or condition."
        case .batteryUnavailable: "This device has no available internal battery data."
        }
    }
}

public struct WidgetEvaluation: Equatable, Sendable {
    public var text: String
    public var graphSamples: [UUID: Double]
}

private enum WidgetValue {
    case text(String), number(Double), flag(Bool)
    var text: String {
        switch self {
        case .text(let value): value
        case .flag(let value): value ? "Yes" : "No"
        case .number(let value): String(format: value.rounded() == value ? "%.0f" : "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
        }
    }
}

public enum WidgetEvaluator {
    public static func validate(_ widget: WidgetDefinition) throws {
        guard Set(widget.nodes.map(\.id)).count == widget.nodes.count else { throw WidgetGraphError.duplicateNode }
        let nodes = Dictionary(uniqueKeysWithValues: widget.nodes.map { ($0.id, $0) })
        var occupied: [UUID: Set<String>] = [:]
        var outgoing: [UUID: [UUID]] = [:]
        for edge in widget.connections {
            guard nodes[edge.source] != nil, let target = nodes[edge.target] else { throw WidgetGraphError.missingNode }
            guard target.kind.inputs.contains(edge.input) else { throw WidgetGraphError.invalidInput }
            guard occupied[edge.target, default: []].insert(edge.input).inserted else { throw WidgetGraphError.duplicateInput }
            outgoing[edge.source, default: []].append(edge.target)
        }
        var visited: Set<UUID> = []
        var visiting: Set<UUID> = []
        func visit(_ id: UUID) throws {
            if visited.contains(id) { return }
            guard visiting.insert(id).inserted else { throw WidgetGraphError.cycle }
            for next in outgoing[id, default: []] { try visit(next) }
            visiting.remove(id)
            visited.insert(id)
        }
        for node in widget.nodes { try visit(node.id) }
        guard widget.nodes.filter({ $0.kind == .output }).count == 1 else { throw WidgetGraphError.outputCount }
    }

    public static func evaluate(_ widget: WidgetDefinition, context: WidgetContext) throws -> WidgetEvaluation {
        try validate(widget)
        let nodes = Dictionary(uniqueKeysWithValues: widget.nodes.map { ($0.id, $0) })
        var incoming: [UUID: [String: UUID]] = [:]
        for edge in widget.connections { incoming[edge.target, default: [:]][edge.input] = edge.source }
        var cache: [UUID: WidgetValue] = [:]
        var samples: [UUID: Double] = [:]
        func evaluate(_ id: UUID) throws -> WidgetValue {
            if let cached = cache[id] { return cached }
            guard let node = nodes[id] else { throw WidgetGraphError.missingNode }
            func input(_ name: String) throws -> WidgetValue {
                guard let source = incoming[id]?[name] else { throw WidgetGraphError.missingInput(node: node.kind.title, input: name) }
                return try evaluate(source)
            }
            func number(_ name: String) throws -> Double {
                guard case .number(let value) = try input(name) else { throw WidgetGraphError.typeMismatch(node: node.kind.title) }
                return value
            }
            let result: WidgetValue
            switch node.kind {
            case .text: result = .text(node.value)
            case .number:
                guard let value = Double(node.value), value.isFinite else { throw WidgetGraphError.invalidNumber }
                result = .number(value)
            case .clock:
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = context.timeZone
                formatter.dateFormat = node.value.isEmpty ? "HH:mm" : node.value
                result = .text(formatter.string(from: context.date))
            case .battery:
                guard let value = context.batteryPercent else { throw WidgetGraphError.batteryUnavailable }
                result = .number(Double(value))
            case .onBattery:
                guard let value = context.onBattery else { throw WidgetGraphError.batteryUnavailable }
                result = .flag(value)
            case .add, .multiply:
                let a = try number("a"), b = try number("b")
                let value = node.kind == .add ? a + b : a * b
                guard value.isFinite else { throw WidgetGraphError.invalidNumber }
                result = .number(value)
            case .lessThan: result = .flag(try number("a") < number("b"))
            case .format: result = .text(try node.value.replacingOccurrences(of: "{value}", with: input("value").text))
            case .select:
                guard case .flag(let flag) = try input("condition") else { throw WidgetGraphError.typeMismatch(node: node.kind.title) }
                result = try input(flag ? "true" : "false")
            case .graph:
                guard let count = Int(node.value), (2...100).contains(count) else { throw WidgetGraphError.invalidSampleCount }
                let value = try number("value")
                samples[id] = value
                result = .number(value)
            case .output: result = .text(try input("value").text)
            }
            cache[id] = result
            return result
        }
        // validate has established the unique output.
        guard let output = widget.nodes.first(where: { $0.kind == .output }) else { throw WidgetGraphError.outputCount }
        let text = try evaluate(output.id).text
        return .init(text: text, graphSamples: samples)
    }
}
