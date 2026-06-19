//
//  AddonMetaData.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import Foundation

public struct AddonMetaData {
    public let name: String?
    public let description: String?
    public let fullDescription: String?
    public let version: String
    public let iconURL: String?
    public let optionsPageURL: String?
    public let openOptionsPageInTab: Bool
    public let enabled: Bool
    public let allowedInPrivateBrowsing: Bool
    public let incognito: AddonIncognitoMode
    public let baseURL: String
    public let creatorName: String?
    public let creatorURL: String?
    public let homepageURL: String?
    public let reviewURL: String?
    public let averageRating: Double?
    public let reviewCount: Int?
    public let updateDate: String?
    public let requiredPermissions: [String]
    public let requiredOrigins: [String]
    public let requiredDataCollectionPermissions: [String]
    public let optionalPermissions: [String]
    public let optionalOrigins: [String]
    public let optionalDataCollectionPermissions: [String]
    public let grantedOptionalPermissions: [String]
    public let grantedOptionalOrigins: [String]
    public let grantedOptionalDataCollectionPermissions: [String]
    public let downloadURL: String?
    public let amoListingURL: String?
    public let disabledFlags: [String]
    
    init(dictionary: [String: Any?]) {
        name = dictionary["name"] as? String
        description = dictionary["description"] as? String
        fullDescription = dictionary["fullDescription"] as? String
        version = dictionary["version"] as? String ?? ""
        iconURL = Self.resolveIconURL(from: dictionary["icons"] ?? nil)
        optionsPageURL = dictionary["optionsPageURL"] as? String
        openOptionsPageInTab = dictionary["openOptionsPageInTab"] as? Bool ?? false
        enabled = dictionary["enabled"] as? Bool ?? false
        allowedInPrivateBrowsing = dictionary["privateBrowsingAllowed"] as? Bool ?? false
        incognito = AddonIncognitoMode(rawValue: dictionary["incognito"] as? String ?? "") ?? .spanning
        baseURL = dictionary["baseURL"] as? String ?? ""
        creatorName = dictionary["creatorName"] as? String
        creatorURL = dictionary["creatorURL"] as? String
        homepageURL = dictionary["homepageURL"] as? String
        reviewURL = dictionary["reviewURL"] as? String
        averageRating = PayloadValue.double(dictionary["averageRating"] ?? nil)
        reviewCount = PayloadValue.int(dictionary["reviewCount"] ?? nil)
        updateDate = dictionary["updateDate"] as? String
        requiredPermissions = dictionary["requiredPermissions"] as? [String] ?? []
        requiredOrigins = dictionary["requiredOrigins"] as? [String] ?? []
        requiredDataCollectionPermissions = dictionary["requiredDataCollectionPermissions"] as? [String] ?? []
        optionalPermissions = dictionary["optionalPermissions"] as? [String] ?? []
        optionalOrigins = dictionary["optionalOrigins"] as? [String] ?? []
        optionalDataCollectionPermissions = dictionary["optionalDataCollectionPermissions"] as? [String] ?? []
        grantedOptionalPermissions = dictionary["grantedOptionalPermissions"] as? [String] ?? []
        grantedOptionalOrigins = dictionary["grantedOptionalOrigins"] as? [String] ?? []
        grantedOptionalDataCollectionPermissions = dictionary["grantedOptionalDataCollectionPermissions"] as? [String] ?? []
        downloadURL = dictionary["downloadUrl"] as? String
        amoListingURL = dictionary["amoListingURL"] as? String
        disabledFlags = dictionary["disabledFlags"] as? [String] ?? []
    }
    
    public var isBlocklisted: Bool {
        return disabledFlags.contains("blocklistDisabled")
    }
    
    public var isSoftBlocked: Bool {
        return disabledFlags.contains("softBlocklistDisabled")
    }
    
    public var isUnsigned: Bool {
        return disabledFlags.contains("signatureDisabled")
    }
    
    public var isUnsupported: Bool {
        return disabledFlags.contains("appDisabled")
    }
    
    public var isIncompatible: Bool {
        return disabledFlags.contains("appVersionDisabled")
    }
    
    public var canBeEnabled: Bool {
        return !isBlocklisted && !isUnsigned && !isIncompatible && !isUnsupported
    }
    
    private static func resolveIconURL(from value: Any?) -> String? {
        let entries: [(String, Any?)]
        if let dictionary = value as? [String: Any?] {
            entries = Array(dictionary)
        } else if let dictionary = value as? [NSNumber: Any?] {
            entries = dictionary.map { ($0.key.stringValue, $0.value) }
        } else {
            return nil
        }
        
        let availableIcons = entries
            .compactMap { key, value -> (Int, String)? in
                guard let size = Int(key) else {
                    return nil
                }
                if let url = value as? String {
                    return (size, url)
                }
                if let url = value as? NSString {
                    return (size, url as String)
                }
                return nil
            }
        
        let rasterIcons = availableIcons.filter { !$0.1.lowercased().hasSuffix(".svg") }
        if let preferredRasterIcon = preferredIconEntry(from: rasterIcons) {
            return preferredRasterIcon.1
        }
        
        return preferredIconEntry(from: availableIcons)?.1
    }
    
    private static func preferredIconEntry(from entries: [(Int, String)]) -> (Int, String)? {
        let minimumSize = 32
        return entries.sorted { lhs, rhs in
            let lhsDelta = max(lhs.0 - minimumSize, 0)
            let rhsDelta = max(rhs.0 - minimumSize, 0)
            return lhsDelta == rhsDelta ? lhs.0 < rhs.0 : lhsDelta < rhsDelta
        }.first
    }
}

public enum AddonIncognitoMode: String {
    case spanning
    case split
    case notAllowed = "not_allowed"
}
