//
//  Addon.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

public final class Addon: NSObject {
    public let id: String
    public let locationURI: String
    public let isBuiltIn: Bool
    public let flags: Int
    public private(set) var metaData: AddonMetaData
    
    public internal(set) var browserAction: AddonAction?
    public internal(set) var pageAction: AddonAction?
    
    init(dictionary: [String: Any?]) {
        id = dictionary["webExtensionId"] as? String ?? ""
        locationURI = dictionary["locationURI"] as? String ?? ""
        isBuiltIn = dictionary["isBuiltIn"] as? Bool ?? false
        flags = PayloadValue.int(dictionary["webExtensionFlags"] ?? nil) ?? 0
        
        metaData = AddonMetaData(
            dictionary: dictionary["metaData"] as? [String: Any?] ?? [:]
        )
    }
    
    func update(from dictionary: [String: Any?]) {
        metaData = AddonMetaData(
            dictionary: dictionary["metaData"] as? [String: Any?] ?? [:]
        )
    }
}
