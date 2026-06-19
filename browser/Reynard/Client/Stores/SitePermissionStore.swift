//
//  SitePermissionStore.swift
//  Reynard
//
//  Created by Minh Ton on 31/5/26.
//

import Foundation
import GeckoView
import SQLite3

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
            return nil
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

final class SitePermissionStore {
    static let shared = SitePermissionStore()
    
    private struct StorageURLs {
        let directoryURL: URL
        let databaseURL: URL
    }
    
    private let fileManager: FileManager
    private let storage: StorageURLs
    private let stateQueue = DispatchQueue(label: "com.minh-ton.Reynard.SitePermissionStore.Queue", qos: .utility)
    private var database: OpaquePointer?
    private var privateActions: [ObjectIdentifier: [String: [SitePermission: SitePermissionAction]]] = [:]
    private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    
    // MARK: - Lifecycle
    
    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        
        guard let applicationSupportDirectoryURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory is unavailable")
        }
        
        let directoryURL = applicationSupportDirectoryURL
            .appendingPathComponent("AppData", isDirectory: true)
            .appendingPathComponent("SitePermissions", isDirectory: true)
        
        self.storage = StorageURLs(
            directoryURL: directoryURL,
            databaseURL: directoryURL.appendingPathComponent("SitePermissions", isDirectory: false)
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
        let host = URLUtils.normalizedHost(host) ?? ""
        return stateQueue.sync {
            let resolvedAction: SitePermissionAction
            if session.isPrivateMode {
                resolvedAction = privateActions[ObjectIdentifier(session)]?[host]?[permission] ?? SiteSettingsUtils.defaultAction(for: permission)
            } else {
                resolvedAction = actionLocked(for: permission, host: host) ?? SiteSettingsUtils.defaultAction(for: permission)
            }
            
            if SiteSettingsUtils.isSystemDisabled(permission) {
                return .blocked
            }
            
            return resolvedAction
        }
    }
    
    func scheduleActionUpdate(_ action: SitePermissionAction, for permission: SitePermission, host: String, session: GeckoSession) {
        let host = URLUtils.normalizedHost(host) ?? ""
        stateQueue.async {
            self.setActionLocked(action, for: permission, host: host, session: session)
        }
    }
    
    func updateAction(_ action: SitePermissionAction, for permission: SitePermission, host: String, session: GeckoSession) {
        let host = URLUtils.normalizedHost(host) ?? ""
        stateQueue.sync {
            self.setActionLocked(action, for: permission, host: host, session: session)
        }
    }
    
    func removeAction(for permission: SitePermission, host: String, session: GeckoSession) {
        let host = URLUtils.normalizedHost(host) ?? ""
        stateQueue.sync {
            if session.isPrivateMode {
                self.removePrivateActionLocked(for: permission, host: host, session: session)
            } else {
                _ = self.deleteActionLocked(for: permission, host: host)
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
    
    func removePersistedAction(for permission: SitePermission, host: String) {
        let host = URLUtils.normalizedHost(host) ?? ""
        stateQueue.sync {
            _ = deleteActionLocked(for: permission, host: host)
        }
    }
    
    // MARK: - Storage
    
    private func prepareStorageLocked() {
        try? fileManager.createDirectory(at: storage.directoryURL, withIntermediateDirectories: true)
    }
    
    private func openDatabaseLocked() {
        guard database == nil else {
            return
        }
        
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(storage.databaseURL.path, &database, flags, nil) == SQLITE_OK else {
            if let database {
                sqlite3_close(database)
            }
            assertionFailure("Failed to open SitePermissions database")
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
    
    private func actionLocked(for permission: SitePermission, host: String) -> SitePermissionAction? {
        guard let statement = prepareStatementLocked(
            """
            SELECT action
            FROM site_permissions
            WHERE host = ? AND permission_key = ?
            LIMIT 1;
            """
        ) else {
            return nil
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        bind(host, to: statement, at: 1)
        bind(permission.rawValue, to: statement, at: 2)
        
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        
        return SitePermissionAction(rawValue: string(from: statement, at: 0))
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
    
    private func setActionLocked(_ action: SitePermissionAction, for permission: SitePermission, host: String, session: GeckoSession) {
        if session.isPrivateMode {
            privateActions[ObjectIdentifier(session), default: [:]][host, default: [:]][permission] = action
        } else {
            _ = upsertActionLocked(action, for: permission, host: host, updatedAt: Date())
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
            assertionFailure("Failed to prepare SitePermissions SQL statement")
            return nil
        }
        
        return statement
    }
    
    private func executeLocked(_ sql: String) -> Bool {
        guard let database else {
            return false
        }
        
        return sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK
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
