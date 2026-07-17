//
//  main.swift
//  Reynard
//
//  Created by Minh Ton on 1/2/26.
//

import Foundation
import GeckoView
import UIKit
import Darwin

@available(iOS, introduced: 13.0, obsoleted: 14.0)
private func configureUnsandboxedAppDataDirectories(_ directories: ReynardDirectories) {
    guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
        return
    }
    
    let appDataDirectory = directories.caches
        .appendingPathComponent(bundleIdentifier, isDirectory: true)
        .appendingPathComponent(".mozilla", isDirectory: true)
        .appendingPathComponent("firefox", isDirectory: true)
    
    do {
        try FileManager.default.createDirectory(
            at: appDataDirectory,
            withIntermediateDirectories: true
        )
    } catch {
        return
    }
    
    setenv("MOZ_APP_DATA", appDataDirectory.path, 1)
    setenv("MOZ_LOCAL_APP_DATA", appDataDirectory.path, 1)
}

let recoveryFailed: Bool
do {
    try ReynardMigrationRecovery().recoverPendingTransactions()
    recoveryFailed = false
} catch {
    recoveryFailed = true
}

let startupMode = ReynardStartupMode.resolve(recoveryFailed: recoveryFailed)
ReynardStartupMode.current = startupMode
let directories = ReynardDirectories.shared

if startupMode.usesUIKitOnlyStartup {
    _ = UIApplicationMain(
        CommandLine.argc,
        CommandLine.unsafeArgv,
        nil,
        NSStringFromClass(AppDelegate.self)
    )
} else {
    UserDataMigration.shared.run()
    JITController.shared.start()
    if #unavailable(iOS 14.0),
       getEntitlementValue("com.apple.private.security.no-sandbox") {
        configureUnsandboxedAppDataDirectories(directories)
    }
    GeckoRuntime.main(argc: CommandLine.argc, argv: CommandLine.unsafeArgv)
}
