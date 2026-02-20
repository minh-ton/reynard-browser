//
//  ReynardProcessExtensions.swift
//  Reynard
//

import Foundation
import os
import ObjectiveC.runtime

// REYNARD_DEBUG: Need cleanup later
private let reynardLogger = Logger(
    subsystem: "me.minh-ton.Reynard.E10S",
    category: "ChildBootstrap"
)

private enum ProcessBootstrapError: Error {
    case missingInputItem
    case missingEndpoint
    case invalidEndpointData
    case missingLibXPCConnection
}

private enum ProcessBootstrapKey {
    static let endpoint = "ReynardXPCListenerEndpoint"
    static let endpointData = "ReynardXPCListenerEndpointData"
}

@objc private protocol BootstrapPing {
    func ping()
}

// REYNARD_DEBUG: Need cleanup later
private func reynardDebugContextSelectors(_ context: NSExtensionContext) {
    var count: UInt32 = 0
    guard let methods = class_copyMethodList(type(of: context), &count) else {
        return
    }
    defer { free(methods) }

    var names: [String] = []
    for index in 0..<Int(count) {
        let selector = method_getName(methods[index])
        let name = NSStringFromSelector(selector)
        if name.localizedCaseInsensitiveContains("xpc") ||
            name.localizedCaseInsensitiveContains("connection") ||
            name.localizedCaseInsensitiveContains("host") ||
            name.localizedCaseInsensitiveContains("listener") {
            names.append(name)
        }
    }

    if !names.isEmpty {
        reynardLogger.notice("REYNARD_DEBUG: NSExtensionContext selectors: \(names.joined(separator: ", "), privacy: .public)")
    }
}

@MainActor
private final class ProcessBootstrap {
    private static var retainedConnections: [NSXPCConnection] = []

    static func start(
        context: NSExtensionContext,
        process: GeckoProcessExtension
    ) throws {
        guard let input = context.inputItems.first as? NSExtensionItem else {
            throw ProcessBootstrapError.missingInputItem
        }

        guard let userInfo = input.userInfo else {
            throw ProcessBootstrapError.missingEndpoint
        }

        let keys = userInfo.keys.map { String(describing: $0) }.sorted().joined(separator: ",")
        reynardLogger.notice("REYNARD_DEBUG: child bootstrap userInfo keys=\(keys, privacy: .public)")
        reynardDebugContextSelectors(context)

        let endpoint: NSXPCListenerEndpoint
        if let directEndpoint = userInfo[ProcessBootstrapKey.endpoint] as? NSXPCListenerEndpoint {
            reynardLogger.notice("REYNARD_DEBUG: child bootstrap using direct endpoint class=\(String(describing: type(of: directEndpoint)), privacy: .public)")
            endpoint = directEndpoint
        } else if let endpointData = userInfo[ProcessBootstrapKey.endpointData] as? Data {
            guard
                let decodedEndpoint = try NSKeyedUnarchiver.unarchivedObject(
                    ofClass: NSXPCListenerEndpoint.self,
                    from: endpointData
                )
            else {
                throw ProcessBootstrapError.invalidEndpointData
            }
            reynardLogger.notice("REYNARD_DEBUG: child bootstrap using decoded endpoint class=\(String(describing: type(of: decodedEndpoint)), privacy: .public)")
            endpoint = decodedEndpoint
        } else {
            if let rawEndpoint = userInfo[ProcessBootstrapKey.endpoint] {
                reynardLogger.error("REYNARD_DEBUG: child bootstrap endpoint key present with unexpected class=\(String(describing: type(of: rawEndpoint)), privacy: .public)")
            }
            throw ProcessBootstrapError.missingEndpoint
        }

        let processName = String(describing: type(of: process))
        let connection = NSXPCConnection(listenerEndpoint: endpoint)
        connection.remoteObjectInterface = NSXPCInterface(with: BootstrapPing.self)
        connection.interruptionHandler = {
            reynardLogger.error("REYNARD_DEBUG: child NSXPC connection interrupted for process=\(processName, privacy: .public)")
            exit(0)
        }
        connection.invalidationHandler = {
            reynardLogger.error("REYNARD_DEBUG: child NSXPC connection invalidated for process=\(processName, privacy: .public)")
            exit(0)
        }
        connection.resume()
        reynardLogger.notice("REYNARD_DEBUG: child NSXPC connection resumed for process=\(processName, privacy: .public)")

        if let bootstrapProxy = connection.remoteObjectProxyWithErrorHandler({ error in
            reynardLogger.error("REYNARD_DEBUG: child bootstrap ping failed for process=\(processName, privacy: .public), error=\(String(describing: error), privacy: .public)")
        }) as? BootstrapPing {
            bootstrapProxy.ping()
            reynardLogger.notice("REYNARD_DEBUG: child bootstrap ping sent for process=\(processName, privacy: .public)")
        } else {
            reynardLogger.error("REYNARD_DEBUG: child bootstrap proxy unavailable for process=\(processName, privacy: .public)")
        }

        retainedConnections.append(connection)

        guard let xpcConnection = XPCConnectionFromNSXPC(connection) else {
            throw ProcessBootstrapError.missingLibXPCConnection
        }

        GeckoRuntime.childMain(xpcConnection: xpcConnection, process: process)
    }
}

open class BaseProcessExtension: NSObject, GeckoProcessExtension, NSExtensionRequestHandling {
    open class var processKind: String {
        fatalError("Subclasses must override processKind")
    }

    public required override init() {
        super.init()
        reynardLogger.notice("REYNARD_DEBUG: BaseProcessExtension init for kind=\(Self.processKind, privacy: .public)")
    }

    open func beginRequest(with context: NSExtensionContext) {
        reynardLogger.notice("REYNARD_DEBUG: beginRequest entered for kind=\(Self.processKind, privacy: .public), inputItems=\(context.inputItems.count, privacy: .public)")
        Task { @MainActor in
            do {
                try ProcessBootstrap.start(context: context, process: self)
                reynardLogger.notice("REYNARD_DEBUG: ProcessBootstrap.start succeeded for kind=\(Self.processKind, privacy: .public)")
            } catch {
                reynardLogger.error("REYNARD_DEBUG: ProcessBootstrap.start failed for kind=\(Self.processKind, privacy: .public), error=\(String(describing: error), privacy: .public)")
                context.cancelRequest(withError: error)
            }
        }
    }

    open func lockdownSandbox(_ revision: String!) {}
}

open class WebContentProcessExtension: BaseProcessExtension {
    public override class var processKind: String { "WebContent" }
}

open class NetworkingProcessExtension: BaseProcessExtension {
    public override class var processKind: String { "Networking" }
}

open class RenderingProcessExtension: BaseProcessExtension {
    public override class var processKind: String { "Rendering" }
}
