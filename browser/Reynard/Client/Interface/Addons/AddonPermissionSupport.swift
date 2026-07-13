//
//  AddonPermissionSupport.swift
//  Reynard
//
//  Created by Minh Ton on 23/5/26.
//

import Foundation

public struct AddonLocalizedPermission {
    public let name: String
    public let localizedName: String
    public let granted: Bool
    
    public init(name: String, localizedName: String, granted: Bool) {
        self.name = name
        self.localizedName = localizedName
        self.granted = granted
    }
}

public struct AddonHostPermissions {
    public let allUrls: String?
    public let wildcards: [String]
    public let sites: [String]
    
    public init(allUrls: String?, wildcards: [String], sites: [String]) {
        self.allUrls = allUrls
        self.wildcards = wildcards
        self.sites = sites
    }
}

private enum AddonHostPermissionKind: Equatable {
    case allUrls
    case domain(String)
    case site(String)
}

public enum AddonPermissionSupport {
    public static let allowForAllSitesTitle = NSLocalizedString("Allow on All Websites", comment: "")
    public static let allowForAllSitesSubtitle = NSLocalizedString("Allow this add-on to access every website.", comment: "")
    public static let noPermissionsRequiredDescription = NSLocalizedString("This add-on doesn’t require any permissions.", comment: "")
    public static let noDataCollectionRequiredDescription = NSLocalizedString("The developer says this add-on doesn’t collect data.", tableName: "AddonLocalizable", comment: "")
    public static let userScriptsWarning = NSLocalizedString("Unverified scripts can pose security and privacy risks. Only allow scripts from add-ons or sources you trust.", tableName: "AddonLocalizable", comment: "")
    
    private static let permissionDescriptions = [
        "<all_urls>": NSLocalizedString("Access your data on all websites", tableName: "AddonLocalizable", comment: ""),
        "bookmarks": NSLocalizedString("Read and modify bookmarks", tableName: "AddonLocalizable", comment: ""),
        "browserSettings": NSLocalizedString("Read and modify browser settings", tableName: "AddonLocalizable", comment: ""),
        "browsingData": NSLocalizedString("Clear recent browsing history, cookies, and related data", tableName: "AddonLocalizable", comment: ""),
        "clipboardRead": NSLocalizedString("Get data from the clipboard", tableName: "AddonLocalizable", comment: ""),
        "clipboardWrite": NSLocalizedString("Input data to the clipboard", tableName: "AddonLocalizable", comment: ""),
        "declarativeNetRequest": NSLocalizedString("Block content on any page", tableName: "AddonLocalizable", comment: ""),
        "declarativeNetRequestFeedback": NSLocalizedString("Read your browsing history", tableName: "AddonLocalizable", comment: ""),
        "devtools": NSLocalizedString("Extend developer tools to access your data in open tabs", tableName: "AddonLocalizable", comment: ""),
        "downloads": NSLocalizedString("Download files and read and modify the browser’s download history", tableName: "AddonLocalizable", comment: ""),
        "downloads.open": NSLocalizedString("Open files downloaded to your device", tableName: "AddonLocalizable", comment: ""),
        "find": NSLocalizedString("Read the text of all open tabs", tableName: "AddonLocalizable", comment: ""),
        "geolocation": NSLocalizedString("Access your location", tableName: "AddonLocalizable", comment: ""),
        "history": NSLocalizedString("Access browsing history", tableName: "AddonLocalizable", comment: ""),
        "management": NSLocalizedString("Monitor add-on usage and manage themes", tableName: "AddonLocalizable", comment: ""),
        "nativeMessaging": NSLocalizedString("Exchange messages with apps other than this one", tableName: "AddonLocalizable", comment: ""),
        "notifications": NSLocalizedString("Display notifications to you", tableName: "AddonLocalizable", comment: ""),
        "pkcs11": NSLocalizedString("Provide cryptographic authentication services", tableName: "AddonLocalizable", comment: ""),
        "privacy": NSLocalizedString("Read and modify privacy settings", tableName: "AddonLocalizable", comment: ""),
        "proxy": NSLocalizedString("Control browser proxy settings", tableName: "AddonLocalizable", comment: ""),
        "sessions": NSLocalizedString("Access recently closed tabs", tableName: "AddonLocalizable", comment: ""),
        "tabHide": NSLocalizedString("Hide and show browser tabs", tableName: "AddonLocalizable", comment: ""),
        "tabs": NSLocalizedString("Access browser tabs", tableName: "AddonLocalizable", comment: ""),
        "topSites": NSLocalizedString("Access browsing history", tableName: "AddonLocalizable", comment: ""),
        "trialML": NSLocalizedString("Download and run AI models on your device", tableName: "AddonLocalizable", comment: ""),
        "userScripts": NSLocalizedString("Allow unverified third-party scripts to access your data", tableName: "AddonLocalizable", comment: ""),
        "webNavigation": NSLocalizedString("Access browser activity during navigation", tableName: "AddonLocalizable", comment: ""),
    ]
    
