//
//  SitePermissionStore.swift
//  Reynard
//
//  Created by Minh Ton on 31/5/26.
//

import Foundation
import GeckoView
import SQLite3
import os

enum SitePermission: String, CaseIterable {
    case camera = "camera"
    case microphone = "microphone"
    case location = "geolocation"
    case notification = "desktop-notification"
    case persistentStorage = "persistent-storage"
    case crossOriginStorageAccess = "storage-access"
    case mediaKeySystemAccess = "media-key-system-access"
    case localDeviceAccess = "loopback-network"
    case localNetworkAccess = "local-network"
    case deviceSensors = "device-sensors"
    case autoplay = "autoplay-media"
    
    init?(contentPermission permission: ContentPermission) {
        guard let contentPermission = permission.permission else {
            return nil
        }
        
        switch contentPermission {
        case .camera:
            self = .camera
        case .microphone:
            self = .microphone
        case .geolocation:
            self = .location
        case .desktopNotification:
            self = .notification
        case .persistentStorage:
            self = .persistentStorage
        case .storageAccess:
            self = .crossOriginStorageAccess
        case .mediaKeySystemAccess:
            self = .mediaKeySystemAccess
        case .localDeviceAccess:
            self = .localDeviceAccess
        case .localNetworkAccess:
            self = .localNetworkAccess
        case .deviceSensors:
            self = .deviceSensors
        case .autoplay:
            self = .autoplay
        case .webxr:
            return nil
        case .tracking:
            return nil
        }
    }
}

enum SitePermissionAction: String {
    case blocked = "blocked"
    case askToAllow = "ask_to_allow"
    case allowed = "allowed"
    
    init?(value: ContentPermission.Value) {
        switch value {
        case .allow:
            self = .allowed
        case .prompt:
            self = .askToAllow
        case .deny:
            self = .blocked
        case .blockAll:
            self = .blocked
        }
    }
    
    init?(autoplayValue: Int32) {
        switch autoplayValue {
        case ContentPermission.Value.allow.rawValue:
            self = .allowed
        case ContentPermission.Value.deny.rawValue:
            self = .askToAllow
        case ContentPermission.Value.blockAll.rawValue:
            self = .blocked
        default:
            return nil
        }
    }
    
    var contentPermissionValue: ContentPermission.Value {
        switch self {
        case .blocked:
            return .deny
        case .askToAllow:
            return .prompt
        case .allowed:
            return .allow
        }
    }
    
    var autoplayValue: Int32 {
        switch self {
        case .allowed:
            return ContentPermission.Value.allow.rawValue
        case .askToAllow:
            return ContentPermission.Value.deny.rawValue
        case .blocked:
            return ContentPermission.Value.blockAll.rawValue
        }
    }
}

struct SitePermissionResolution {
    enum Source: Equatable {
        case persisted
        case privateSession
        case defaultValue
        case systemDisabled
        case storageFailure
        case invalidHost
    }

    let action: SitePermissionAction
    let source: Source
}

final class SitePermissionStore {
    private static let log = OSLog(subsystem: "com.minh-ton.Reynard", category: "SitePermissions")
    private enum ActionLookup {
        case found(SitePermissionAction)
        case missing
        case failure
    }

    static let shared = SitePermissionStore()
    
    private struct StorageURLs {
        let directoryURL: URL
        let databaseURL: URL
        let isInMemory: Bool
    }
    
    private let fileManager: FileManager
    private let storage: StorageURLs
    private let stateQueue = DispatchQueue(label: "com.minh-ton.Reynard.SitePermissionStore.Queue", qos: .utility)
    private var database: OpaquePointer?
    private var privateActions: [ObjectIdentifier: [String: [SitePermission: SitePermissionAction]]] = [:]
    private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    
    // MARK: - Lifecycle
    
    init(
        fileManager: FileManager = .default,
        storageDirectoryURL: URL? = nil,
        directories: ReynardDirectories = .shared
    ) {
        self.fileManager = fileManager
        let applicationSupportDirectoryURL = storageDirectoryURL ?? directories.applicationSupport
        let directoryURL = applicationSupportDirectoryURL
            .appendingPathComponent("AppData", isDirectory: true)
            .appendingPathComponent("SitePermissions", isDirectory: true)
        
        self.storage = StorageURLs(
            directoryURL: directoryURL,
            databaseURL: directoryURL.appendingPathComponent("SitePermissions", isDirectory: false),
            isInMemory: false
        )
        
        stateQueue.sync {
            prepareStorageLocked()
            openDatabaseLocked()
            configureDatabaseLocked()
            createSchemaLocked()
        }
    }
    
    deinit {
        stateQueue.sync {
            guard let database else {
                return
            }
            
            sqlite3_close(database)
            self.database = nil
        }
    }
    
