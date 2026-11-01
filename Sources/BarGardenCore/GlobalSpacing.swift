import Foundation

public enum GlobalSpacingKeys {
    public static let spacing = "NSStatusItemSpacing"
    public static let padding = "NSStatusItemSelectionPadding"
    public static let all = [spacing, padding]
}

/// Serialized property-list values preserve the original type, including a
/// string value written by another tool. Missing keys remain absent.
public enum PreferenceValueCodec {
    public static func encode(_ value: Any) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: ["value": value], format: .binary, options: 0)
    }

    public static func decode(_ data: Data) throws -> Any {
        guard let wrapper = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let value = wrapper["value"] else { throw GlobalSpacingError.invalidBackup }
        return value
    }
}

public struct GlobalSpacingValues: Equatable, Sendable {
    public var spacing: Int
    public var padding: Int
    public static let range = 0...16

    public init(spacing: Int, padding: Int) { self.spacing = spacing; self.padding = padding }
}

public struct GlobalSpacingSnapshot: Codable, Equatable, Sendable {
    public var originals: [String: Data]
    public init(originals: [String: Data]) { self.originals = originals }
}

@MainActor public protocol GlobalSpacingPreferences: AnyObject {
    func read(_ key: String) throws -> Data?
    func write(_ key: String, value: Data?) throws
    func synchronize() throws
}

@MainActor public protocol GlobalSpacingBackups: AnyObject {
    func load() throws -> GlobalSpacingSnapshot?
    func save(_ snapshot: GlobalSpacingSnapshot) throws
    func remove() throws
}

@MainActor public final class GlobalSpacingFileBackups: GlobalSpacingBackups {
    private let url: URL
    public init(url: URL) { self.url = url }

    public func load() throws -> GlobalSpacingSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(GlobalSpacingSnapshot.self, from: Data(contentsOf: url))
    }

    public func save(_ snapshot: GlobalSpacingSnapshot) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }

    public func remove() throws { try FileManager.default.removeItem(at: url) }
}

public enum GlobalSpacingError: LocalizedError {
    case invalidValue, invalidBackup, noBackup, verification, synchronization
    case failedButReverted(String), rollbackFailed(String), backupCleanup

    public var errorDescription: String? {
        switch self {
        case .invalidValue: "Spacing and padding must be integers from 0–16."
        case .invalidBackup: "The original-values backup cannot be read. No changes were applied."
        case .noBackup: "No original-values backup is available. Settings were not changed."
        case .verification: "The saved values do not match the requested settings."
        case .synchronization: "The system did not confirm the preferences write."
        case .failedButReverted(let reason): "The operation failed; previous values were restored: \(reason)"
        case .rollbackFailed(let reason): "The operation and automatic recovery were not confirmed. Original backup preserved: \(reason)"
        case .backupCleanup: "Original values restored, but backup cleanup failed. Refresh the status later."
        }
    }
}

@MainActor
public final class GlobalSpacingTransaction {
    private let preferences: any GlobalSpacingPreferences
    private let backups: any GlobalSpacingBackups

    public init(preferences: any GlobalSpacingPreferences, backups: any GlobalSpacingBackups) {
        self.preferences = preferences
        self.backups = backups
    }

    public func apply(_ values: GlobalSpacingValues) throws {
        guard GlobalSpacingValues.range.contains(values.spacing), GlobalSpacingValues.range.contains(values.padding) else {
            throw GlobalSpacingError.invalidValue
        }
        let before = try capture()
        if try backups.load() == nil { try backups.save(.init(originals: before)) }
        let desired = [GlobalSpacingKeys.spacing: try PreferenceValueCodec.encode(values.spacing),
                       GlobalSpacingKeys.padding: try PreferenceValueCodec.encode(values.padding)]
        try change(to: desired, revertingTo: before)
    }

    public func restore() throws {
        guard let snapshot = try backups.load() else { throw GlobalSpacingError.noBackup }
        let before = try capture()
        try change(to: snapshot.originals, revertingTo: before)
        do { try backups.remove() } catch { throw GlobalSpacingError.backupCleanup }
    }

    private func capture() throws -> [String: Data] {
        var result: [String: Data] = [:]
        for key in GlobalSpacingKeys.all { result[key] = try preferences.read(key) }
        return result
    }

    private func writeAndVerify(_ values: [String: Data]) throws {
        // The key set is fixed; backup contents cannot widen the write scope.
        for key in GlobalSpacingKeys.all { try preferences.write(key, value: values[key]) }
        try preferences.synchronize()
        for key in GlobalSpacingKeys.all {
            guard try preferences.read(key) == values[key] else { throw GlobalSpacingError.verification }
        }
    }

    private func change(to desired: [String: Data], revertingTo before: [String: Data]) throws {
        do { try writeAndVerify(desired) }
        catch {
            let originalFailure = error.localizedDescription
            do { try writeAndVerify(before) }
            catch { throw GlobalSpacingError.rollbackFailed("\(originalFailure)；\(error.localizedDescription)") }
            throw GlobalSpacingError.failedButReverted(originalFailure)
        }
    }
}
