//
//  AddonRuntime.swift
//  Reynard
//
//  Created by Minh Ton on 28/4/26.
//

import Foundation

public final class AddonRuntime: NSObject, GeckoEventListenerInternal {
    public static let shared = AddonRuntime()
    
    public weak var delegate: AddonEmbedderDelegate? {
        didSet {
            if delegate == nil {
                attachedActionDelegateAddonIDs.removeAll()
            }
            guard delegate != nil else {
                return
            }
            Task { @MainActor in
                _ = try? await self.list()
                self.notifyActionDelegateAttached()
            }
        }
    }
    
    var addonsByID: [String: Addon] = [:]
    var attachedActionDelegateAddonIDs = Set<String>()
    var installCounter = 0
    
    public var installedAddons: [Addon] {
        return Array(addonsByID.values).sorted {
            ($0.metaData.name ?? $0.id).localizedCaseInsensitiveCompare($1.metaData.name ?? $1.id) == .orderedAscending
        }
    }
    
    private override init() {
        super.init()
        for event in AddonRuntimeEvent.allCases {
            GeckoEventDispatcherWrapper.runtimeInstance.addListener(type: event.rawValue, listener: self)
        }
    }
    
    func register(sessionListener: AddonSessionListener) {
        guard let session = sessionListener.session else {
            return
        }
        for event in sessionListener.events {
            session.dispatcher.addListener(type: event, listener: sessionListener)
        }
    }
}