    private static let dataCollectionShortDescriptions = [
        "authenticationInfo": NSLocalizedString("authentication information", tableName: "AddonLocalizable", comment: ""),
        "bookmarksInfo": NSLocalizedString("bookmarks", tableName: "AddonLocalizable", comment: ""),
        "browsingActivity": NSLocalizedString("browsing activity", tableName: "AddonLocalizable", comment: ""),
        "financialAndPaymentInfo": NSLocalizedString("financial and payment information", tableName: "AddonLocalizable", comment: ""),
        "healthInfo": NSLocalizedString("health information", tableName: "AddonLocalizable", comment: ""),
        "locationInfo": NSLocalizedString("location", tableName: "AddonLocalizable", comment: ""),
        "personalCommunications": NSLocalizedString("personal communications", tableName: "AddonLocalizable", comment: ""),
        "personallyIdentifyingInfo": NSLocalizedString("personally identifying information", tableName: "AddonLocalizable", comment: ""),
        "searchTerms": NSLocalizedString("search terms", tableName: "AddonLocalizable", comment: ""),
        "technicalAndInteraction": NSLocalizedString("technical and interaction data", tableName: "AddonLocalizable", comment: ""),
        "websiteActivity": NSLocalizedString("website activity", tableName: "AddonLocalizable", comment: ""),
        "websiteContent": NSLocalizedString("website content", tableName: "AddonLocalizable", comment: ""),
    ]
    
    private static let dataCollectionLongDescriptions = [
        "authenticationInfo": NSLocalizedString("Share authentication information with the add-on developer", tableName: "AddonLocalizable", comment: ""),
        "bookmarksInfo": NSLocalizedString("Share bookmarks information with the add-on developer", tableName: "AddonLocalizable", comment: ""),
        "browsingActivity": NSLocalizedString("Share browsing activity with the add-on developer", tableName: "AddonLocalizable", comment: ""),
        "financialAndPaymentInfo": NSLocalizedString("Share financial and payment information with the add-on developer", tableName: "AddonLocalizable", comment: ""),
        "healthInfo": NSLocalizedString("Share health information with the add-on developer", tableName: "AddonLocalizable", comment: ""),
        "locationInfo": NSLocalizedString("Share location information with the add-on developer", tableName: "AddonLocalizable", comment: ""),
        "personalCommunications": NSLocalizedString("Share personal communications with the add-on developer", tableName: "AddonLocalizable", comment: ""),
        "personallyIdentifyingInfo": NSLocalizedString("Share personally identifying information with the add-on developer", tableName: "AddonLocalizable", comment: ""),
        "searchTerms": NSLocalizedString("Share search terms with the add-on developer", tableName: "AddonLocalizable", comment: ""),
        "technicalAndInteraction": NSLocalizedString("Share technical and interaction data with the add-on developer", tableName: "AddonLocalizable", comment: ""),
        "websiteActivity": NSLocalizedString("Share website activity with the add-on developer", tableName: "AddonLocalizable", comment: ""),
        "websiteContent": NSLocalizedString("Share website content with the add-on developer", tableName: "AddonLocalizable", comment: ""),
    ]
    
