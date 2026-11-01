import AppKit
import SwiftUI
@preconcurrency import ApplicationServices
import ServiceManagement
import BarGardenCore

@MainActor
final class AppModel: ObservableObject {
    @Published var configuration = Configuration()
    @Published var items: [IndexedMenuItem] = []
    @Published var accessibilityGranted = false
    @Published var screenRecordingGranted = false
    @Published var message: String?
    @Published private(set) var configurationIssue: String?
    @Published var query = ""
    @Published var activeGroupID: UUID?
    @Published var selectedWidgetID: UUID?
    @Published var widgetResults: [UUID: String] = [:]
    @Published var appearanceStatus = "System appearance"
    @Published var globalSpacingSummary = "Not read yet"
    @Published var hasGlobalSpacingBackup = false
    @Published var section = AppSection.layout
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var lastRuleResult = "No rules triggered yet"
    @Published var ruleContextSummary = "Waiting for first condition check"
    @Published var isArranging = false
    @Published var itemPreviews: [String: NSImage] = [:]
    @Published var menuReadNotice: String?
    var statusBar: StatusBarController?
    var openQuickBar: (() -> Void)?
    var groupsDidChange: (([MenuBarGroup]) -> Void)?
    var spacersDidChange: (([MenuBarSpacer]) -> Void)?
    var widgetsDidChange: (([WidgetDefinition]) -> Void)?
    var appearanceDidChange: ((MenuBarAppearance) -> Void)?
    let index = MenuBarIndex()
    let ruleRuntime = RuleRuntime()
    private let mover = MoveExecutor()
    private var previewTask: Task<Void, Never>?
    private let store: ConfigurationStore
    private let globalSpacing: GlobalSpacingController
    private var hideTask: Task<Void, Never>?
    private var layoutRefreshTask: Task<Void, Never>?

    init(configurationURL: URL? = nil) {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = configurationURL ?? root.appendingPathComponent("BarGarden/configuration.json")
        store = ConfigurationStore(url: url)
        globalSpacing = GlobalSpacingController(root: url.deletingLastPathComponent())
        do { configuration = try store.load() }
        catch {
            configurationIssue = "The configuration could not be read. The original file is preserved. Changes in this session are temporary; repair the file and restart before saving."
            message = "Could not read configuration; original file preserved: \(craftErrorDescription(error))"
        }
        checkPermissions()
        refreshGlobalSpacing()
    }

    func refreshGlobalSpacing() {
        do {
            let status = try globalSpacing.status()
            globalSpacingSummary = status.summary
            hasGlobalSpacingBackup = status.hasBackup
        } catch { globalSpacingSummary = "Could not read: \(craftErrorDescription(error))" }
    }

    func applyGlobalSpacing(_ values: GlobalSpacingValues) {
        guard !isArranging else { return }
        do {
            try globalSpacing.apply(values)
            message = "System spacing saved. Some apps need to be restarted to show the change."
        } catch { message = craftErrorDescription(error) }
        refreshGlobalSpacing()
    }

    func restoreGlobalSpacing() {
        guard !isArranging else { return }
        do {
            try globalSpacing.restore()
            message = "Previous system spacing restored. Some apps need to be restarted to show the change."
        } catch { message = craftErrorDescription(error) }
        refreshGlobalSpacing()
    }

