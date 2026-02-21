//
//  ProcessExtensions.swift
//  Reynard
//
//  Created by Minh Ton on 20/2/26.
//

import Foundation

@objc private protocol BootstrapPing {
    func ping()
}

@MainActor
private final class ProcessBootstrap {
    private static var retainedConnections: [NSXPCConnection] = []

    static func start(
        context: NSExtensionContext,
        process: GeckoProcessExtension
    ) throws {
        guard
            let input = context.inputItems.first as? NSExtensionItem,
            let userInfo = input.userInfo,
            let endpoint = userInfo["ReynardXPCListenerEndpoint"] as? NSXPCListenerEndpoint
        else {
            throw NSError(
                domain: "Reynard.ProcessBootstrap",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing NSXPC listener endpoint"]
            )
        }

        let connection = NSXPCConnection(listenerEndpoint: endpoint)
        connection.remoteObjectInterface = NSXPCInterface(with: BootstrapPing.self)
        connection.interruptionHandler = {
            exit(0)
        }
        connection.invalidationHandler = {
            exit(0)
        }
        connection.resume()

        (connection.remoteObjectProxyWithErrorHandler({ _ in }) as? BootstrapPing)?.ping()

        retainedConnections.append(connection)

        guard let xpcConnection = XPCConnectionFromNSXPC(connection) else {
            throw NSError(
                domain: "Reynard.ProcessBootstrap",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to bridge NSXPCConnection to libxpc"]
            )
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
    }

    open func beginRequest(with context: NSExtensionContext) {
        Task { @MainActor in
            do {
                try ProcessBootstrap.start(context: context, process: self)
            } catch {
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