    public static func localizePermissions(_ permissions: [String], forUpdate: Bool = false) -> [String] {
        var localizedURLAccessPermissions: [String] = []
        let requireAllUrlsAccess = permissions.contains("<all_urls>")
        var notFoundPermissions: [String] = []
        
        let localizedNormalPermissions = permissions.compactMap { permission -> String? in
            guard let localizedPermission = localizedPermissionDescription(for: permission, forUpdate: forUpdate) else {
                notFoundPermissions.append(permission)
                return nil
            }
            
            return localizedPermission
        }
        
        if !requireAllUrlsAccess && !notFoundPermissions.isEmpty {
            localizedURLAccessPermissions = localizeURLAccessPermissions(notFoundPermissions, forUpdate: forUpdate)
        }
        
        return localizedNormalPermissions + localizedURLAccessPermissions
    }
    
    public static func localizeOptionalPermissions(
        _ permissions: [String],
        grantedPermissions: [String]
    ) -> [AddonLocalizedPermission] {
        let granted = Set(grantedPermissions)
        var localizedPermissions: [AddonLocalizedPermission] = []
        var unresolved: [String] = []
        var allUrlsFound = false
        
        permissions.forEach { permission in
            guard let localizedName = localizedPermissionDescription(for: permission, forUpdate: false) else {
                unresolved.append(permission)
                return
            }
            
            if permission == "<all_urls>" {
                allUrlsFound = true
            }
            
            localizedPermissions.append(
                AddonLocalizedPermission(name: permission, localizedName: localizedName, granted: granted.contains(permission))
            )
        }
        
        if !allUrlsFound {
            unresolved.forEach { permission in
                guard let localizedName = localizeHostPermission(permission, forUpdate: false) else {
                    return
                }
                
                localizedPermissions.append(
                    AddonLocalizedPermission(name: permission, localizedName: localizedName, granted: granted.contains(permission))
                )
            }
        }
        
        return localizedPermissions
    }
    
    public static func localizeOptionalOrigins(
        _ origins: [String],
        grantedOrigins: [String]
    ) -> [AddonLocalizedPermission] {
        let granted = Set(grantedOrigins)
        var localizedOrigins: [AddonLocalizedPermission] = []
        var seen = Set<String>()
        
        origins.forEach { origin in
            guard !seen.contains(origin),
                  let localizedName = localizeHostPermission(origin, forUpdate: false) else {
                return
            }
            
            seen.insert(origin)
            localizedOrigins.append(
                AddonLocalizedPermission(name: origin, localizedName: localizedName, granted: granted.contains(origin))
            )
        }
        
        return localizedOrigins
    }
    
    public static func localizeDataCollectionPermissions(_ permissions: [String]) -> [String] {
        permissions.compactMap { dataCollectionShortDescriptions[$0] }
    }
    
    public static func localizeOptionalDataCollectionPermissions(
        _ permissions: [String],
        grantedPermissions: [String]
    ) -> [AddonLocalizedPermission] {
        let granted = Set(grantedPermissions)
        return permissions.compactMap { permission in
            guard let localizedName = dataCollectionLongDescriptions[permission] else {
                return nil
            }
            
            return AddonLocalizedPermission(name: permission, localizedName: localizedName, granted: granted.contains(permission))
        }
    }
    
    public static func formatLocalizedDataCollectionPermissions(_ localizedPermissions: [String]) -> String {
        ListFormatter.localizedString(byJoining: localizedPermissions)
    }
    
