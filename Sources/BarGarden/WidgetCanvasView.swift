import SwiftUI
import BarGardenCore

struct WidgetCanvasView: View {
    let widget: WidgetDefinition
    @Binding var selectedNodeID: UUID?
    let moveNode: (UUID, Double, Double) -> Void
    @State private var positions: [UUID: CGPoint] = [:]

    private func point(_ id: UUID) -> CGPoint? {
        if let position = positions[id] { return position }
        return widget.nodes.first { $0.id == id }.map { CGPoint(x: $0.x, y: $0.y) }
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    for x in stride(from: CGFloat(12), to: size.width, by: 20) {
                        for y in stride(from: CGFloat(12), to: size.height, by: 20) {
                            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)), with: .color(CraftBrand.line))
                        }
                    }
                }.allowsHitTesting(false)
                ForEach(Array(widget.connections.enumerated()), id: \.offset) { _, edge in
                    if let source = point(edge.source), let target = point(edge.target) {
                        Path { path in
                            let start = CGPoint(x: source.x + 180, y: source.y + 50)
                            let end = CGPoint(x: target.x, y: target.y + 50)
                            path.move(to: start)
                            path.addCurve(to: end, control1: CGPoint(x: start.x + 60, y: start.y),
                                          control2: CGPoint(x: end.x - 60, y: end.y))
                        }.stroke(CraftBrand.accent.opacity(0.5), lineWidth: 2)
                    }
                }
                ForEach(Array(widget.nodes.enumerated()), id: \.element.id) { index, node in
                    let current = point(node.id) ?? .zero
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(String(format: "%02d", index + 1)).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(CraftBrand.accent)
                            Text(node.kind.title).font(.system(size: 12, weight: .semibold))
                        }
                        Text(node.value.isEmpty ? node.kind.inputs.map(widgetInputTitle).joined(separator: " · ") : node.value)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        HStack {
                            if !node.kind.inputs.isEmpty { Circle().fill(.teal).frame(width: 7, height: 7) }
                            Spacer()
                            if node.kind != .output { Circle().fill(.teal).frame(width: 7, height: 7) }
                        }
                    }.padding(12).frame(width: 180, height: 100)
                        .background(node.kind == .output ? CraftBrand.accent.opacity(0.08) : .white, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selectedNodeID == node.id ? .teal : .gray.opacity(0.3), lineWidth: selectedNodeID == node.id ? 2 : 1))
                        .contentShape(Rectangle())
                        .position(x: current.x + 90, y: current.y + 50)
                        .onTapGesture { selectedNodeID = node.id }
                        .accessibilityLabel("Node \(index + 1): \(node.kind.title)")
                        .gesture(DragGesture().onChanged { value in
                            selectedNodeID = node.id
                            positions[node.id] = CGPoint(x: max(0, node.x + value.translation.width), y: max(0, node.y + value.translation.height))
                        }.onEnded { value in
                            moveNode(node.id, max(0, node.x + value.translation.width), max(0, node.y + value.translation.height))
                            positions[node.id] = nil
                        })
                }
            }.frame(width: max(820, (widget.nodes.map(\.x).max() ?? 0) + 230),
                    height: max(300, (widget.nodes.map(\.y).max() ?? 0) + 150))
                .background(CraftBrand.canvas)
        }.frame(height: 330).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

func widgetInputTitle(_ input: String) -> String {
    switch input {
    case "a": "Value A"
    case "b": "Value B"
    case "condition": "Condition"
    case "true": "When true"
    case "false": "Otherwise"
    default: "Input value"
    }
}
