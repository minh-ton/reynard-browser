//
//  AddonRuntimeStore.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import Foundation

extension AddonRuntime {
    func notifyActionDelegateAttached() {
        for addon in addonsByID.values {
            notifyActionDelegateAttached(for: addon)
        }
    }
    
    func notifyActionDelegateAttached(for addon: Addon) {
        guard delegate != nil,
              !attachedActionDelegateAddonIDs.contains(addon.id) else {
            return
        }
        
        attachedActionDelegateAddonIDs.insert(addon.id)
        GeckoEventDispatcherWrapper.runtimeInstance.dispatch(
            type: "GeckoView:ActionDelegate:Attached",
            message: ["extensionId": addon.id]
        )
    }
    
    func upsertAddon(from dictionary: [String: Any?]) -> Addon {
        let id = dictionary["webExtensionId"] as? String ?? ""
        if let existingAddon = addonsByID[id] {
            existingAddon.update(from: dictionary)
            notifyActionDelegateAttached(for: existingAddon)
            return existingAddon
        }
        let createdAddon = Addon(dictionary: dictionary)
        addonsByID[id] = createdAddon
        notifyActionDelegateAttached(for: createdAddon)
        return createdAddon
    }
    
    func removeAddon(from message: [String: Any?]?) -> Addon? {
        guard let addonID = addonID(from: message) else {
            return nil
        }
        return removeAddon(byID: addonID)
    }
    
    func removeAddon(byID addonID: String) -> Addon? {
        attachedActionDelegateAddonIDs.remove(addonID)
        return addonsByID.removeValue(forKey: addonID)
    }
    
    func addonID(from message: [String: Any?]?) -> String? {
        if let extensionID = message?["extensionId"] as? String,
           !extensionID.isEmpty {
            return extensionID
        }
        
        if let addonID = PayloadValue.string(message?["addonId"]),
           !addonID.isEmpty {
            return addonID
        }
        
        if let extensionDictionary = message?["extension"] as? [String: Any?],
           let addonID = extensionDictionary["webExtensionId"] as? String,
           !addonID.isEmpty {
            return addonID
        }
        
        return nil
    }
}
