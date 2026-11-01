import AppKit
import IOKit.ps
import BarGardenCore

@MainActor
final class RuleRuntime {
    private var task: Task<Void, Never>?
    private var transition = RuleTransition()

    func start(model: AppModel) {
        stop()
        task = Task { @MainActor [weak self, weak model] in
            while !Task.isCancelled {
                guard let self, let model else { return }
                self.evaluate(model: model)
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
        }
    }

    func stop() { task?.cancel(); task = nil; transition.reset() }

    func evaluate(model: AppModel) {
        let context = context()
        let appName = context.frontmostBundleID.flatMap { bundleID in
            NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }?.localizedName
        } ?? context.frontmostBundleID ?? "Unknown app"
        let power = context.onBattery.map { $0 ? "On battery" : "External power" } ?? "Power unknown"
        model.ruleContextSummary = "Frontmost: \(appName) · \(power) · Checked \(Date().formatted(date: .omitted, time: .standard))"
        let candidate = model.configuration.matchingRule(context: context)
        let needsAccessibility = candidate.flatMap { rule in model.configuration.presets.first { $0.id == rule.presetID } }.map { !$0.placements.isEmpty } ?? false
        if needsAccessibility && !model.accessibilityGranted {
            model.lastRuleResult = "\(candidate?.name ?? "Rule") · Waiting for Accessibility"
        } else if !model.isArranging, let rule = transition.evaluate(configuration: model.configuration, context: context) {
            model.lastRuleResult = "\(rule.name) · Applying"
            model.applyPreset(rule.presetID, ruleName: rule.name)
        }
    }

    private func context() -> TriggerContext {
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        var batteryPercent: Int?
        var onBattery: Bool?
        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                guard let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                      info[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                      let current = info[kIOPSCurrentCapacityKey] as? Int,
                      let maximum = info[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
                batteryPercent = current * 100 / maximum
                onBattery = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSBatteryPowerValue
                break
            }
        }
        return .init(frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                     batteryPercent: batteryPercent, onBattery: onBattery,
                     minuteOfDay: (now.hour ?? 0) * 60 + (now.minute ?? 0))
    }
}