    var filteredItems: [IndexedMenuItem] {
        query.isEmpty ? items : items.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.appName.localizedCaseInsensitiveContains(query) }
    }

    var activeGroup: MenuBarGroup? { configuration.groups.first { $0.id == activeGroupID } }

    var quickBarItems: [IndexedMenuItem] {
        guard let group = activeGroup else { return filteredItems }
        return group.memberIDs.compactMap { id in items.first { $0.id == id } }.filter {
            query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.appName.localizedCaseInsensitiveContains(query)
        }
    }

    var unavailableGroupMemberCount: Int {
        guard let group = activeGroup else { return 0 }
        return group.memberIDs.count - group.availableMemberIDs(in: Set(items.map(\.id))).count
    }

    func checkPermissions() {
        accessibilityGranted = AXIsProcessTrusted()
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openPrivacy("Privacy_Accessibility")
    }

    func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
        openPrivacy("Privacy_ScreenCapture")
    }

    private func openPrivacy(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") { NSWorkspace.shared.open(url) }
    }

    func refresh(previews: Bool = true) {
        checkPermissions()
        items = index.refresh()
        var notices: [String] = []
        if index.unpositionedItemCount > 0 {
            notices.append("\(index.unpositionedItemCount) items have no available position and are omitted from layout (\(index.unpositionedApps.sorted().joined(separator: ", "))).")
        }
        if !index.unavailableApps.isEmpty {
            notices.append("Temporarily unavailable: \(Set(index.unavailableApps).sorted().joined(separator: ", ")). Refresh to try again.")
        }
        menuReadNotice = notices.isEmpty ? nil : notices.joined(separator: "\n")
        if screenRecordingGranted && previews {
            previewTask?.cancel()
            let snapshot = items
            previewTask = Task { @MainActor [weak self] in
                let previews = await MenuItemPreviews.capture(snapshot)
                guard !Task.isCancelled else { return }
                self?.itemPreviews = previews
            }
        } else if !screenRecordingGranted { itemPreviews = [:] }
    }

    func toggle() { setCollapsed(!configuration.collapsed) }

    func setCollapsed(_ value: Bool) {
        guard !isArranging else { return }
        hideTask?.cancel()
        configuration.collapsed = value
        statusBar?.setCollapsed(value)
        save()
        scheduleAutoHide()
        refreshAfterLayoutSettles()
    }

    func setAutoHideSeconds(_ seconds: Int) {
        configuration.autoHideSeconds = seconds
        save()
        scheduleAutoHide()
    }

    private func scheduleAutoHide() {
        hideTask?.cancel()
        hideTask = nil
        if !configuration.collapsed && configuration.autoHideSeconds > 0 {
            let duration = configuration.autoHideSeconds
            hideTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(duration)) } catch { return }
                self?.setCollapsed(true)
            }
        }
    }

    private func refreshAfterLayoutSettles() {
        layoutRefreshTask?.cancel()
        layoutRefreshTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            self?.refresh()
        }
    }

    private func finishArrangement(collapsed: Bool) async {
        statusBar?.setCollapsed(collapsed)
        // AppKit changes the separators before WindowServer updates the other apps' frames.
        try? await Task.sleep(for: .milliseconds(250))
        refresh()
        isArranging = false
        scheduleAutoHide()
    }

    func activate(_ item: IndexedMenuItem) {
        guard !isArranging else { return }
        let revealAlwaysHidden = zone(for: item) == .alwaysHidden
        setCollapsed(false)
        if revealAlwaysHidden {
            statusBar?.setCollapsed(false, revealAlwaysHidden: true)
            message = "Always-hidden items are temporarily visible. Click the menu bar control to hide them again."
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            let current = index.refresh().first(where: { $0.id == item.id })
            guard let current else { message = craftErrorDescription(MenuMoveError.missingItem); return }
            let result = index.press(current)
            switch result {
            case .success: message = nil
            case .cannotComplete:
                // Menu tracking may outlive the AX messaging timeout even when the menu opens.
                // Do not repeat the action: that could close the menu or activate it twice.
                message = "Requested opening of “\(item.title)”. If its menu does not appear, refresh and try again."
            default: message = "Could not open “\(item.title)” (Accessibility error \(result.rawValue)). Refresh and try again."
            }
        }
    }

    func save() {
        if let configurationIssue {
            message = configurationIssue
        } else {
            do { try store.save(configuration) }
            catch { message = "Configuration not saved: \(craftErrorDescription(error))" }
        }
        if activeGroupID != nil, activeGroup == nil { activeGroupID = nil }
        groupsDidChange?(configuration.groups)
        spacersDidChange?(configuration.spacers)
        widgetsDidChange?(configuration.widgets)
        appearanceDidChange?(configuration.appearance)
    }

    func addGroup(title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        configuration.groups.append(MenuBarGroup(title: title))
        configuration.activePresetID = nil
        save()
    }

    func updateGroup(_ group: MenuBarGroup) {
        guard let index = configuration.groups.firstIndex(where: { $0.id == group.id }) else { return }
        configuration.groups[index] = group
        configuration.activePresetID = nil
        save()
    }

    func removeGroup(_ id: UUID) {
        configuration.groups.removeAll { $0.id == id }
        configuration.activePresetID = nil
        save()
    }

    func assignItem(_ id: String, toGroup groupID: UUID?) {
        configuration.assignItem(id, toGroup: groupID)
        configuration.activePresetID = nil
        save()
    }

    func moveGroupMember(_ id: String, in groupID: UUID, by offset: Int) {
        configuration.moveGroupMember(id, in: groupID, by: offset)
        configuration.activePresetID = nil
        save()
    }

    func addSpacer(title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        configuration.spacers.append(MenuBarSpacer(title: title.isEmpty ? "Spacer" : title))
        configuration.activePresetID = nil
        save()
    }

    func updateSpacer(_ spacer: MenuBarSpacer) {
        guard let index = configuration.spacers.firstIndex(where: { $0.id == spacer.id }) else { return }
        var spacer = spacer
        spacer.width = spacer.effectiveWidth
        configuration.spacers[index] = spacer
        configuration.activePresetID = nil
        save()
    }

    func removeSpacer(_ id: UUID) {
        configuration.spacers.removeAll { $0.id == id }
        configuration.activePresetID = nil
        save()
    }

    func addWidget(_ widget: WidgetDefinition) {
        configuration.widgets.append(widget)
        selectedWidgetID = widget.id
        configuration.activePresetID = nil
        save()
    }

    func updateWidget(_ widget: WidgetDefinition) {
        guard let index = configuration.widgets.firstIndex(where: { $0.id == widget.id }) else { return }
        configuration.widgets[index] = widget
        configuration.activePresetID = nil
        save()
    }

    func removeWidget(_ id: UUID) {
        configuration.widgets.removeAll { $0.id == id }
        if selectedWidgetID == id { selectedWidgetID = configuration.widgets.first?.id }
        configuration.activePresetID = nil
        save()
    }

    func setAppearance(_ appearance: MenuBarAppearance) {
        configuration.appearance = appearance
        configuration.activePresetID = nil
        save()
    }

    func savePreset(name: String) {
        guard !isArranging else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if accessibilityGranted {
            refresh()
            configuration.placements = capturePlacements()
        }
        configuration.presets.append(.init(name: trimmed, placements: configuration.placements,
                                          collapsed: configuration.collapsed, groups: configuration.groups,
                                          spacers: configuration.spacers, widgets: configuration.widgets,
                                          appearance: configuration.appearance))
        save()
    }

    func applyPreset(_ id: UUID, ruleName: String? = nil) {
        guard !isArranging, let preset = configuration.presets.first(where: { $0.id == id }) else { return }
        if preset.placements.isEmpty {
            _ = configuration.applyPreset(id: id)
            setCollapsed(preset.collapsed)
            if let ruleName { lastRuleResult = "\(ruleName) · Visibility applied" }
            return
        }
        guard accessibilityGranted else { message = craftErrorDescription(MenuMoveError.permission); return }
        isArranging = true
        hideTask?.cancel()
        layoutRefreshTask?.cancel()
        statusBar?.setCollapsed(false, revealAlwaysHidden: true)
        Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(250))
                refresh(previews: false)
                let plan = LayoutPlan(placements: preset.placements, liveItemIDs: Set(items.map(\.id)))
                for placement in plan.moves(from: capturePlacements()) {
                    try await performMove(id: placement.id, zone: placement.zone)
                }
                guard plan.isSatisfied(by: capturePlacements()) else { throw MenuMoveError.failedVerification }
                _ = configuration.applyPreset(id: id)
                save()
                message = plan.missingItemIDs.isEmpty ? "Restored “\(preset.name)”." : "Restored available items; \(plan.missingItemIDs.count) items are not running or unavailable."
                if let ruleName { lastRuleResult = "\(ruleName) · \(message ?? "Completed")" }
            } catch {
                message = "Layout was not fully restored: \(craftErrorDescription(error))"
                if let ruleName { lastRuleResult = "\(ruleName) · Incomplete: \(craftErrorDescription(error))" }
            }
            await finishArrangement(collapsed: configuration.collapsed)
        }
    }

    func zone(for item: IndexedMenuItem) -> ItemZone { statusBar?.zone(for: item.frame) ?? .visible }

    func move(_ item: IndexedMenuItem, to zone: ItemZone) {
        guard !isArranging else { return }
        isArranging = true
        hideTask?.cancel()
        layoutRefreshTask?.cancel()
        let wasCollapsed = configuration.collapsed
        statusBar?.setCollapsed(false, revealAlwaysHidden: true)
        Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(250))
                try await performMove(id: item.id, zone: zone)
                configuration.placements = capturePlacements()
                configuration.activePresetID = nil
                save()
                message = "Moved “\(item.title)” to \(zone.title)."
            } catch { message = craftErrorDescription(error) }
            await finishArrangement(collapsed: wasCollapsed)
        }
    }

    private func performMove(id: String, zone: ItemZone) async throws {
        refresh(previews: false)
        guard let item = items.first(where: { $0.id == id }) else { throw MenuMoveError.missingItem }
        guard let boundary = statusBar?.boundary(for: zone),
              abs(item.frame.midY - boundary.midY) < 12,
              boundary.width < 100,
              onSameDisplay(item.frame, boundary) else { throw MenuMoveError.noGeometry }
        // Drop next to the separator's edge. Offsetting by half the dragged item's width
        // can cross the adjacent separator when the destination region is empty.
        let destination = CGPoint(x: zone == .visible ? boundary.maxX + 1 : boundary.minX - 1, y: boundary.midY)
        try await mover.move(from: item.frame, to: destination)
        for _ in 0..<12 {
            try await Task.sleep(for: .milliseconds(100))
            refresh(previews: false)
            if let moved = items.first(where: { $0.id == id }), self.zone(for: moved) == zone { return }
        }
        throw MenuMoveError.failedVerification
    }

    private func onSameDisplay(_ item: CGRect, _ boundary: CGRect) -> Bool {
        let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
        return NSScreen.screens.contains { screen in
            let cocoa = screen.frame
            let quartz = CGRect(x: cocoa.minX, y: mainHeight - cocoa.maxY, width: cocoa.width, height: cocoa.height)
            return quartz.contains(CGPoint(x: item.midX, y: item.midY)) && quartz.contains(CGPoint(x: boundary.midX, y: boundary.midY))
        }
    }

    private func capturePlacements() -> [ItemPlacement] {
        var counts: [ItemZone: Int] = [:]
        return items.map { item in
            let zone = zone(for: item)
            let order = counts[zone, default: 0]
            counts[zone] = order + 1
            return .init(id: item.id, zone: zone, order: order)
        }
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { message = "Could not update login startup: \(craftErrorDescription(error))" }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case layout = "Menu bar", groups = "Groups", spacing = "Spacers", globalSpacing = "System spacing", widgets = "Widgets", appearance = "Appearance", presets = "Saved layouts", rules = "Rules", general = "Preferences"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .layout: "menubar.rectangle"
        case .groups: "folder"
        case .spacing: "rectangle.split.3x1"
        case .globalSpacing: "arrow.left.and.right"
        case .widgets: "point.3.connected.trianglepath.dotted"
        case .appearance: "paintpalette"
        case .presets: "square.stack.3d.up"
        case .rules: "bolt"
        case .general: "gearshape"
        }
    }
}
