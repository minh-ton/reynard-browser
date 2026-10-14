//
//  FxAAccountStorage.swift
//  Reynard
//
//  Persists the signed-in Mozilla account. Tokens and the Sync key are
//  stored in the Keychain; builds that can't use the Keychain (for example
//  unsigned TrollStore builds without keychain entitlements) fall back to a
//  file protected by iOS data protection.
//

import Foundation
import Security

struct FxAScopedKey: Codable, Equatable {
    /// e.g. "1525212342123-mrz...". Sent to the tokenserver as X-KeyID.
    let kid: String
    /// base64url encoded 64 byte kSync.
    let k: String
    let scope: String
}

struct FxAAccountState: Codable, Equatable {
    var uid: String?
    var email: String?
    var displayName: String?
    var refreshToken: String
    var sessionToken: String?
    var syncKey: FxAScopedKey
    var accessToken: String?
    var accessTokenExpiry: Date?
    var deviceID: String?
    /// Our record ID in the Sync `clients` and `tabs` collections.
    var clientRecordID: String
    var signedInAt: Date
}

enum FxAAccountStorage {
    private static let service = "com.minh-ton.Reynard.MozillaAccount"
    private static let account = "default"

    private static var fallbackFileURL: URL? {
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return directory
            .appendingPathComponent("AppData", isDirectory: true)
            .appendingPathComponent("Account", isDirectory: true)
            .appendingPathComponent("account.json", isDirectory: false)
    }

    static func load() -> FxAAccountState? {
        if let data = keychainRead() ?? fileRead() {
            return try? JSONDecoder().decode(FxAAccountState.self, from: data)
        }
        return nil
    }

    static func save(_ state: FxAAccountState) {
        guard let data = try? JSONEncoder().encode(state) else {
            return
        }
        if keychainWrite(data) {
            fileDelete()
        } else {
            fileWrite(data)
        }
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        fileDelete()
    }

    // MARK: - Keychain

    private static func keychainRead() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    private static func keychainWrite(_ data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        guard updateStatus == errSecItemNotFound else {
            NSLog("Reynard Sync: keychain update failed (%d), using file storage", updateStatus)
            return false
        }

        var addQuery = query
        attributes.forEach { addQuery[$0.key] = $0.value }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            NSLog("Reynard Sync: keychain add failed (%d), using file storage", addStatus)
        }
        return addStatus == errSecSuccess
    }

    // MARK: - File fallback

    private static func fileRead() -> Data? {
        guard let url = fallbackFileURL else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    private static func fileWrite(_ data: Data) {
        guard let url = fallbackFileURL else {
            return
        }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private static func fileDelete() {
        guard let url = fallbackFileURL else {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }
}

/// Non-secret Sync preferences and bookkeeping, kept in UserDefaults.
enum SyncPreferences {
    private static let defaults = UserDefaults.standard
    private static let prefix = "default.SyncSettings."

    enum Engine: String, CaseIterable {
        case tabs
        case history
        case bookmarks
    }

    static func isEnabled(_ engine: Engine) -> Bool {
        defaults.object(forKey: prefix + "enabled." + engine.rawValue) as? Bool ?? true
    }

    static func setEnabled(_ enabled: Bool, for engine: Engine) {
        defaults.set(enabled, forKey: prefix + "enabled." + engine.rawValue)
    }

    static var deviceName: String {
        get {
            if let name = defaults.string(forKey: prefix + "deviceName"), !name.isEmpty {
                return name
            }
            return defaultDeviceName
        }
        set {
            defaults.set(newValue, forKey: prefix + "deviceName")
        }
    }

    static var defaultDeviceName: String {
        "Reynard on \(DeviceNameSource.modelName)"
    }

    static var lastSyncDate: Date? {
        get { defaults.object(forKey: prefix + "lastSyncDate") as? Date }
        set { defaults.set(newValue, forKey: prefix + "lastSyncDate") }
    }

    static var lastSyncError: String? {
        get { defaults.string(forKey: prefix + "lastSyncError") }
        set { defaults.set(newValue, forKey: prefix + "lastSyncError") }
    }

    /// Server modified time (seconds, as sent by the server) of the newest record we have seen per collection.
    static func lastModified(_ collection: String) -> Double {
        defaults.double(forKey: prefix + "lastModified." + collection)
    }

    static func setLastModified(_ value: Double, for collection: String) {
        defaults.set(value, forKey: prefix + "lastModified." + collection)
    }

    static var lastHistoryUpload: Date? {
        get { defaults.object(forKey: prefix + "lastHistoryUpload") as? Date }
        set { defaults.set(newValue, forKey: prefix + "lastHistoryUpload") }
    }

    static var globalSyncID: String? {
        get { defaults.string(forKey: prefix + "globalSyncID") }
        set { defaults.set(newValue, forKey: prefix + "globalSyncID") }
    }

    /// Forget per-collection progress (after a server wipe or node reassignment).
    static func resetCollectionTimestamps() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix + "lastModified.") {
            defaults.removeObject(forKey: key)
        }
        defaults.removeObject(forKey: prefix + "lastHistoryUpload")
    }
    
    static func resetBookkeeping() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix + "lastModified.") {
            defaults.removeObject(forKey: key)
        }
        defaults.removeObject(forKey: prefix + "lastHistoryUpload")
        defaults.removeObject(forKey: prefix + "globalSyncID")
        defaults.removeObject(forKey: prefix + "lastSyncDate")
        defaults.removeObject(forKey: prefix + "lastSyncError")
    }
}

enum DeviceNameSource {
    static var modelName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let identifier = withUnsafeBytes(of: &systemInfo.machine) { buffer -> String in
            let bytes = buffer.prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }
        if identifier.hasPrefix("iPad") {
            return "iPad"
        }
        if identifier.hasPrefix("iPod") {
            return "iPod touch"
        }
        return "iPhone"
    }
}