    // MARK: - Permissions
    
    func resolvedAction(for permission: SitePermission, host: String, session: GeckoSession) -> SitePermissionAction {
        resolution(for: permission, host: host, session: session).action
    }

    func resolution(
        for permission: SitePermission,
        host: String,
        session: GeckoSession
    ) -> SitePermissionResolution {
        guard let host = URLUtils.normalizedHost(host) else {
            return SitePermissionResolution(
                action: SiteSettingsUtils.defaultAction(for: permission),
                source: .invalidHost
            )
        }
        return stateQueue.sync {
            if SiteSettingsUtils.isSystemDisabled(permission) {
                return SitePermissionResolution(action: .blocked, source: .systemDisabled)
            }
            if SitePermissionDecisionPolicy.storageScope(isPrivate: session.isPrivateMode) == .sessionOnly {
                if let action = privateActions[ObjectIdentifier(session)]?[host]?[permission] {
                    return SitePermissionResolution(action: action, source: .privateSession)
                }
                return SitePermissionResolution(
                    action: SiteSettingsUtils.defaultAction(for: permission),
                    source: .defaultValue
                )
            }
            switch actionLocked(for: permission, host: host) {
            case let .found(action):
                return SitePermissionResolution(action: action, source: .persisted)
            case .missing:
                return SitePermissionResolution(
                    action: SiteSettingsUtils.defaultAction(for: permission),
                    source: .defaultValue
                )
            case .failure:
                return SitePermissionResolution(
                    action: SiteSettingsUtils.defaultAction(for: permission),
                    source: .storageFailure
                )
            }
        }
    }

    @discardableResult
    func updateAction(_ action: SitePermissionAction, for permission: SitePermission, host: String, session: GeckoSession) -> Bool {
        guard let host = URLUtils.normalizedHost(host) else {
            return false
        }
        return stateQueue.sync {
            self.setActionLocked(action, for: permission, host: host, session: session)
        }
    }
    
    @discardableResult
    func removeAction(for permission: SitePermission, host: String, session: GeckoSession) -> Bool {
        guard let host = URLUtils.normalizedHost(host) else {
            return false
        }
        return stateQueue.sync {
            if session.isPrivateMode {
                self.removePrivateActionLocked(for: permission, host: host, session: session)
                return true
            } else {
                return self.deleteActionLocked(for: permission, host: host)
            }
        }
    }
    
    func removePrivateActions(for session: GeckoSession) {
        guard session.isPrivateMode else {
            return
        }
        
        stateQueue.sync {
            privateActions[ObjectIdentifier(session)] = nil
        }
    }
    
    func storedHosts(for permission: SitePermission, action: SitePermissionAction) -> [(host: String, updatedAt: Date)] {
        return stateQueue.sync {
            hostsLocked(for: permission, action: action)
        }
    }
    
    @discardableResult
    func removePersistedAction(for permission: SitePermission, host: String) -> Bool {
        guard let host = URLUtils.normalizedHost(host) else {
            return false
        }
        return stateQueue.sync {
            deleteActionLocked(for: permission, host: host)
        }
    }
    
    // MARK: - Storage
    
    private func prepareStorageLocked() {
        guard !storage.isInMemory else {
            return
        }
        do {
            try fileManager.createDirectory(at: storage.directoryURL, withIntermediateDirectories: true)
        } catch {
            os_log(
                "Unable to create the site permissions directory: %{public}@",
                log: Self.log,
                type: .error,
                error.localizedDescription
            )
            return
        }
    }
    
    private func openDatabaseLocked() {
        guard database == nil else {
            return
        }
        
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let databasePath = storage.isInMemory ? ":memory:" : storage.databaseURL.path
        guard sqlite3_open_v2(databasePath, &database, flags, nil) == SQLITE_OK else {
            if let database {
                sqlite3_close(database)
            }
            os_log("Failed to open the site permissions database", log: Self.log, type: .error)
            return
        }
        
        self.database = database
    }
    
    private func configureDatabaseLocked() {
        guard database != nil else {
            return
        }
        
        _ = executeLocked("PRAGMA foreign_keys = ON;")
        _ = executeLocked("PRAGMA journal_mode = WAL;")
        _ = executeLocked("PRAGMA synchronous = NORMAL;")
        _ = executeLocked("PRAGMA temp_store = MEMORY;")
        sqlite3_busy_timeout(database, 2_500)
    }
    
    private func createSchemaLocked() {
        let sql = """
        CREATE TABLE IF NOT EXISTS site_permissions (
            host TEXT NOT NULL,
            permission_key TEXT NOT NULL,
            action TEXT NOT NULL,
            updated_at REAL NOT NULL,
            PRIMARY KEY(host, permission_key)
        );
        
        CREATE INDEX IF NOT EXISTS idx_site_permissions_permission_key ON site_permissions(permission_key);
        CREATE INDEX IF NOT EXISTS idx_site_permissions_updated_at ON site_permissions(updated_at);
        """
        
        _ = executeLocked(sql)
    }
    