    public static func requiredDataCollectionDescription(for permissions: [String]) -> String? {
        if permissions.count == 1, permissions.contains("none") {
            return noDataCollectionRequiredDescription
        }
        
        let localizedPermissions = localizeDataCollectionPermissions(permissions)
        guard !localizedPermissions.isEmpty else {
            return nil
        }
        
        return String(
            format: NSLocalizedString("The developer says this add-on collects: %@", tableName: "AddonLocalizable", comment: "Data collection list"),
            formatLocalizedDataCollectionPermissions(localizedPermissions)
        )
    }
    
    public static func optionalDataCollectionDescription(for permissions: [String]) -> String? {
        let localizedPermissions = localizeDataCollectionPermissions(permissions)
        guard !localizedPermissions.isEmpty else {
            return nil
        }
        
        return String(
            format: NSLocalizedString("The developer says this add-on wants to collect: %@", tableName: "AddonLocalizable", comment: "Data collection list"),
            formatLocalizedDataCollectionPermissions(localizedPermissions)
        )
    }
    
    public static func updateDataCollectionDescription(for permissions: [String]) -> String? {
        let localizedPermissions = localizeDataCollectionPermissions(permissions)
        guard !localizedPermissions.isEmpty else {
            return nil
        }
        
        return String(
            format: NSLocalizedString("New required data collection: The developer says this add-on will collect %@.", comment: "Data collection list"),
            formatLocalizedDataCollectionPermissions(localizedPermissions)
        )
    }
    
    public static func updatePermissionDescription(for permissions: [String]) -> String? {
        let localizedPermissions = localizePermissions(permissions, forUpdate: true)
        guard !localizedPermissions.isEmpty else {
            return nil
        }
        
        return String(
            format: NSLocalizedString("New required permissions: %@", comment: "Permission list"),
            localizedPermissions.joined(separator: " ")
        )
    }
    
    public static func allSiteOriginPermissions(_ origins: [String]) -> [String] {
        origins.filter { hostPermissionKind(for: $0) == .allUrls }
    }
    
    public static func classifyOriginPermissions(_ origins: [String]) -> AddonHostPermissions {
        var allUrls: String?
        var wildcards: [String] = []
        var sites: [String] = []
        
        origins.forEach { permission in
            if permission == "<all_urls>" {
                if allUrls == nil {
                    allUrls = permission
                }
                return
            }
            
            guard let translation = hostPermissionKind(for: permission) else {
                return
            }
            
            switch translation {
            case .allUrls:
                if allUrls == nil {
                    allUrls = permission
                }
            case .domain(let host):
                if !wildcards.contains(host) {
                    wildcards.append(host)
                }
            case .site(let host):
                if !sites.contains(host) {
                    sites.append(host)
                }
            }
        }
        
        return AddonHostPermissions(allUrls: allUrls, wildcards: wildcards, sites: sites)
    }
    
    public static func localizeHostPermission(_ permission: String, forUpdate: Bool) -> String? {
        switch hostPermissionKind(for: permission) {
        case .allUrls:
            let description = NSLocalizedString("Access your data on all websites", tableName: "AddonLocalizable", comment: "")
            return forUpdate ? description + "." : description
        case .domain(let host):
            let format = NSLocalizedString("Access your data on websites in the %@ domain", tableName: "AddonLocalizable", comment: "Domain name")
            let description = String(format: format, host)
            return forUpdate ? description + "." : description
        case .site(let host):
            let format = NSLocalizedString("Access your data on %@", tableName: "AddonLocalizable", comment: "Website host")
            let description = String(format: format, host)
            return forUpdate ? description + "." : description
        case nil:
            return nil
        }
    }
    
    private static func localizedPermissionDescription(for permission: String, forUpdate: Bool) -> String? {
        guard let description = permissionDescriptions[permission] else {
            return nil
        }
        
        return forUpdate ? description + "." : description
    }
    
