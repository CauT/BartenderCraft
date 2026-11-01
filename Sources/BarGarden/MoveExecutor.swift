import AppKit
import ApplicationServices
import BarGardenCore

enum MenuMoveError: LocalizedError {
    case permission, busy, missingItem, noGeometry, inputActive, failedVerification
    var errorDescription: String? {
        switch self {
        case .permission: "请先授予栏庭辅助功能权限。"
        case .busy: "正在整理菜单栏，请稍后再试。"
        case .missingItem: "项目已退出或无法再读取，请刷新菜单栏。"
        case .noGeometry: "项目或分隔线当前不在同一个可见菜单栏，无法移动。"
        case .inputActive: "检测到鼠标或键盘正在使用，已取消整理。"
        case .failedVerification: "系统未将项目移到指定区域；该项目可能不可移动。"
        }
    }
}

/// Original implementation using public CGEvent command-drag semantics.
/// A posted event is not treated as proof of movement: callers must verify geometry.
@MainActor
final class MoveExecutor {
    private(set) var isExecuting = false

    func move(from: CGRect, to: CGPoint) async throws {
        guard AXIsProcessTrusted() else { throw MenuMoveError.permission }
        guard !isExecuting else { throw MenuMoveError.busy }
        guard from.width > 0, from.height > 0 else { throw MenuMoveError.noGeometry }
        isExecuting = true
        defer { isExecuting = false }
        for attempt in 0..<12 {
            try Task.checkCancellation()
            let quiet = [CGEventType.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown].allSatisfy {
                CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) > 0.25
            }
            if quiet && !CGEventSource.buttonState(.combinedSessionState, button: .left) && !CGEventSource.buttonState(.combinedSessionState, button: .right) { break }
            if attempt == 11 { throw MenuMoveError.inputActive }
            try await Task.sleep(for: .milliseconds(100))
        }
        let originalPointer = CGEvent(source: nil)?.location
        let source = CGEventSource(stateID: .hidSystemState)
        let origin = CGPoint(x: from.midX, y: from.midY)
        guard let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: origin, mouseButton: .left),
              let dragged = CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: to, mouseButton: .left),
              let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: to, mouseButton: .left) else { throw MenuMoveError.noGeometry }
        for event in [down, dragged, up] {
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: 0x42475244)
        }
        down.post(tap: .cghidEventTap)
        var released = false
        // Always release our mouse-down, including cancellation during the short drag sequence.
        defer {
            if !released { up.post(tap: .cghidEventTap) }
            if let originalPointer {
                CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: originalPointer, mouseButton: .left)?.post(tap: .cghidEventTap)
            }
        }
        try await Task.sleep(for: .milliseconds(60))
        dragged.post(tap: .cghidEventTap)
        try await Task.sleep(for: .milliseconds(60))
        up.post(tap: .cghidEventTap)
        released = true
    }
}
