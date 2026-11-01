import SwiftUI
import BarGardenCore

struct RulesView: View {
    @ObservedObject var model: AppModel
    @State private var name = ""
    @State private var conditionKind = 0
    @State private var bundleID = ""
    @State private var batteryThreshold = 30
    @State private var startHour = 9
    @State private var endHour = 18
    @State private var presetID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            CraftSectionIntro(title: "Choose when your layout changes", detail: "Use time, the frontmost application or battery level to apply a saved layout.", symbol: "bolt")
            Label("\(model.lastRuleResult)", systemImage: "clock.arrow.circlepath").font(.callout).foregroundStyle(.secondary)
            HStack {
                Text(model.ruleContextSummary).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Check now") { model.ruleRuntime.evaluate(model: model) }.disabled(model.isArranging)
            }
            if model.configuration.presets.isEmpty {
                CraftEmptyState(title: "Save a layout first", detail: "Rules switch to a saved layout when their conditions match.", symbol: "square.stack.3d.up")
            } else {
                // An in-content header avoids the labeled GroupBox reader crash seen in desktop acceptance.
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("New rule").font(.headline)
                        TextField("Name, e.g. Evening focus", text: $name).textFieldStyle(.roundedBorder)
                        Picker("Condition", selection: $conditionKind) {
                            Text("Time range").tag(0)
                            Text("Frontmost app").tag(1)
                            Text("Battery level").tag(2)
                        }
                        if conditionKind == 0 {
                            HStack {
                                Picker("Start", selection: $startHour) { ForEach(0..<24) { Text(String(format: "%02d:00", $0)).tag($0) } }
                                Picker("End", selection: $endHour) { ForEach(0..<24) { Text(String(format: "%02d:00", $0)).tag($0) } }
                            }
                        } else if conditionKind == 1 {
                            TextField("App bundle ID, e.g. com.apple.Safari", text: $bundleID).textFieldStyle(.roundedBorder)
                            Menu("Choose a running app") {
                                ForEach(runningApps, id: \.bundleIdentifier) { app in
                                    Button(app.localizedName ?? app.bundleIdentifier ?? "App") { bundleID = app.bundleIdentifier ?? "" }
                                }
                            }
                        } else {
                            Stepper("On battery below \(batteryThreshold)%", value: $batteryThreshold, in: 5...95, step: 5)
                        }
                        Picker("Switch to", selection: $presetID) {
                            Text("Choose a layout").tag(Optional<UUID>.none)
                            ForEach(model.configuration.presets) { Text($0.name).tag(Optional($0.id)) }
                        }
                        HStack {
                            Text("Checked every 15 seconds in list order. Runs once when entering a matching condition.")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Add rule", action: addRule).disabled(presetID == nil || name.trimmingCharacters(in: .whitespaces).isEmpty || (conditionKind == 1 && bundleID.isEmpty))
                        }
                    }.padding(12)
                }
            }
            ForEach(model.configuration.rules) { rule in
                GroupBox {
                    HStack {
                        Toggle(isOn: Binding(get: { model.configuration.rules.first(where: { $0.id == rule.id })?.enabled ?? false }, set: { value in
                            if let index = model.configuration.rules.firstIndex(where: { $0.id == rule.id }) { model.configuration.rules[index].enabled = value; model.save() }
                        })) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(rule.name).font(.headline)
                                Text(describe(rule)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Button(role: .destructive) {
                            model.configuration.rules.removeAll { $0.id == rule.id }; model.save()
                        } label: { Image(systemName: "trash") }
                    }.padding(8)
                }
            }
        }.frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func addRule() {
        guard let presetID else { return }
        let condition: TriggerCondition
        switch conditionKind {
        case 1: condition = .frontmostApp(bundleID: bundleID.trimmingCharacters(in: .whitespacesAndNewlines))
        case 2: condition = .batteryBelow(percent: batteryThreshold)
        default: condition = .timeRange(startMinute: startHour * 60, endMinute: endHour * 60)
        }
        model.configuration.rules.append(.init(name: name.trimmingCharacters(in: .whitespacesAndNewlines), condition: condition, presetID: presetID))
        model.save()
        name = ""
    }

    private func describe(_ rule: LayoutRule) -> String {
        let target = model.configuration.presets.first(where: { $0.id == rule.presetID })?.name ?? "Layout deleted"
        let condition: String
        switch rule.condition {
        case .frontmostApp(let id): condition = id
        case .batteryBelow(let percent): condition = "On battery < \(percent)%"
        case .timeRange(let start, let end): condition = String(format: "%02d:%02d–%02d:%02d", start / 60, start % 60, end / 60, end % 60)
        }
        return "\(condition) → \(target)"
    }
}
