import SwiftUI
import BarGardenCore

struct SpacerSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var newTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            CraftSectionIntro(title: "A little space goes a long way", detail: "Create adjustable gaps between icons. Markers make spacers easy to locate while arranging.", symbol: "rectangle.split.3x1")
            HStack {
                TextField("Spacer name", text: $newTitle).textFieldStyle(.roundedBorder)
                    .onSubmit { addSpacer() }
                Button("Add spacer") { addSpacer() }.buttonStyle(.borderedProminent)
            }
            Text("Add an adjustable gap between menu bar icons. Hold ⌘ to drag it into position; enable its marker to find it easily. Click it to return here.")
                .font(.callout).foregroundStyle(.secondary)
            if model.configuration.spacers.isEmpty {
                ContentUnavailableView("Give your icons some space", systemImage: "rectangle.split.3x1", description: Text("Add a spacer from 4–160 pt wide. Spacers are included in saved layouts."))
            }
            ForEach(model.configuration.spacers) { spacer in
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            TextField("Spacer name", text: binding(spacer, \.title)).textFieldStyle(.roundedBorder)
                            Toggle("Enabled", isOn: binding(spacer, \.enabled)).toggleStyle(.switch)
                            Button(role: .destructive) { model.removeSpacer(spacer.id) } label: { Image(systemName: "trash") }
                                .help("Remove this spacer")
                        }
                        HStack {
                            Stepper("Width: \(spacer.effectiveWidth) pt", value: binding(spacer, \.width), in: MenuBarSpacer.widthRange)
                            Spacer()
                            Toggle("Show positioning marker", isOn: binding(spacer, \.showsMarker))
                        }
                        HStack(spacing: 0) {
                            Image(systemName: "circle.fill").foregroundStyle(.secondary)
                            ZStack {
                                Color.teal.opacity(0.1)
                                if spacer.showsMarker { Text("┊").foregroundStyle(.secondary) }
                            }.frame(width: CGFloat(spacer.effectiveWidth), height: 24)
                            Image(systemName: "circle.fill").foregroundStyle(.secondary)
                        }.accessibilityLabel("Spacer preview: \(spacer.effectiveWidth) pt")
                    }.padding(12)
                }
            }
        }.disabled(model.isArranging)
    }

    private func addSpacer() {
        model.addSpacer(title: newTitle)
        newTitle = ""
    }

    private func binding<Value>(_ spacer: MenuBarSpacer, _ key: WritableKeyPath<MenuBarSpacer, Value>) -> Binding<Value> {
        Binding(get: { spacer[keyPath: key] }, set: { value in
            guard var current = model.configuration.spacers.first(where: { $0.id == spacer.id }) else { return }
            current[keyPath: key] = value
            model.updateSpacer(current)
        })
    }
}