    // MARK: - Permission Records
    
    private func actionLocked(for permission: SitePermission, host: String) -> ActionLookup {
        guard let statement = prepareStatementLocked(
            """
            SELECT action
            FROM site_permissions
            WHERE host = ? AND permission_key = ?
            LIMIT 1;
            """
        ) else {
            return .failure
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(host, to: statement, at: 1)
        bind(permission.rawValue, to: statement, at: 2)
        
        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW else {
            return result == SQLITE_DONE ? .missing : .failure
        }
        guard let action = SitePermissionAction(rawValue: string(from: statement, at: 0)) else {
            return .failure
        }
        return .found(action)
    }
    
    private func upsertActionLocked(_ action: SitePermissionAction, for permission: SitePermission, host: String, updatedAt: Date) -> Bool {
        guard let statement = prepareStatementLocked(
            """
            INSERT INTO site_permissions (host, permission_key, action, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(host, permission_key) DO UPDATE SET
                action = excluded.action,
                updated_at = excluded.updated_at;
            """
        ) else {
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(host, to: statement, at: 1)
        bind(permission.rawValue, to: statement, at: 2)
        bind(action.rawValue, to: statement, at: 3)
        sqlite3_bind_double(statement, 4, updatedAt.timeIntervalSince1970)
        return sqlite3_step(statement) == SQLITE_DONE
    }
    
    private func setActionLocked(_ action: SitePermissionAction, for permission: SitePermission, host: String, session: GeckoSession) -> Bool {
        if SitePermissionDecisionPolicy.storageScope(isPrivate: session.isPrivateMode) == .sessionOnly {
            privateActions[ObjectIdentifier(session), default: [:]][host, default: [:]][permission] = action
            return true
        } else {
            return upsertActionLocked(action, for: permission, host: host, updatedAt: Date())
        }
    }
    
    private func removePrivateActionLocked(for permission: SitePermission, host: String, session: GeckoSession) {
        let key = ObjectIdentifier(session)
        privateActions[key]?[host]?[permission] = nil
        if privateActions[key]?[host]?.isEmpty == true {
            privateActions[key]?[host] = nil
        }
        if privateActions[key]?.isEmpty == true {
            privateActions[key] = nil
        }
    }
    
    private func deleteActionLocked(for permission: SitePermission, host: String) -> Bool {
        guard let statement = prepareStatementLocked(
            """
            DELETE FROM site_permissions
            WHERE host = ? AND permission_key = ?;
            """
        ) else {
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(host, to: statement, at: 1)
        bind(permission.rawValue, to: statement, at: 2)
        return sqlite3_step(statement) == SQLITE_DONE
    }
    
    private func hostsLocked(for permission: SitePermission, action: SitePermissionAction) -> [(host: String, updatedAt: Date)] {
        guard let statement = prepareStatementLocked(
            """
            SELECT host, updated_at
            FROM site_permissions
            WHERE permission_key = ? AND action = ?
            ORDER BY host COLLATE NOCASE ASC;
            """
        ) else {
            return []
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(permission.rawValue, to: statement, at: 1)
        bind(action.rawValue, to: statement, at: 2)
        
        var entries: [(host: String, updatedAt: Date)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let host = string(from: statement, at: 0)
            let timestamp = sqlite3_column_double(statement, 1)
            if !host.isEmpty {
                entries.append((host: host, updatedAt: Date(timeIntervalSince1970: timestamp)))
            }
        }
        return entries
    }
    
    // MARK: - SQLite
    
    private func prepareStatementLocked(_ sql: String) -> OpaquePointer? {
        guard let database else {
            return nil
        }
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            os_log(
                "Failed to prepare a site permissions database operation",
                log: Self.log,
                type: .error
            )
            return nil
        }
        
        return statement
    }
    
    private func executeLocked(_ sql: String) -> Bool {
        guard let database else {
            return false
        }

        let result = sqlite3_exec(database, sql, nil, nil, nil)
        if result != SQLITE_OK {
            os_log(
                "A site permissions database operation failed with code %{public}d",
                log: Self.log,
                type: .error,
                result
            )
        }
        return result == SQLITE_OK
    }
    
    private func bind(_ text: String, to statement: OpaquePointer, at index: Int32) {
        sqlite3_bind_text(statement, index, text, -1, sqliteTransient)
    }
    
    private func string(from statement: OpaquePointer, at index: Int32) -> String {
        guard let cString = sqlite3_column_text(statement, index) else {
            return ""
        }
        
        return String(cString: cString)
    }
}
