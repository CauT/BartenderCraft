import SwiftUI
import BarGardenCore

struct GroupSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var newTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            CraftSectionIntro(title: "Collections for your daily tools", detail: "Build a group, choose its members and reorder them. Each group gets its own menu bar shortcut.", symbol: "square.grid.2x2")
            HStack {
                TextField("New group name", text: $newTitle).textFieldStyle(.roundedBorder)
                    .onSubmit { addGroup() }
                Button("Create group") { addGroup() }.buttonStyle(.borderedProminent)
                    .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("Each group gets a menu bar shortcut. An item belongs to one group at a time; moving it between groups keeps its visibility section unchanged.")
                .font(.callout).foregroundStyle(.secondary)
            if model.configuration.groups.isEmpty {
                ContentUnavailableView("Bring your tools together", systemImage: "folder", description: Text("Create a group such as Work, then add frequently used menu bar items."))
            }
            ForEach(model.configuration.groups) { group in
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: group.symbol).foregroundStyle(.teal)
                            TextField("Group name", text: binding(group, \.title)).textFieldStyle(.roundedBorder)
                            Toggle("Show in menu bar", isOn: binding(group, \.enabled)).toggleStyle(.switch)
                            Button(role: .destructive) { model.removeGroup(group.id) } label: {
                                Image(systemName: "trash")
                            }.help("Delete this group; keep its original menu bar items")
                        }
                        HStack {
                            Picker("Icon", selection: binding(group, \.symbol)) {
                                Label("Folder", systemImage: "folder").tag("folder")
                                Label("Star", systemImage: "star").tag("star")
                                Label("Tools", systemImage: "wrench.and.screwdriver").tag("wrench.and.screwdriver")
                                Label("Grid", systemImage: "square.grid.2x2").tag("square.grid.2x2")
                            }
                            Picker("Quick Access color", selection: binding(group, \.appearance)) {
                                Text("Teal").tag(GroupAppearance.teal)
                                Text("Blue").tag(GroupAppearance.blue)
                                Text("Purple").tag(GroupAppearance.purple)
                            }
                        }
                        if !group.memberIDs.isEmpty {
                            Text("Member order").font(.headline)
                            ForEach(Array(group.memberIDs.enumerated()), id: \.element) { index, id in
                                HStack {
                                    Text(model.items.first { $0.id == id }?.title ?? "Member unavailable or not running")
                                        .lineLimit(1).help(id)
                                    Spacer()
                                    Button { model.moveGroupMember(id, in: group.id, by: -1) } label: { Image(systemName: "chevron.up") }
                                        .disabled(index == 0).help("Move earlier")
                                    Button { model.moveGroupMember(id, in: group.id, by: 1) } label: { Image(systemName: "chevron.down") }
                                        .disabled(index == group.memberIDs.count - 1).help("Move later")
                                    Button("Remove") { model.assignItem(id, toGroup: nil) }
                                }
                            }
                        }
                        Divider()
                        Text("Choose menu bar items").font(.headline)
                        if !model.accessibilityGranted {
                            Text("Connect Accessibility and refresh to choose actual menu bar items.").foregroundStyle(.secondary)
                            Button("Open System Settings") { model.requestAccessibility() }
                        } else if model.items.isEmpty {
                            Text("No items detected. Expand the menu bar and refresh.").foregroundStyle(.secondary)
                        }
                        ForEach(model.items) { item in
                            Toggle(isOn: Binding(get: { group.memberIDs.contains(item.id) }, set: { selected in
                                model.assignItem(item.id, toGroup: selected ? group.id : nil)
                            })) {
                                HStack {
                                    Text(item.title).lineLimit(1)
                                    Text(item.appName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    if let owner = model.configuration.groups.first(where: { $0.id != group.id && $0.memberIDs.contains(item.id) }) {
                                        Text("From \(owner.title)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }.padding(12)
                }
            }
        }.disabled(model.isArranging)
    }

    private func addGroup() {
        model.addGroup(title: newTitle)
        newTitle = ""
    }

    private func binding<Value>(_ group: MenuBarGroup, _ key: WritableKeyPath<MenuBarGroup, Value>) -> Binding<Value> {
        Binding(get: { group[keyPath: key] }, set: { value in
            guard var current = model.configuration.groups.first(where: { $0.id == group.id }) else { return }
            current[keyPath: key] = value
            model.updateGroup(current)
        })
    }
}
