import SwiftUI
import BarGardenCore

struct AppearanceSettingsView: View {
    @ObservedObject var model: AppModel
    private var style: MenuBarAppearance { model.configuration.appearance }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            CraftSectionIntro(title: "A finish that feels like yours", detail: "Preview your color and shape choices below. Changes apply immediately to the menu bar and are included in saved layouts.", symbol: "paintpalette")
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text("APPEARANCE PREVIEW").font(.system(size: 10, weight: .bold)).tracking(1); Spacer(); Text("Illustration").font(.caption).foregroundStyle(.secondary) }
                HStack(spacing: 14) {
                    Image(systemName: "apple.logo")
                    Text("Finder").fontWeight(.semibold)
                    Text("File").foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "wifi")
                    Image(systemName: "battery.75percent")
                    Image(systemName: "menubar.rectangle")
                    Text("9:41 AM").monospacedDigit()
                }.font(.system(size: 12)).padding(16)
                    .background(LinearGradient(colors: previewColors, startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: CGFloat(style.cornerRadius)))
                    .overlay(RoundedRectangle(cornerRadius: CGFloat(style.cornerRadius)).stroke(CraftBrand.ink.opacity(0.25), lineWidth: CGFloat(style.borderWidth)))
            }.padding(20).background(.white, in: RoundedRectangle(cornerRadius: 16))

            GroupBox {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Menu bar background", selection: binding(\.background)) {
                        Text("System default").tag(MenuBarBackground.system)
                        Text("Solid color").tag(MenuBarBackground.solid)
                        Text("Gradient").tag(MenuBarBackground.gradient)
                    }
                    if style.background != .system {
                        Picker("Primary color", selection: binding(\.primary)) { tones }
                        if style.background == .gradient { Picker("Secondary color", selection: binding(\.secondary)) { tones } }
                        HStack {
                            Text("Opacity")
                            Slider(value: binding(\.opacity), in: 0.1...0.9, step: 0.05)
                            Text("\(Int(style.effectiveOpacity * 100))%").monospacedDigit().frame(width: 45)
                        }
                        Stepper("Corner radius: \(style.cornerRadius) pt", value: binding(\.cornerRadius), in: 0...18)
                        Stepper("Border: \(style.borderWidth) pt", value: binding(\.borderWidth), in: 0...3)
                    }
                    Text(model.appearanceStatus).font(.callout).foregroundStyle(.secondary)
                    Text("Applies to the top menu bar area of each display and is saved with layouts. Choose System default to restore the original appearance.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Restore system appearance") { model.setAppearance(MenuBarAppearance()) }
                        .disabled(style.background == .system)
                }.padding(12)
            }
        }.disabled(model.isArranging || !supported)
    }

    private var previewColors: [Color] {
        guard style.background != .system else { return [CraftBrand.canvas, CraftBrand.canvas] }
        let first = tone(style.primary).opacity(style.effectiveOpacity)
        return [first, style.background == .gradient ? tone(style.secondary).opacity(style.effectiveOpacity) : first]
    }

    private func tone(_ tone: MenuBarTone) -> Color {
        switch tone { case .teal: CraftBrand.accent; case .blue: .blue; case .violet: .purple; case .graphite: .gray }
    }

    private var supported: Bool {
        if #available(macOS 26, *) { true } else { false }
    }

    private var tones: some View {
        Group {
            Text("Teal").tag(MenuBarTone.teal)
            Text("Blue").tag(MenuBarTone.blue)
            Text("Purple").tag(MenuBarTone.violet)
            Text("Graphite").tag(MenuBarTone.graphite)
        }
    }

    private func binding<Value>(_ key: WritableKeyPath<MenuBarAppearance, Value>) -> Binding<Value> {
        Binding(get: { style[keyPath: key] }, set: { value in
            var updated = style
            updated[keyPath: key] = value
            model.setAppearance(updated)
        })
    }
}
