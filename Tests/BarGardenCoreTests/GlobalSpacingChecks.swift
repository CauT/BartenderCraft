import Foundation
import BarGardenCore

private enum SpacingTestFailure: Error { case injected }

@MainActor private final class MemorySpacingPreferences: GlobalSpacingPreferences {
    var values: [String: Data]
    var writeCalls = 0
    var failWriteAt: Int?
    var ignoreWriteAt: Int?
    var failedSynchronizations = 0
    var failRead = false

    init(_ values: [String: Data]) { self.values = values }
    func read(_ key: String) throws -> Data? {
        if failRead { throw SpacingTestFailure.injected }
        return values[key]
    }
    func write(_ key: String, value: Data?) throws {
        writeCalls += 1
        if writeCalls == failWriteAt { throw SpacingTestFailure.injected }
        if writeCalls == ignoreWriteAt { return }
        values[key] = value
    }
    func synchronize() throws {
        if failedSynchronizations > 0 { failedSynchronizations -= 1; throw GlobalSpacingError.synchronization }
    }
}

@MainActor private final class MemorySpacingBackups: GlobalSpacingBackups {
    var value: GlobalSpacingSnapshot?
    var failSave = false
    var failRemove = false
    func load() throws -> GlobalSpacingSnapshot? { value }
    func save(_ snapshot: GlobalSpacingSnapshot) throws {
        if failSave { throw SpacingTestFailure.injected }
        value = snapshot
    }
    func remove() throws {
        if failRemove { throw SpacingTestFailure.injected }
        value = nil
    }
}

@MainActor func globalSpacingChecks() throws {
    let spacing = GlobalSpacingKeys.spacing, padding = GlobalSpacingKeys.padding
    let original = [spacing: try PreferenceValueCodec.encode("8")]
    let requested = GlobalSpacingValues(spacing: 2, padding: 0)
    func environment() -> (MemorySpacingPreferences, MemorySpacingBackups, GlobalSpacingTransaction) {
        let preferences = MemorySpacingPreferences(original), backups = MemorySpacingBackups()
        return (preferences, backups, GlobalSpacingTransaction(preferences: preferences, backups: backups))
    }
    let (preferences, backups, transaction) = environment()
    try transaction.apply(requested)
    try expect(try PreferenceValueCodec.decode(preferences.values[spacing]!) as? Int == 2
        && PreferenceValueCodec.decode(preferences.values[padding]!) as? Int == 0 && backups.value?.originals == original,
        "Applying global spacing first saves exact originals, including the absent padding key")
    try transaction.apply(.init(spacing: 4, padding: 4))
    try expect(backups.value?.originals == original, "Switching spacing keeps the first original backup")
    let restarted = GlobalSpacingTransaction(preferences: preferences, backups: backups)
    try restarted.restore()
    try expect(preferences.values == original && backups.value == nil
        && (try PreferenceValueCodec.decode(preferences.values[spacing]!)) is String,
        "Restarted controller restores original value type, removes originally absent key and clears backup")

    let (missing, _, withoutBackup) = environment()
    do { try withoutBackup.restore(); throw CheckFailure.failed("No-backup restore wrote preferences") }
    catch GlobalSpacingError.noBackup { }
    try expect(missing.writeCalls == 0, "Missing backup never guesses a default or deletes current settings")
    for invalid in [-1, 17] {
        let (store, files, operation) = environment()
        do { try operation.apply(.init(spacing: invalid, padding: 2)); throw CheckFailure.failed("Out-of-range spacing accepted") }
        catch GlobalSpacingError.invalidValue { }
        try expect(store.writeCalls == 0 && files.value == nil, "Invalid spacing \(invalid) is rejected before any backup or preference write")
    }
    let (noSave, badFile, saveFailure) = environment()
    badFile.failSave = true
    do { try saveFailure.apply(requested); throw CheckFailure.failed("Missing durable backup accepted") }
    catch SpacingTestFailure.injected { }
    try expect(noSave.writeCalls == 0 && noSave.values == original, "Backup failure prevents all global preference writes")

    let (partial, partialBackup, partialOperation) = environment()
    partial.failWriteAt = 2
    do { try partialOperation.apply(requested); throw CheckFailure.failed("Partial write was success") }
    catch GlobalSpacingError.failedButReverted { }
    try expect(partial.values == original && partialBackup.value?.originals == original,
               "Failure on the second key restores both keys and retains original backup")
    let (unsynced, _, syncOperation) = environment()
    unsynced.failedSynchronizations = 1
    do { try syncOperation.apply(requested); throw CheckFailure.failed("Unsynced write was success") }
    catch GlobalSpacingError.failedButReverted { }
    try expect(unsynced.values == original, "Synchronization failure restores the preceding values")
    let (ignored, _, verificationOperation) = environment()
    ignored.ignoreWriteAt = 2
    do { try verificationOperation.apply(requested); throw CheckFailure.failed("Unverified write was success") }
    catch GlobalSpacingError.failedButReverted { }
    try expect(ignored.values == original, "Readback mismatch rolls back instead of reporting success")
    let (failedRollback, rescueBackup, failedOperation) = environment()
    failedRollback.failWriteAt = 2
    failedRollback.failedSynchronizations = 1
    do { try failedOperation.apply(requested); throw CheckFailure.failed("Failed rollback hidden") }
    catch GlobalSpacingError.rollbackFailed { }
    try expect(rescueBackup.value?.originals == original, "A failed rollback retains the persistent recovery snapshot")

    let (restoreStore, restoreBackup, restoreOperation) = environment()
    try restoreOperation.apply(requested)
    let beforeRestore = restoreStore.values
    restoreStore.failWriteAt = restoreStore.writeCalls + 2
    do { try restoreOperation.restore(); throw CheckFailure.failed("Partial restore was success") }
    catch GlobalSpacingError.failedButReverted { }
    try expect(restoreStore.values == beforeRestore && restoreBackup.value?.originals == original,
               "Partial restore rolls back to the current applied state and keeps original backup")
    let (cleanupStore, cleanupBackup, cleanupOperation) = environment()
    try cleanupOperation.apply(requested)
    cleanupBackup.failRemove = true
    do { try cleanupOperation.restore(); throw CheckFailure.failed("Backup cleanup failure hidden") }
    catch GlobalSpacingError.backupCleanup { }
    try expect(cleanupStore.values == original && cleanupBackup.value != nil,
               "Backup cleanup failure reports the already-restored settings without losing the snapshot")
    let (unreadable, noReadBackup, readOperation) = environment()
    unreadable.failRead = true
    do { try readOperation.apply(requested); throw CheckFailure.failed("Unreadable original accepted") }
    catch SpacingTestFailure.injected { }
    try expect(unreadable.writeCalls == 0 && noReadBackup.value == nil, "Unreadable original settings are preserved untouched")

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("originals.json")
    let filePreferences = MemorySpacingPreferences(original)
    let fileOperation = GlobalSpacingTransaction(preferences: filePreferences, backups: GlobalSpacingFileBackups(url: url))
    try fileOperation.apply(requested)
    let reloadedBackup = GlobalSpacingFileBackups(url: url)
    let savedOriginals = try reloadedBackup.load()?.originals
    try GlobalSpacingTransaction(preferences: filePreferences, backups: reloadedBackup).restore()
    try expect(savedOriginals == original && filePreferences.values == original && (try reloadedBackup.load()) == nil,
               "Original backup survives actual file storage, reload and restore through a fresh controller")
}
