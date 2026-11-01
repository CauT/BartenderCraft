import SwiftUI

/// Display branding is deliberately separate from durable storage and bundle identity.
enum CraftBrand {
    static let name = "BartenderCraft"
    static let version = "0.2.0"
    static let ink = Color(red: 0.10, green: 0.16, blue: 0.25)
    static let accent = Color(red: 0.04, green: 0.52, blue: 0.58)
    static let canvas = Color(red: 0.96, green: 0.97, blue: 0.98)
    static let line = Color(red: 0.86, green: 0.90, blue: 0.92)
}

struct CraftCardStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            configuration.label
            configuration.content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(CraftBrand.line, lineWidth: 1))
    }
}

struct CraftBadge: View {
    let title: String
    var positive = true
    var body: some View {
        Label(title, systemImage: positive ? "checkmark.circle.fill" : "circle.dashed")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(positive ? CraftBrand.accent : CraftBrand.ink.opacity(0.65))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background((positive ? CraftBrand.accent : .gray).opacity(0.08), in: Capsule())
    }
}

struct CraftSectionIntro: View {
    let title: String
    let detail: String
    let symbol: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 20, weight: .medium))
                .foregroundStyle(CraftBrand.accent).frame(width: 44, height: 44)
                .background(CraftBrand.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(CraftBrand.ink)
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(CraftBrand.line, lineWidth: 1))
    }
}

struct CraftEmptyState: View {
    let title: String
    let detail: String
    let symbol: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 28, weight: .light))
                .foregroundStyle(CraftBrand.accent).frame(width: 64, height: 64)
                .background(CraftBrand.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
            Text(title).font(.system(size: 17, weight: .semibold))
            Text(detail).font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 390)
        }.padding(32).frame(minWidth: 0, maxWidth: .infinity, alignment: .center)
    }
}

/// Translate owned move failures at the presentation boundary without modifying
/// the existing movement implementation or its in-progress local changes.
func craftErrorDescription(_ error: Error) -> String {
    guard let move = error as? MenuMoveError else { return error.localizedDescription }
    if case .permission = move { return "Connect Accessibility in System Settings before arranging items." }
    if case .busy = move { return "The menu bar is being arranged. Try again shortly." }
    if case .missingItem = move { return "This item is no longer available. Refresh the menu bar." }
    if case .noGeometry = move { return "The item and divider must be on the same visible menu bar." }
    if case .inputActive = move { return "Arrangement cancelled because the mouse or keyboard is in use." }
    if case .failedVerification = move { return "The system did not move this item to the requested section. It may not support moving." }
    return "Arrangement stopped. Check Accessibility and release any held mouse button before trying again."

}