    private static func localizeURLAccessPermissions(_ accessPermissions: [String], forUpdate: Bool) -> [String] {
        var hostPermissions: [(String, AddonHostPermissionKind)] = []
        var seenPermissions = Set<String>()
        
        accessPermissions.forEach { permission in
            guard !seenPermissions.contains(permission),
                  let translation = hostPermissionKind(for: permission) else {
                return
            }
            
            seenPermissions.insert(permission)
            hostPermissions.append((permission, translation))
        }
        
        if hostPermissions.contains(where: { _, translation in
            if case .allUrls = translation {
                return true
            }
            return false
        }) {
            let description = NSLocalizedString("Access your data on all websites", tableName: "AddonLocalizable", comment: "")
            return [forUpdate ? description + "." : description]
        }
        
        return formatURLAccessPermissions(hostPermissions, forUpdate: forUpdate)
    }
    
    private static func formatURLAccessPermissions(
        _ hostPermissions: [(String, AddonHostPermissionKind)],
        forUpdate: Bool
    ) -> [String] {
        let maxShownPermissionsEntries = forUpdate ? 2 : 4
        var descriptions: [String] = []
        var domainCount = 0
        var siteCount = 0
        
        for (_, translation) in hostPermissions {
            switch translation {
            case .allUrls:
                continue
            case .domain(let host):
                domainCount += 1
                guard domainCount <= maxShownPermissionsEntries else {
                    continue
                }
                let format = NSLocalizedString("Access your data on websites in the %@ domain", tableName: "AddonLocalizable", comment: "Domain name")
                let description = String(format: format, host)
                descriptions.append(forUpdate ? description + "." : description)
            case .site(let host):
                siteCount += 1
                guard siteCount <= maxShownPermissionsEntries else {
                    continue
                }
                let format = NSLocalizedString("Access your data on %@", tableName: "AddonLocalizable", comment: "Website host")
                let description = String(format: format, host)
                descriptions.append(forUpdate ? description + "." : description)
            }
        }
        
        if domainCount > maxShownPermissionsEntries {
            if domainCount - maxShownPermissionsEntries == 1 {
                let description = NSLocalizedString("Access your data on another domain", tableName: "AddonLocalizable", comment: "")
                descriptions.append(forUpdate ? description + "." : description)
            } else {
                let description = NSLocalizedString("Access your data on other domains", tableName: "AddonLocalizable", comment: "")
                descriptions.append(forUpdate ? description + "." : description)
            }
        }
        
        if siteCount > maxShownPermissionsEntries {
            if siteCount - maxShownPermissionsEntries == 1 {
                let description = NSLocalizedString("Access your data on another website", tableName: "AddonLocalizable", comment: "")
                descriptions.append(forUpdate ? description + "." : description)
            } else {
                let description = NSLocalizedString("Access your data on other websites", tableName: "AddonLocalizable", comment: "")
                descriptions.append(forUpdate ? description + "." : description)
            }
        }
        
        return descriptions
    }
    
    private static func hostPermissionKind(for pattern: String) -> AddonHostPermissionKind? {
        if pattern == "<all_urls>" {
            return .allUrls
        }
        
        guard let schemeRange = pattern.range(of: "://") else {
            return nil
        }
        
        let scheme = pattern[..<schemeRange.lowerBound]
        if scheme != "*" && scheme != "http" && scheme != "https" && scheme != "ws" && scheme != "wss" && scheme != "file" {
            return nil
        }
        
        let hostAndPath = pattern[schemeRange.upperBound...]
        let parts = hostAndPath.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        let host = parts.first.map(String.init) ?? ""
        let path = parts.count > 1 ? "/" + parts[1] : ""
        
        switch true {
        case host == "*":
            return .allUrls
        case host.isEmpty || path.isEmpty:
            return nil
        case host.hasPrefix("*."):
            return .domain(String(host.dropFirst(2)))
        default:
            return .site(host)
        }
    }
}
