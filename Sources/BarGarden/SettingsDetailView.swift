import SwiftUI
import BarGardenCore

struct SettingsDetailView: View {
    @ObservedObject var model: AppModel
    @State private var presetName = ""
    @State private var selectedZone: ItemZone?

    private var visibleItems: [IndexedMenuItem] {
        model.filteredItems.filter { selectedZone == nil || model.zone(for: $0) == selectedZone }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Workspace", systemImage: "square.grid.2x2").foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(.tertiary)
                Text(model.section.rawValue).fontWeight(.medium)
                Spacer()
                Button { model.openQuickBar?() } label: { Label("Quick Access", systemImage: "command") }
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }.help("Refresh menu bar items")
            }.font(.system(size: 12)).padding(.horizontal, 30).padding(.vertical, 18).background(.white)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(model.section.rawValue).font(.system(size: 29, weight: .bold))
                            Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.section == .layout { CraftBadge(title: model.configuration.collapsed ? "Hidden items tucked away" : "Menu bar expanded") }
                    }
                    if let issue = model.configurationIssue { notice(issue, symbol: "exclamationmark.triangle", warning: true) }
                    if let message = model.message, message != model.configurationIssue {
                        HStack { notice(message, symbol: "info.circle", warning: false); Button { model.message = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("Dismiss message") }
                    }
                    switch model.section {
                    case .layout: layout
                    case .groups: GroupSettingsView(model: model)
                    case .spacing: SpacerSettingsView(model: model)
                    case .globalSpacing: GlobalSpacingSettingsView(model: model)
                    case .widgets: WidgetSettingsView(model: model)
                    case .appearance: AppearanceSettingsView(model: model)
                    case .presets: presets
                    case .rules: RulesView(model: model)
                    case .general: general
                    }
                }.padding(30).frame(maxWidth: 1150, alignment: .leading).frame(maxWidth: .infinity)
            }.background(CraftBrand.canvas)
        }
    }

    private var subtitle: String {
        switch model.section {
        case .layout: "Keep everyday tools in sight. Put everything else within reach."
        case .groups: "Bring related tools together with a dedicated menu bar shortcut."
        case .spacing: "Give your menu bar a little breathing room."
        case .globalSpacing: "Adjust system-wide spacing with a recoverable starting point."
        case .widgets: "Build small, useful displays from connected nodes."
        case .appearance: "Shape the look of your menu bar."
        case .presets: "Save a workspace for each part of your day."
        case .rules: "Let your saved layouts follow a schedule or context."
        case .general: "Permissions, startup and everyday preferences."
        }
    }

    private var layout: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                metric("Detected items", value: model.accessibilityGranted ? String(model.items.count) : "—", symbol: "menubar.rectangle", detail: model.accessibilityGranted ? "Available to organize" : "Accessibility required")
                metric("Groups", value: String(model.configuration.groups.count), symbol: "square.grid.2x2", detail: "Your tool collections")
                metric("Saved layouts", value: String(model.configuration.presets.count), symbol: "square.stack.3d.up", detail: "Ready to switch")
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("A place for every icon").font(.system(size: 17, weight: .semibold))
                            Text("Hold ⌘ and drag an icon across a divider to change its section.").font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(model.configuration.collapsed ? "Show hidden items" : "Hide items") { model.toggle() }.buttonStyle(.borderedProminent)
                    }
                    HStack(spacing: 0) {
                        zoneDiagram("Always hidden", symbol: "eye.slash", detail: "Left of ┊", tint: .secondary)
                        Divider().frame(height: 48)
                        zoneDiagram("Hidden", symbol: "tray", detail: "Between ┊ and │", tint: CraftBrand.accent)
                        Divider().frame(height: 48)
                        zoneDiagram("Always visible", symbol: "sun.max", detail: "Right of │", tint: CraftBrand.ink)
                    }.padding(.vertical, 15).background(CraftBrand.canvas, in: RoundedRectangle(cornerRadius: 12))
                }.padding(14)
            }
            if !model.accessibilityGranted {
                permissionCard("Connect Accessibility", detail: "Read, open and arrange menu bar items. Divider-based hiding works without this permission.", granted: false, action: model.requestAccessibility)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Your menu bar").font(.system(size: 16, weight: .semibold))
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Find an item or app", text: $model.query).textFieldStyle(.plain)
                        }.padding(9).frame(width: 230).background(CraftBrand.canvas, in: RoundedRectangle(cornerRadius: 8))
                    }
                    Picker("Section", selection: $selectedZone) {
                        Text("All items").tag(Optional<ItemZone>.none)
                        ForEach(ItemZone.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                    }.pickerStyle(.segmented)
                    if let notice = model.menuReadNotice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                    if visibleItems.isEmpty {
                        CraftEmptyState(title: model.accessibilityGranted ? (model.query.isEmpty && selectedZone == nil ? "No items detected yet" : "No matching items") : "Your icons will appear here",
                                        detail: model.accessibilityGranted ? "Try another search or section. Expand the menu bar and refresh to discover available items." : "Connect Accessibility, then refresh. Your existing menu bar configuration stays in place.", symbol: "menubar.rectangle")
                    } else {
                        ForEach(visibleItems) { item in
                            HStack(spacing: 12) {
                                if let icon = item.icon { Image(nsImage: icon).resizable().frame(width: 28, height: 28) }
                                else { Image(systemName: "app").font(.title2).frame(width: 28, height: 28).foregroundStyle(.secondary) }
                                VStack(alignment: .leading, spacing: 3) { Text(item.title).fontWeight(.medium).lineLimit(1); Text(item.appName).font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                Menu(model.zone(for: item).title) {
                                    ForEach(ItemZone.allCases, id: \.self) { zone in Button("Move to \(zone.title)") { model.move(item, to: zone) } }
                                }.frame(width: 140).disabled(model.isArranging)
                                Button("Open") { model.activate(item) }
                            }.padding(.vertical, 8)
                            if item.id != visibleItems.last?.id { Divider() }
                        }
                    }
                }.padding(14)
            }
        }
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 18) {
            CraftSectionIntro(title: "Capture your current workspace", detail: "Save item order, visibility, groups, spacers, widgets and appearance. Restoring positions requires Accessibility; unavailable apps are skipped.", symbol: "square.stack.3d.up")
            GroupBox {
                HStack(spacing: 12) {
                    TextField("Layout name, e.g. Focus", text: $presetName).textFieldStyle(.roundedBorder)
                    Button("Save current layout") { model.savePreset(name: presetName); presetName = "" }
                        .buttonStyle(.borderedProminent).disabled(model.isArranging || presetName.trimmingCharacters(in: .whitespaces).isEmpty)
                }.padding(12)
            }
            if model.configuration.presets.isEmpty { CraftEmptyState(title: "Make room for different routines", detail: "Organize the menu bar, give this layout a name, and save it above.", symbol: "square.stack.3d.up") }
            ForEach(model.configuration.presets) { preset in
                GroupBox {
                    HStack(spacing: 14) {
                        Image(systemName: "rectangle.3.group").font(.title2).foregroundStyle(CraftBrand.accent)
                        VStack(alignment: .leading, spacing: 5) { Text(preset.name).font(.headline); Text(preset.collapsed ? "Hidden items tucked away" : "Menu bar expanded").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        if model.configuration.activePresetID == preset.id { CraftBadge(title: "Active") }
                        Button("Apply layout") { model.applyPreset(preset.id) }.disabled(model.isArranging)
                        Button(role: .destructive) {
                            model.configuration.presets.removeAll { $0.id == preset.id }
                            if model.configuration.activePresetID == preset.id { model.configuration.activePresetID = nil }
                            model.save()
                        } label: { Image(systemName: "trash") }.help("Delete this saved layout")
                    }.padding(14)
                }
            }
        }.frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("ACCESS & PRIVACY").font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundStyle(.secondary)
            permissionCard("Accessibility", detail: "Read menu bar items and respond to your open and arrange actions.", granted: model.accessibilityGranted, action: model.requestAccessibility)
            permissionCard("Screen Recording · optional", detail: "Show actual menu bar thumbnails. Application icons remain available without it.", granted: model.screenRecordingGranted, action: model.requestScreenRecording)
            Text("EVERYDAY BEHAVIOR").font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundStyle(.secondary).padding(.top, 8)
            GroupBox {
                VStack(alignment: .leading, spacing: 18) {
                    Toggle("Launch \(CraftBrand.name) at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLogin($0) }))
                    Divider()
                    Picker("Automatically hide after expanding", selection: Binding(get: { model.configuration.autoHideSeconds }, set: { model.setAutoHideSeconds($0) })) {
                        Text("Never").tag(0); Text("10 seconds").tag(10); Text("30 seconds").tag(30); Text("60 seconds").tag(60)
                    }
                    Divider()
                    HStack { Label("Show / hide items", systemImage: "keyboard"); Spacer(); Text("⌃⌥B").monospaced() }
                    HStack { Label("Search menu bar", systemImage: "magnifyingglass"); Spacer(); Text("⌃⌥Space").monospaced() }
                    Text("Click the menu bar control to show or hide items. Right-click for its menu, or Option-click for settings.").font(.callout).foregroundStyle(.secondary)
                }.padding(14)
            }
            CraftSectionIntro(title: "Independent. Local. Yours.", detail: "\(CraftBrand.name) is an independent menu bar utility. It is not affiliated with Bartender and does not include its code or artwork.", symbol: "lock.shield")
        }
    }

    private func metric(_ title: String, value: String, symbol: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack { Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary); Spacer(); Image(systemName: symbol).foregroundStyle(CraftBrand.accent) }
            Text(value).font(.system(size: 29, weight: .semibold, design: .rounded))
            Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(17).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(CraftBrand.line, lineWidth: 1))
    }

    private func zoneDiagram(_ title: String, symbol: String, detail: String, tint: Color) -> some View {
        VStack(spacing: 7) { Image(systemName: symbol).font(.system(size: 18)); Text(title).font(.system(size: 12, weight: .semibold)); Text(detail).font(.system(size: 10)).foregroundStyle(.secondary) }
            .foregroundStyle(tint).frame(maxWidth: .infinity)
    }

    private func notice(_ message: String, symbol: String, warning: Bool) -> some View {
        Label(message, systemImage: symbol).font(.callout).foregroundStyle(warning ? Color.orange : CraftBrand.ink)
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background((warning ? Color.orange : CraftBrand.accent).opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func permissionCard(_ title: String, detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        GroupBox {
            HStack(spacing: 14) {
                Image(systemName: granted ? "checkmark.shield" : "hand.raised").font(.system(size: 23)).foregroundStyle(CraftBrand.accent).frame(width: 40)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text(title).font(.system(size: 15, weight: .semibold))
                        CraftBadge(title: granted ? "Enabled" : "Not enabled", positive: granted)
                    }
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if !granted { Button("Open System Settings", action: action) }
            }.padding(14)
        }
    }
}
