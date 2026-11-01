import AppKit
import IOKit.ps
import BarGardenCore

@MainActor
final class WidgetStatusItems: NSObject {
    private var definitions: [UUID: WidgetDefinition] = [:]
    private var entries: [UUID: NSStatusItem] = [:]
    private var nextRefresh: [UUID: Date] = [:]
    private var histories: [UUID: [UUID: [Double]]] = [:]
    private var results: [UUID: String] = [:]
    private var task: Task<Void, Never>?
    private let openEditor: (UUID) -> Void
    private let report: ([UUID: String]) -> Void

    init(openEditor: @escaping (UUID) -> Void, report: @escaping ([UUID: String]) -> Void) {
        self.openEditor = openEditor
        self.report = report
    }

    func sync(_ widgets: [WidgetDefinition]) {
        let enabled = widgets.filter(\.enabled)
        let ids = Set(enabled.map(\.id))
        for id in Array(entries.keys) where !ids.contains(id) {
            if let item = entries.removeValue(forKey: id) { NSStatusBar.system.removeStatusItem(item) }
            definitions[id] = nil
            nextRefresh[id] = nil
            histories[id] = nil
            results[id] = nil
        }
        for widget in enabled {
            if definitions[widget.id] != widget {
                nextRefresh[widget.id] = .distantPast
                histories[widget.id] = nil
            }
            definitions[widget.id] = widget
            if entries[widget.id] == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.autosaveName = "BarGarden.Widget.\(widget.id.uuidString)"
                item.button?.identifier = NSUserInterfaceItemIdentifier(widget.id.uuidString)
                item.button?.target = self
                item.button?.action = #selector(clicked(_:))
                entries[widget.id] = item
            }
        }
        tick()
        if enabled.isEmpty { task?.cancel(); task = nil }
        else if task == nil {
            task = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    self?.tick()
                }
            }
        }
        report(results)
    }

    func stop() {
        task?.cancel()
        task = nil
        for item in entries.values { NSStatusBar.system.removeStatusItem(item) }
        entries.removeAll()
        definitions.removeAll()
        nextRefresh.removeAll()
        histories.removeAll()
        results.removeAll()
        report(results)
    }

    private func tick() {
        let now = Date()
        let due = definitions.values.filter { nextRefresh[$0.id, default: .distantPast] <= now }
        guard !due.isEmpty else { return }
        let needsBattery = due.contains { $0.nodes.contains { $0.kind == .battery || $0.kind == .onBattery } }
        let power = needsBattery ? batteryReading() : (nil, nil)
        let context = WidgetContext(date: now, batteryPercent: power.0, onBattery: power.1)
        for widget in due {
            nextRefresh[widget.id] = now.addingTimeInterval(Double(min(3600, max(1, widget.refreshSeconds))))
            guard let item = entries[widget.id] else { continue }
            do {
                let result = try WidgetEvaluator.evaluate(widget, context: context)
                item.button?.title = result.text.isEmpty ? "·" : String(result.text.prefix(40))
                item.button?.toolTip = "\(widget.title) · \(result.text) · Click to edit"
                item.button?.setAccessibilityLabel("\(widget.title)：\(result.text)")
                for node in widget.nodes {
                    guard let sample = result.graphSamples[node.id] else { continue }
                    let limit = min(100, max(2, Int(node.value) ?? 30))
                    var series = histories[widget.id]?[node.id] ?? []
                    series.append(sample)
                    if series.count > limit { series.removeFirst(series.count - limit) }
                    histories[widget.id, default: [:]][node.id] = series
                }
                let graph = widget.nodes.first { result.graphSamples[$0.id] != nil }
                if let graph, let series = histories[widget.id]?[graph.id] { item.button?.image = drawGraph(series) }
                else { item.button?.image = nil }
                item.button?.imagePosition = .imageLeading
                results[widget.id] = "Output: \(result.text)"
            } catch {
                item.button?.title = "⚠︎"
                item.button?.image = nil
                item.button?.toolTip = "\(widget.title)：\(error.localizedDescription) · Click to edit"
                item.button?.setAccessibilityLabel("\(widget.title)：\(error.localizedDescription)")
                results[widget.id] = error.localizedDescription
            }
        }
        report(results)
    }

    private func drawGraph(_ values: [Double]) -> NSImage {
        let image = NSImage(size: NSSize(width: 50, height: 18))
        image.lockFocus()
        let path = NSBezierPath()
        path.lineWidth = 1.5
        let low = values.min() ?? 0, high = values.max() ?? 0
        for (index, value) in values.enumerated() {
            let x = 1 + 48 * Double(index) / Double(max(1, values.count - 1))
            let y = high == low ? 9 : 2 + 14 * (value - low) / (high - low)
            let point = NSPoint(x: x, y: y)
            if index == 0 { path.move(to: point) } else { path.line(to: point) }
        }
        if values.count == 1 { NSBezierPath(ovalIn: NSRect(x: 0, y: 8, width: 2, height: 2)).fill() }
        NSColor.labelColor.setStroke()
        path.stroke()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private func batteryReading() -> (Int?, Bool?) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else { return (nil, nil) }
        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  info[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = info[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = info[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            return (current * 100 / maximum, (info[kIOPSPowerSourceStateKey] as? String) == kIOPSBatteryPowerValue)
        }
        return (nil, nil)
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw) else { return }
        openEditor(id)
    }
}
