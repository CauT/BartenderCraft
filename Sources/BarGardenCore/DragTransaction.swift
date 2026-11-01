import Foundation

public enum DragEvent: Equatable, Sendable {
    case down, dragged, up, upAfterInterruption, restorePointer
}

/// The system bridge owns event creation; tests can exercise the same cleanup
/// transaction without posting input or installing an event tap.
@MainActor
public protocol DragTransport: AnyObject {
    var pointer: CGPoint? { get }
    var canRestorePointer: Bool { get }
    func checkInput() throws
    func stopMonitoring()
    func send(_ event: DragEvent, at point: CGPoint)
    func pause(for duration: Duration) async throws
    func verifyReleased() throws
}

@MainActor
public enum DragTransaction {
    public static func run(from origin: CGPoint, to destination: CGPoint, using transport: any DragTransport) async throws {
        var stopped = false
        defer { if !stopped { transport.stopMonitoring() } }
        let originalPointer = transport.pointer
        try Task.checkCancellation()
        try transport.checkInput()
        var failure: (any Error)?
        var verifyRelease = false
        do {
            transport.send(.down, at: origin)
            var lastPosition = origin
            defer {
                let restore = transport.canRestorePointer
                verifyRelease = restore
                // Do not tear down our tap while the final release is queued in it.
                transport.stopMonitoring()
                stopped = true
                transport.send(restore ? .up : .upAfterInterruption,
                    at: restore ? lastPosition : (transport.pointer ?? lastPosition))
                if restore, let originalPointer { transport.send(.restorePointer, at: originalPointer) }
            }
            try await transport.pause(for: .milliseconds(60))
            try Task.checkCancellation()
            try transport.checkInput()
            transport.send(.dragged, at: destination)
            lastPosition = destination
            try await transport.pause(for: .milliseconds(60))
            try Task.checkCancellation()
            try transport.checkInput()
        } catch {
            failure = error
        }
        if verifyRelease {
            // Cleanup must finish even when the caller's task is cancelled.
            // An unstructured task does not inherit that cancellation. Keep
            // release failures ahead of the original cancellation/error.
            try await Task { @MainActor in
                try await transport.pause(for: .milliseconds(50))
                try transport.verifyReleased()
            }.value
        }
        if let failure { throw failure }
    }
}
