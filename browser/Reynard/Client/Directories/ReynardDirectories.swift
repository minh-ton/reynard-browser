//
//  ReynardDirectories.swift
//  Reynard
//

import Foundation

struct ReynardDirectories {
    let applicationSupport: URL
    let caches: URL
    let documents: URL
    let temporary: URL

    var downloads: URL {
        documents.appendingPathComponent("Downloads", isDirectory: true)
    }

    var appData: URL {
        applicationSupport.appendingPathComponent("AppData", isDirectory: true)
    }

    var ddi: URL {
        applicationSupport.appendingPathComponent("DDI", isDirectory: true)
    }

    var geckoApplicationData: URL {
        applicationSupport
            .appendingPathComponent(".mozilla", isDirectory: true)
            .appendingPathComponent("firefox", isDirectory: true)
    }

    var geckoLocalData: URL {
        caches
            .appendingPathComponent("mozilla", isDirectory: true)
            .appendingPathComponent("firefox", isDirectory: true)
    }

    var pairingFile: URL {
        documents.appendingPathComponent("pairingFile.plist", isDirectory: false)
    }

    var jitTemporary: URL {
        temporary.appendingPathComponent("ptrace_jit", isDirectory: false)
    }

    var migrationRecovery: URL {
        applicationSupport
            .deletingLastPathComponent()
            .appendingPathComponent("ReynardMigration", isDirectory: true)
    }

    static let shared: ReynardDirectories = {
        let fileManager = FileManager.default
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first,
        let caches = fileManager.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first,
        let documents = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            fatalError("Reynard data directories are unavailable")
        }

        return ReynardDirectories(
            applicationSupport: applicationSupport,
            caches: caches,
            documents: documents,
            temporary: fileManager.temporaryDirectory
        )
    }()

    static func make(
        applicationSupport: URL,
        caches: URL,
        documents: URL,
        temporary: URL
    ) -> ReynardDirectories {
        ReynardDirectories(
            applicationSupport: applicationSupport,
            caches: caches,
            documents: documents,
            temporary: temporary
        )
    }
}
