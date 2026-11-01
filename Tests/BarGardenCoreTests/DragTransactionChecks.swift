import Foundation
import CoreGraphics
import BarGardenCore

private enum DragCheckError: Error { case input, unavailable, heldButton }
private enum RecordedDragAction: Equatable {
    case event(DragEvent, CGPoint)
    case stop
}

@MainActor
private final class RecordingDragTransport: DragTransport {
    var pointer: CGPoint? = CGPoint(x: 40, y: 50)
    var canRestorePointer = true
    var actions: [RecordedDragAction] = []
    var interruptAt: Int?
    var cancelAt: Int?
    var cancelCurrentTaskAt: Int?
    var loseMonitorAt: Int?
    var initiallyUnavailable = false
    var released = true
    var releaseChecked = false
    var verificationTaskWasCancelled = false
    private var pauses = 0
    private var lostMonitor = false

    func checkInput() throws {
        if initiallyUnavailable || lostMonitor { throw DragCheckError.unavailable }
        if !canRestorePointer { throw DragCheckError.input }
    }
    func stopMonitoring() { actions.append(.stop) }
    func send(_ event: DragEvent, at point: CGPoint) { actions.append(.event(event, point)) }
    func pause(for duration: Duration) async throws {
        pauses += 1
        if pauses == cancelCurrentTaskAt { withUnsafeCurrentTask { $0?.cancel() } }
        try Task.checkCancellation()
        if pauses == cancelAt { throw CancellationError() }
        if pauses == interruptAt || pauses == loseMonitorAt {
            canRestorePointer = false
            pointer = CGPoint(x: 900, y: 700)
            lostMonitor = pauses == loseMonitorAt
        }
    }
    func verifyReleased() throws {
        releaseChecked = true
        verificationTaskWasCancelled = Task.isCancelled
        if !released { throw DragCheckError.heldButton }
    }
}

@MainActor func dragTransactionChecks() async throws {
    let origin = CGPoint(x: 10, y: 20)
    let destination = CGPoint(x: 200, y: 20)
    let originalPointer = CGPoint(x: 40, y: 50)
    let userPointer = CGPoint(x: 900, y: 700)
    func run(_ transport: RecordingDragTransport) async throws {
        try await DragTransaction.run(from: origin, to: destination, using: transport)
    }

    let normal = RecordingDragTransport()
    try await run(normal)
    try expect(normal.actions == [.event(.down, origin), .event(.dragged, destination), .stop,
        .event(.up, destination), .event(.restorePointer, originalPointer)] && normal.releaseChecked,
        "Normal drag stops its tap before release, restores pointer and confirms button release")

    let unavailable = RecordingDragTransport()
    unavailable.initiallyUnavailable = true
    do { try await run(unavailable); throw CheckFailure.failed("Unavailable monitor accepted a drag") }
    catch DragCheckError.unavailable { }
    try expect(unavailable.actions == [.stop], "Unavailable input monitor posts no mouse-down")

    for step in [1, 2] {
        let interrupted = RecordingDragTransport()
        interrupted.interruptAt = step
        do { try await run(interrupted); throw CheckFailure.failed("User input did not abort drag") }
        catch DragCheckError.input { }
        var expected: [RecordedDragAction] = [.event(.down, origin)]
        if step == 2 { expected.append(.event(.dragged, destination)) }
        expected += [.stop, .event(.upAfterInterruption, userPointer)]
        try expect(interrupted.actions == expected && !interrupted.releaseChecked,
                   "Input during phase \(step) stops remaining work and releases at user's pointer without restoring")

        let cancelled = RecordingDragTransport()
        cancelled.cancelAt = step
        do { try await run(cancelled); throw CheckFailure.failed("Cancellation did not propagate") }
        catch is CancellationError { }
        expected = [.event(.down, origin)]
        if step == 2 { expected.append(.event(.dragged, destination)) }
        expected += [.stop, .event(.up, step == 1 ? origin : destination), .event(.restorePointer, originalPointer)]
        try expect(cancelled.actions == expected && cancelled.releaseChecked,
                   "Cancellation during phase \(step) balances mouse-down exactly once and verifies release")
    }

    let lost = RecordingDragTransport()
    lost.loseMonitorAt = 1
    do { try await run(lost); throw CheckFailure.failed("Lost monitor did not abort drag") }
    catch DragCheckError.unavailable { }
    try expect(lost.actions == [.event(.down, origin), .stop, .event(.upAfterInterruption, userPointer)],
               "Losing the monitor prevents further drag and pointer restoration")

    let held = RecordingDragTransport()
    held.released = false
    do { try await run(held); throw CheckFailure.failed("Held button was reported as success") }
    catch DragCheckError.heldButton { }
    try expect(held.releaseChecked && held.actions == normal.actions,
               "Posting mouse-up does not bypass the independent release check")

    let actuallyCancelled = RecordingDragTransport()
    actuallyCancelled.cancelCurrentTaskAt = 2
    let duringDrag = Task { @MainActor in try await run(actuallyCancelled) }
    do { try await duringDrag.value; throw CheckFailure.failed("Real task cancellation did not propagate") }
    catch is CancellationError { }
    try expect(actuallyCancelled.actions == normal.actions && actuallyCancelled.releaseChecked
        && !actuallyCancelled.verificationTaskWasCancelled,
        "Real task cancellation still waits for and verifies release in uncancelled cleanup")

    let cancelledHeld = RecordingDragTransport()
    cancelledHeld.cancelCurrentTaskAt = 1
    cancelledHeld.released = false
    let failedCleanup = Task { @MainActor in try await run(cancelledHeld) }
    do { try await failedCleanup.value; throw CheckFailure.failed("Cancelled drag hid its release failure") }
    catch DragCheckError.heldButton { }
    try expect(cancelledHeld.releaseChecked && !cancelledHeld.verificationTaskWasCancelled,
               "A held button after cancellation reports release failure ahead of cancellation")

    let beforeStart = RecordingDragTransport()
    let task = Task { @MainActor in try await run(beforeStart) }
    task.cancel()
    do { try await task.value; throw CheckFailure.failed("Already-cancelled task posted input") }
    catch is CancellationError { }
    try expect(beforeStart.actions == [.stop], "Cancellation before start removes monitor without posting input")
}
