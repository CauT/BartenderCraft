import SwiftUI

struct QuickBarView: View {
    @ObservedObject var model: AppModel
    let activate: (IndexedMenuItem) -> Void
    @FocusState private var focused: Bool

    private var accent: Color {
        switch model.activeGroup?.appearance {
        case .blue: .blue
        case .purple: .purple
        default: CraftBrand.accent
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: model.activeGroup?.symbol ?? "menubar.rectangle").foregroundStyle(accent)
                Text(model.activeGroup?.title ?? "Quick Access").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(CraftBrand.name).font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 14)
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.system(size: 19)).foregroundStyle(accent)
                TextField("Find an item or application…", text: $model.query)
                    .font(.system(size: 18)).textFieldStyle(.plain).focused($focused)
                    .onSubmit { if let item = model.quickBarItems.first { activate(item) } }
                if !model.query.isEmpty {
                    Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain).help("Clear search")
                }
            }.padding(17).background(.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.25), lineWidth: 1))
                .padding(.horizontal, 18)
            if !model.accessibilityGranted {
                VStack(spacing: 0) {
                    CraftEmptyState(title: "Your menu bar, one search away", detail: "Connect Accessibility to find and open menu bar items. No permission is requested until you choose to continue.", symbol: "magnifyingglass")
                    Button("Open System Settings") { model.requestAccessibility() }.buttonStyle(.borderedProminent)
                }.padding(.bottom, 24)
            } else if model.quickBarItems.isEmpty {
                CraftEmptyState(title: "No matching items", detail: model.activeGroup == nil ? "Try a different name or refresh the menu bar." : "Add members in Groups. Unavailable members return when their apps are running.", symbol: "menubar.rectangle")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(model.quickBarItems) { item in
                            Button { activate(item) } label: {
                                HStack(spacing: 11) {
                                    if let image = model.itemPreviews[item.id] ?? item.icon { Image(nsImage: image).resizable().scaledToFit().frame(width: 30, height: 30) }
                                    else { Image(systemName: "menubar.rectangle").frame(width: 30, height: 30).foregroundStyle(accent) }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                        Text(item.appName).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "arrow.up.right").font(.system(size: 9)).foregroundStyle(.tertiary)
                                }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.white, in: RoundedRectangle(cornerRadius: 11))
                                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(CraftBrand.line, lineWidth: 1))
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain).help("Open \(item.title)")
                        }
                    }.padding(18)
                }.frame(maxHeight: 330)
            }
            Divider()
            HStack {
                Text(model.accessibilityGranted ? "\(model.quickBarItems.count) available · Return opens first result" : "⌃⌥Space opens Quick Access")
                Spacer()
                Button("Refresh") { model.refresh() }.buttonStyle(.plain).foregroundStyle(accent)
            }.font(.system(size: 10)).foregroundStyle(.secondary).padding(16)
            if model.unavailableGroupMemberCount > 0 {
                Text("\(model.unavailableGroupMemberCount) members are unavailable. Their group membership is preserved.").font(.caption).foregroundStyle(.secondary).padding([.horizontal, .bottom], 16)
            }
            if let notice = model.menuReadNotice { Text(notice).font(.caption).foregroundStyle(.secondary).padding([.horizontal, .bottom], 16) }
        }.frame(width: 610).background(CraftBrand.canvas).foregroundStyle(CraftBrand.ink).tint(accent)
            .preferredColorScheme(.light).onAppear { focused = true }
    }
}
