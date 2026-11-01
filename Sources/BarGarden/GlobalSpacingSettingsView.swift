import SwiftUI
import BarGardenCore

struct GlobalSpacingSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var spacing = 6
    @State private var padding = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            CraftSectionIntro(title: "System-wide rhythm", detail: "These settings affect all menu bar applications. Preview the spacing first, then explicitly apply when ready.", symbol: "arrow.left.and.right")
            HStack {
                Text("Preview").font(.caption).foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: CGFloat(spacing)) {
                    ForEach(["wifi", "battery.75percent", "speaker.wave.2", "clock"], id: \.self) { symbol in
                        Image(systemName: symbol).font(.system(size: 16)).padding(.horizontal, CGFloat(padding)).frame(height: 36)
                            .background(CraftBrand.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                Spacer()
            }.padding(20).background(.white, in: RoundedRectangle(cornerRadius: 14))
            GroupBox {
            VStack(alignment: .leading, spacing: 20) {
                Text("Current system settings").font(.headline)
                Text(model.globalSpacingSummary).font(.callout).foregroundStyle(.secondary)
                Text("Affects every app's menu bar icons. Some apps need to be restarted. Changes persist; the original values are saved for restoration.")
                    .font(.callout).foregroundStyle(.secondary)
                Divider()
                Stepper("Icon spacing: \(spacing)", value: $spacing, in: GlobalSpacingValues.range)
                Stepper("Item padding: \(padding)", value: $padding, in: GlobalSpacingValues.range)
                HStack {
                    Button("Back up & apply") { model.applyGlobalSpacing(.init(spacing: spacing, padding: padding)) }
                        .buttonStyle(.borderedProminent)
                    Button("Restore original values") { model.restoreGlobalSpacing() }.disabled(!model.hasGlobalSpacingBackup)
                    Spacer()
                    Button("Read again") { model.refreshGlobalSpacing() }
                }
                Text(model.hasGlobalSpacingBackup ? "The original backup is available. Further adjustments preserve the values from before your first change." : "Before your first change, the original values are saved, including values that were unset.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(12)
        }
        }.disabled(model.isArranging)
            .onAppear { model.refreshGlobalSpacing() }
    }
}
