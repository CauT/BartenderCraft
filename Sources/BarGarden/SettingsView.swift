import SwiftUI
import BarGardenCore

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "menubar.rectangle").font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white).frame(width: 42, height: 42)
                        .background(CraftBrand.accent, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(CraftBrand.name).font(.system(size: 16, weight: .bold))
                        Text("YOUR MENU BAR, ORGANIZED").font(.system(size: 8, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 20).padding(.top, 25).padding(.bottom, 32)
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        navigationGroup("WORKSPACE", sections: [.layout, .groups, .presets])
                        navigationGroup("CUSTOMIZE", sections: [.appearance, .spacing, .globalSpacing, .widgets])
                        navigationGroup("AUTOMATE", sections: [.rules, .general])
                    }.padding(.horizontal, 12)
                }
                VStack(alignment: .leading, spacing: 10) {
                    CraftBadge(title: model.accessibilityGranted ? "Accessibility connected" : "Setup available", positive: model.accessibilityGranted)
                    Text("Independent Mac utility · \(CraftBrand.version)")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }.padding(20)
            }.frame(width: 240).background(.white)
            Rectangle().fill(CraftBrand.line).frame(width: 1)
            SettingsDetailView(model: model)
        }
        .foregroundStyle(CraftBrand.ink).tint(CraftBrand.accent)
        .groupBoxStyle(CraftCardStyle())
        .preferredColorScheme(.light)
        .frame(minWidth: 960, minHeight: 660)
        .onAppear { model.refresh() }
    }

    private func navigationGroup(_ title: String, sections: [AppSection]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 9, weight: .bold)).tracking(1.3).foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 6)
            ForEach(sections) { section in
                Button { model.section = section } label: {
                    HStack(spacing: 11) {
                        Image(systemName: section.symbol).font(.system(size: 15)).frame(width: 21)
                        Text(section.rawValue).font(.system(size: 13, weight: model.section == section ? .semibold : .regular))
                        Spacer()
                        if model.section == section { RoundedRectangle(cornerRadius: 2).fill(CraftBrand.accent).frame(width: 3, height: 16) }
                    }.foregroundStyle(model.section == section ? CraftBrand.accent : CraftBrand.ink.opacity(0.72))
                        .padding(.horizontal, 13).padding(.vertical, 10)
                        .background(model.section == section ? CraftBrand.accent.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityAddTraits(model.section == section ? .isSelected : [])
            }
        }
    }
}
