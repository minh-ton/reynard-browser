//
//  UserDataMigration.swift
//  Reynard
//
//  Created by Minh Ton on 17/5/26.
//

import Foundation

final class UserDataMigration {
    static let shared = UserDataMigration()
    
    private let fileManager: FileManager
    private let documentsDirectoryURL: URL
    private let applicationSupportDirectoryURL: URL
    
    private var documentsAppDataDirectoryURL: URL {
        documentsDirectoryURL.appendingPathComponent("AppData", isDirectory: true)
    }
    
    private var documentsDDIDirectoryURL: URL {
        documentsDirectoryURL.appendingPathComponent("DDI", isDirectory: true)
    }
    
    private var applicationSupportAppDataDirectoryURL: URL {
        applicationSupportDirectoryURL.appendingPathComponent("AppData", isDirectory: true)
    }
    
    private var applicationSupportDDIDirectoryURL: URL {
        applicationSupportDirectoryURL.appendingPathComponent("DDI", isDirectory: true)
    }
    
    private init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        
        guard let documentsDirectoryURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Documents directory is unavailable")
        }
        
        guard let applicationSupportDirectoryURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory is unavailable")
        }
        
        self.documentsDirectoryURL = documentsDirectoryURL
        self.applicationSupportDirectoryURL = applicationSupportDirectoryURL
    }
    
    func run() {
        migrateAppDataToApplicationSupport()
        migrateDDIToApplicationSupport()
        removeLegacyUserAgentOverride()
    }
    
    private func migrateAppDataToApplicationSupport() {
        let sourceURL = documentsAppDataDirectoryURL
        let destinationURL = applicationSupportAppDataDirectoryURL
        
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            return
        }
        
        do {
            try removeLegacyStoreFolders(in: sourceURL)
            try fileManager.createDirectory(at: applicationSupportDirectoryURL, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        } catch {
            fatalError("AppData migration failed")
        }
        
        guard !fileManager.fileExists(atPath: sourceURL.path) else {
            fatalError("AppData migration failed")
        }
    }
    
    private func migrateDDIToApplicationSupport() {
        let sourceURL = documentsDDIDirectoryURL
        let destinationURL = applicationSupportDDIDirectoryURL
        
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            return
        }
        
        do {
            try fileManager.createDirectory(at: applicationSupportDirectoryURL, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        } catch {
            fatalError("DDI migration failed")
        }
        
        guard !fileManager.fileExists(atPath: sourceURL.path) else {
            fatalError("DDI migration failed")
        }
    }
    
    private func removeLegacyUserAgentOverride() {
        try? fileManager.removeItem(
            at: documentsDirectoryURL.appendingPathComponent("ua-override.json", isDirectory: false)
        )
    }
    
    private func removeLegacyStoreFolders(in appDataDirectoryURL: URL) throws {
        for folderName in ["TabManagement", "Favicons"] {
            let folderURL = appDataDirectoryURL.appendingPathComponent(folderName, isDirectory: true)
            if fileManager.fileExists(atPath: folderURL.path) {
                try fileManager.removeItem(at: folderURL)
            }
        }
    }
}
