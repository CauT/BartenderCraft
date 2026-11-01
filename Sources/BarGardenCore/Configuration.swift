import Foundation

public enum ItemZone: String, Codable, CaseIterable, Sendable {
    case visible, hidden, alwaysHidden

    public var title: String {
        switch self {
        case .visible: "Visible"
        case .hidden: "Hidden"
        case .alwaysHidden: "Always hidden"
        }
    }
}

public struct ItemPlacement: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var zone: ItemZone
    public var order: Int

    public init(id: String, zone: ItemZone, order: Int) {
        self.id = id
        self.zone = zone
        self.order = order
    }
}

public struct LayoutPreset: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var placements: [ItemPlacement]
    public var collapsed: Bool
    // nil means a legacy preset: leave that collection unchanged.
    public var groups: [MenuBarGroup]?
    public var spacers: [MenuBarSpacer]?
    public var widgets: [WidgetDefinition]?
    public var appearance: MenuBarAppearance?

    public init(id: UUID = UUID(), name: String, placements: [ItemPlacement], collapsed: Bool,
                groups: [MenuBarGroup]? = nil, spacers: [MenuBarSpacer]? = nil, widgets: [WidgetDefinition]? = nil,
                appearance: MenuBarAppearance? = nil) {
        self.id = id
        self.name = name
        self.placements = placements
        self.collapsed = collapsed
        self.groups = groups
        self.spacers = spacers
        self.widgets = widgets
        self.appearance = appearance
    }
}

public enum TriggerCondition: Codable, Equatable, Sendable {
    case frontmostApp(bundleID: String)
    case batteryBelow(percent: Int)
    case timeRange(startMinute: Int, endMinute: Int)

    public func matches(_ context: TriggerContext) -> Bool {
        switch self {
        case .frontmostApp(let bundleID):
            return context.frontmostBundleID == bundleID
        case .batteryBelow(let percent):
            return context.batteryPercent.map { $0 < percent && context.onBattery == true } ?? false
        case .timeRange(let start, let end):
            if start == end { return true }
            if start < end { return context.minuteOfDay >= start && context.minuteOfDay < end }
            return context.minuteOfDay >= start || context.minuteOfDay < end
        }
    }
}

public struct TriggerContext: Sendable {
    public var frontmostBundleID: String?
    public var batteryPercent: Int?
    public var onBattery: Bool?
    public var minuteOfDay: Int

    public init(frontmostBundleID: String?, batteryPercent: Int?, onBattery: Bool?, minuteOfDay: Int) {
        self.frontmostBundleID = frontmostBundleID
        self.batteryPercent = batteryPercent
        self.onBattery = onBattery
        self.minuteOfDay = minuteOfDay
    }
}

public struct LayoutRule: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var enabled: Bool
    public var condition: TriggerCondition
    public var presetID: UUID

    public init(id: UUID = UUID(), name: String, enabled: Bool = true, condition: TriggerCondition, presetID: UUID) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.condition = condition
        self.presetID = presetID
    }
}

public struct Configuration: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var collapsed: Bool = false
    public var autoHideSeconds: Int = 0
    public var placements: [ItemPlacement] = []
    public var presets: [LayoutPreset] = []
    public var rules: [LayoutRule] = []
    public var activePresetID: UUID?
    public var groups: [MenuBarGroup] = []
    public var spacers: [MenuBarSpacer] = []
    public var widgets: [WidgetDefinition] = []
    public var appearance = MenuBarAppearance()

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case version, collapsed, autoHideSeconds, placements, presets, rules, activePresetID, groups, spacers, widgets, appearance
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        collapsed = try values.decode(Bool.self, forKey: .collapsed)
        autoHideSeconds = try values.decode(Int.self, forKey: .autoHideSeconds)
        placements = try values.decode([ItemPlacement].self, forKey: .placements)
        presets = try values.decode([LayoutPreset].self, forKey: .presets)
        rules = try values.decode([LayoutRule].self, forKey: .rules)
        activePresetID = try values.decodeIfPresent(UUID.self, forKey: .activePresetID)
        groups = try values.decodeIfPresent([MenuBarGroup].self, forKey: .groups) ?? []
        spacers = try values.decodeIfPresent([MenuBarSpacer].self, forKey: .spacers) ?? []
        widgets = try values.decodeIfPresent([WidgetDefinition].self, forKey: .widgets) ?? []
        appearance = try values.decodeIfPresent(MenuBarAppearance.self, forKey: .appearance) ?? MenuBarAppearance()
    }

    public mutating func applyPreset(id: UUID) -> Bool {
        guard let preset = presets.first(where: { $0.id == id }) else { return false }
        placements = preset.placements
        collapsed = preset.collapsed
        if let groups = preset.groups { self.groups = groups }
        if let spacers = preset.spacers { self.spacers = spacers }
        if let widgets = preset.widgets { self.widgets = widgets }
        if let appearance = preset.appearance { self.appearance = appearance }
        activePresetID = id
        return true
    }

    /// Only evaluate existing, enabled destinations. Array order is user-visible priority.
    public func matchingRule(context: TriggerContext) -> LayoutRule? {
        rules.first { rule in
            rule.enabled && presets.contains(where: { $0.id == rule.presetID }) && rule.condition.matches(context)
        }
    }
}

public struct ConfigurationStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func load() throws -> Configuration {
        guard FileManager.default.fileExists(atPath: url.path) else { return Configuration() }
        return try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: url))
    }

    public func save(_ configuration: Configuration) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(configuration).write(to: url, options: .atomic)
    }
}
