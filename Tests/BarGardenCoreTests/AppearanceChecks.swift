import Foundation
import CoreGraphics
import BarGardenCore

@MainActor func appearanceChecks() throws {
    let oldData = Data("{\"version\":1,\"collapsed\":false,\"autoHideSeconds\":0,\"placements\":[],\"presets\":[],\"rules\":[]}".utf8)
    var configuration = try JSONDecoder().decode(Configuration.self, from: oldData)
    let main = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    try expect(configuration.appearance == MenuBarAppearance()
        && configuration.appearance.frame(in: main, menuBarHeight: 24, menuBarVisible: true, sessionUnlocked: true) == nil,
        "Old configurations keep system appearance and create no cover frame")
    let style = MenuBarAppearance(background: .gradient, primary: .violet, secondary: .teal,
                                  opacity: 0.65, cornerRadius: 18, borderWidth: 2)
    let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    try expect(style.frame(in: left, menuBarHeight: 24, menuBarVisible: true, sessionUnlocked: true)
        == CGRect(x: -1920, y: 1056, width: 1920, height: 24), "Cover stays at the top of a display left of the main display")
    let above = CGRect(x: 0, y: 1080, width: 1200, height: 900)
    try expect(style.frame(in: above, menuBarHeight: 38, menuBarVisible: true, sessionUnlocked: true)
        == CGRect(x: 0, y: 1942, width: 1200, height: 38), "A display above the main display retains its Cocoa origin and notch-height band")
    try expect(style.frame(in: main, menuBarHeight: 24, menuBarVisible: false, sessionUnlocked: true) == nil
        && style.frame(in: main, menuBarHeight: 24, menuBarVisible: true, sessionUnlocked: false) == nil,
        "Hidden menu bars and locked sessions have no planned appearance window")
    var extreme = style
    extreme.opacity = 2
    extreme.borderWidth = 9
    try expect(extreme.effectiveOpacity == 0.9 && extreme.effectiveBorderWidth == 3
        && extreme.effectiveRadius(height: 24) == 12
        && extreme.frame(in: main, menuBarHeight: 2000, menuBarVisible: true, sessionUnlocked: true) == main,
        "Drawing bounds keep opacity, border, radius and cover height inside supported limits")
    configuration.appearance = style
    configuration.widgets = [.clock()]
    let preset = LayoutPreset(name: "外观", placements: [], collapsed: false, appearance: style)
    configuration.presets = [preset]
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ConfigurationStore(url: directory.appendingPathComponent("configuration.json"))
    try store.save(configuration)
    try expect(try store.load() == configuration, "Appearance settings and preset snapshot survive actual file storage")
    configuration.appearance = MenuBarAppearance()
    _ = configuration.applyPreset(id: preset.id)
    try expect(configuration.appearance == style && configuration.widgets.count == 1, "Appearance preset restores theme without changing unsnapshotted widgets")
    let old = LayoutPreset(name: "旧", placements: [], collapsed: true)
    let clear = LayoutPreset(name: "系统", placements: [], collapsed: false, appearance: MenuBarAppearance())
    configuration.presets += [old, clear]
    _ = configuration.applyPreset(id: old.id)
    try expect(configuration.appearance == style, "Legacy preset keeps current appearance")
    _ = configuration.applyPreset(id: clear.id)
    try expect(configuration.appearance.background == .system, "An explicit system snapshot disables the theme")
}
