import Foundation
import CoreFoundation
import BarGardenCore

@MainActor
final class HostSpacingPreferences: GlobalSpacingPreferences {
    private let applicationID: CFString
    init(applicationID: CFString = kCFPreferencesAnyApplication) { self.applicationID = applicationID }

    func read(_ key: String) throws -> Data? {
        guard let value = CFPreferencesCopyValue(key as CFString, applicationID,
            kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) else { return nil }
        return try PreferenceValueCodec.encode(value)
    }

    func write(_ key: String, value: Data?) throws {
        let decoded: CFPropertyList?
        if let value { decoded = try PreferenceValueCodec.decode(value) as AnyObject }
        else { decoded = nil }
        CFPreferencesSetValue(key as CFString, decoded, applicationID,
                              kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }

    func synchronize() throws {
        guard CFPreferencesSynchronize(applicationID, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) else {
            throw GlobalSpacingError.synchronization
        }
    }
}

@MainActor
final class GlobalSpacingController {
    private let preferences = HostSpacingPreferences()
    private let backups: GlobalSpacingFileBackups
    private let transaction: GlobalSpacingTransaction

    init(root: URL) {
        backups = GlobalSpacingFileBackups(url: root.appendingPathComponent("global-spacing-originals.json"))
        transaction = GlobalSpacingTransaction(preferences: preferences, backups: backups)
    }

    func apply(_ values: GlobalSpacingValues) throws { try transaction.apply(values) }
    func restore() throws { try transaction.restore() }

    func status() throws -> (summary: String, hasBackup: Bool) {
        func describe(_ key: String) throws -> String {
            guard let blob = try preferences.read(key) else { return "System default" }
            let value = try PreferenceValueCodec.decode(blob)
            if let number = value as? Int { return String(number) }
            if let text = value as? String, Int(text) != nil { return text }
            return "Custom value"
        }
        return ("Spacing: \(try describe(GlobalSpacingKeys.spacing)) · Padding: \(try describe(GlobalSpacingKeys.padding))",
                try backups.load() != nil)
    }
}
