import SwiftUI
import BarGardenCore

struct WidgetSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var selectedNodeID: UUID?
    @State private var newKind = WidgetNodeKind.text

    private var widget: WidgetDefinition? { model.configuration.widgets.first { $0.id == model.selectedWidgetID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            CraftSectionIntro(title: "Small displays. Useful information.", detail: "Start with a clock, battery chart or text. Connect nodes on the canvas to make it your own.", symbol: "point.3.connected.trianglepath.dotted")
            HStack {
                if !model.configuration.widgets.isEmpty {
                    Picker("Widget", selection: $model.selectedWidgetID) {
                        ForEach(model.configuration.widgets) { widget in Text(widget.title).tag(Optional(widget.id)) }
                    }
                }
                Menu("Add widget") {
                    Button("Clock") { model.addWidget(.clock()) }
                    Button("Battery chart") { model.addWidget(.battery()) }
                    Button("Custom text") { addTextWidget() }
                }
            }
            if let widget {
                HStack {
                    TextField("Widget name", text: binding(widget, \.title)).textFieldStyle(.roundedBorder)
                    Toggle("Show in menu bar", isOn: binding(widget, \.enabled)).toggleStyle(.switch)
                    Button(role: .destructive) { model.removeWidget(widget.id) } label: { Image(systemName: "trash") }
                }
                Stepper("Refresh every \(widget.refreshSeconds) seconds", value: binding(widget, \.refreshSeconds), in: 1...3600)
                Text(widget.enabled ? (model.widgetResults[widget.id] ?? "Waiting for first update") : "Disabled. The menu bar item and scheduled updates are stopped.")
                    .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                Text("Select a node to edit its parameters and connections below. Drag to arrange nodes. Each widget has one menu bar output.")
                    .font(.callout).foregroundStyle(.secondary)
                WidgetCanvasView(widget: widget, selectedNodeID: $selectedNodeID) { id, x, y in
                    edit(widget.id) { value in
                        guard let index = value.nodes.firstIndex(where: { $0.id == id }) else { return }
                        value.nodes[index].x = x
                        value.nodes[index].y = y
                    }
                }.id(widget.id)
                HStack {
                    Picker("Add node", selection: $newKind) {
                        ForEach(WidgetNodeKind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Button("Add") { addNode(to: widget) }
                        .disabled(newKind == .output && widget.nodes.contains { $0.kind == .output })
                }
                Picker("Edit node", selection: $selectedNodeID) {
                    Text("Choose a node…").tag(Optional<UUID>.none)
                    ForEach(Array(widget.nodes.enumerated()), id: \.element.id) { index, node in
                        Text("\(index + 1). \(node.kind.title)").tag(Optional(node.id))
                    }
                }
                if let node = widget.nodes.first(where: { $0.id == selectedNodeID }) {
                    nodeEditor(node, in: widget)
                }
            } else {
                CraftEmptyState(title: "Create your first widget", detail: "Start with a clock, battery chart or text, then connect values, conditions and output.", symbol: "point.3.connected.trianglepath.dotted")
            }
        }.frame(minWidth: 0, maxWidth: .infinity, alignment: .leading).disabled(model.isArranging)
            .onAppear { if widget == nil { model.selectedWidgetID = model.configuration.widgets.first?.id } }
            .onChange(of: model.selectedWidgetID) { _, _ in selectedNodeID = nil }
            .onChange(of: model.configuration.widgets.map(\.id)) { _, _ in
                if widget == nil { model.selectedWidgetID = model.configuration.widgets.first?.id }
            }
    }

    private func nodeEditor(_ node: WidgetNode, in widget: WidgetDefinition) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(node.kind.title).font(.headline)
                    Spacer()
                    Button("Delete node", role: .destructive) {
                        edit(widget.id) { $0.removeNode(node.id) }
                        selectedNodeID = nil
                    }
                }
                if [.text, .number, .clock, .format, .graph].contains(node.kind) {
                    TextField(parameterLabel(node.kind), text: Binding(get: { node.value }, set: { text in
                        edit(widget.id) { value in
                            if let index = value.nodes.firstIndex(where: { $0.id == node.id }) { value.nodes[index].value = text }
                        }
                    })).textFieldStyle(.roundedBorder)
                }
                ForEach(node.kind.inputs, id: \.self) { input in
                    Picker(widgetInputTitle(input), selection: Binding<UUID?>(get: {
                        widget.connections.first { $0.target == node.id && $0.input == input }?.source
                    }, set: { source in
                        edit(widget.id) { value in
                            value.connections.removeAll { $0.target == node.id && $0.input == input }
                            if let source { value.connect(source: source, target: node.id, input: input) }
                        }
                    })) {
                        Text("Not connected").tag(Optional<UUID>.none)
                        ForEach(Array(widget.nodes.enumerated()).filter { $0.element.id != node.id && $0.element.kind != .output }, id: \.element.id) { index, source in
                            Text("\(index + 1). \(source.kind.title) \(source.value.prefix(16))").tag(Optional(source.id))
                        }
                    }
                }
            }.padding(12)
        }
    }

    private func edit(_ id: UUID, change: (inout WidgetDefinition) -> Void) {
        guard var current = model.configuration.widgets.first(where: { $0.id == id }) else { return }
        change(&current)
        model.updateWidget(current)
    }

    private func binding<Value>(_ widget: WidgetDefinition, _ key: WritableKeyPath<WidgetDefinition, Value>) -> Binding<Value> {
        Binding(get: { widget[keyPath: key] }, set: { value in edit(widget.id) { $0[keyPath: key] = value } })
    }

    private func addTextWidget() {
        let text = WidgetNode(kind: .text, value: "Hello", x: 20, y: 40)
        let output = WidgetNode(kind: .output, x: 280, y: 40)
        model.addWidget(.init(title: "Text", nodes: [text, output], connections: [.init(source: text.id, target: output.id, input: "value")]))
    }

    private func addNode(to widget: WidgetDefinition) {
        let defaults: [WidgetNodeKind: String] = [.text: "Text", .number: "1", .clock: "HH:mm:ss", .format: "{value}", .graph: "30"]
        let node = WidgetNode(kind: newKind, value: defaults[newKind] ?? "",
                              x: Double(widget.nodes.count % 3) * 240 + 20, y: Double(widget.nodes.count / 3) * 140 + 40)
        edit(widget.id) { $0.nodes.append(node) }
        selectedNodeID = node.id
    }

    private func parameterLabel(_ kind: WidgetNodeKind) -> String {
        switch kind {
        case .clock: "Date format, e.g. HH:mm:ss"
        case .number: "Number, e.g. 42 or 0.5"
        case .format: "Format text; use {value} for the input"
        case .graph: "Samples to keep, 2–100"
        default: "Display text"
        }
    }
}
