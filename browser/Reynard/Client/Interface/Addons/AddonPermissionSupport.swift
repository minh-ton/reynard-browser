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
    public static let allowForAllSitesTitle = "Allow for all sites"
    public static let allowForAllSitesSubtitle = "If you trust this extension, you can give it permission on every website."
    public static let noPermissionsRequiredDescription = "This extension doesn’t require any permissions."
    public static let noDataCollectionRequiredDescription = "The developer says this extension doesn’t require data collection."
    public static let userScriptsWarning = "Unverified scripts can pose security and privacy risks. Only run scripts from extensions or sources you trust."
    
    private static let permissionDescriptions = [
        "<all_urls>": "Access your data for all websites",
        "bookmarks": "Read and modify bookmarks",
        "browserSettings": "Read and modify browser settings",
        "browsingData": "Clear recent browsing history, cookies, and related data",
        "clipboardRead": "Get data from the clipboard",
        "clipboardWrite": "Input data to the clipboard",
        "declarativeNetRequest": "Block content on any page",
        "declarativeNetRequestFeedback": "Read your browsing history",
        "devtools": "Extend developer tools to access your data in open tabs",
        "downloads": "Download files and read and modify the browser's download history",
        "downloads.open": "Open files downloaded to your device",
        "find": "Read the text of all open tabs",
        "geolocation": "Access your location",
        "history": "Access browsing history",
        "management": "Monitor extension usage and manage themes",
        "nativeMessaging": "Exchange messages with apps other than this one",
        "notifications": "Display notifications to you",
        "pkcs11": "Provide cryptographic authentication services",
        "privacy": "Read and modify privacy settings",
        "proxy": "Control browser proxy settings",
        "sessions": "Access recently closed tabs",
        "tabHide": "Hide and show browser tabs",
        "tabs": "Access browser tabs",
        "topSites": "Access browsing history",
        "trialML": "Download and run AI models on your device",
        "userScripts": "Allow unverified third-party scripts to access your data",
        "webNavigation": "Access browser activity during navigation",
    ]
    
    private static let dataCollectionShortDescriptions = [
        "authenticationInfo": "authentication information",
        "bookmarksInfo": "bookmarks",
        "browsingActivity": "browsing activity",
        "financialAndPaymentInfo": "financial and payment information",
        "healthInfo": "health information",
        "locationInfo": "location",
        "personalCommunications": "personal communications",
        "personallyIdentifyingInfo": "personally identifying information",
        "searchTerms": "search terms",
        "technicalAndInteraction": "technical and interaction data",
        "websiteActivity": "website activity",
        "websiteContent": "website content",
    ]
    
    private static let dataCollectionLongDescriptions = [
        "authenticationInfo": "Share authentication information with extension developer",
        "bookmarksInfo": "Share bookmarks information with extension developer",
        "browsingActivity": "Share browsing activity with extension developer",
        "financialAndPaymentInfo": "Share financial and payment information with extension developer",
        "healthInfo": "Share health information with extension developer",
        "locationInfo": "Share location information with extension developer",
        "personalCommunications": "Share personal communications with extension developer",
        "personallyIdentifyingInfo": "Share personally identifying information with extension developer",
        "searchTerms": "Share search terms with extension developer",
        "technicalAndInteraction": "Share technical and interaction data with extension developer",
        "websiteActivity": "Share website activity with extension developer",
        "websiteContent": "Share website content with extension developer",
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
        
        return "The developer says this extension collects: \(formatLocalizedDataCollectionPermissions(localizedPermissions))"
    }
    
    public static func optionalDataCollectionDescription(for permissions: [String]) -> String? {
        let localizedPermissions = localizeDataCollectionPermissions(permissions)
        guard !localizedPermissions.isEmpty else {
            return nil
        }
        
        return "The developer says the extension wants to collect: \(formatLocalizedDataCollectionPermissions(localizedPermissions))"
    }
    
    public static func updateDataCollectionDescription(for permissions: [String]) -> String? {
        let localizedPermissions = localizeDataCollectionPermissions(permissions)
        guard !localizedPermissions.isEmpty else {
            return nil
        }
        
        return "New required data collection: The developer says the extension will collect \(formatLocalizedDataCollectionPermissions(localizedPermissions))."
    }
    
    public static func updatePermissionDescription(for permissions: [String]) -> String? {
        let localizedPermissions = localizePermissions(permissions, forUpdate: true)
        guard !localizedPermissions.isEmpty else {
            return nil
        }
        
        return "New required permissions: \(localizedPermissions.joined(separator: " "))"
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
            return forUpdate ? "Access your data for all websites." : "Access your data for all websites"
        case .domain(let host):
            let description = "Access your data for sites in the \(host) domain"
            return forUpdate ? description + "." : description
        case .site(let host):
            let description = "Access your data for \(host)"
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
            return [forUpdate ? "Access your data for all websites." : "Access your data for all websites"]
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
                let description = "Access your data for sites in the \(host) domain"
                descriptions.append(forUpdate ? description + "." : description)
            case .site(let host):
                siteCount += 1
                guard siteCount <= maxShownPermissionsEntries else {
                    continue
                }
                let description = "Access your data for \(host)"
                descriptions.append(forUpdate ? description + "." : description)
            }
        }
        
        if domainCount > maxShownPermissionsEntries {
            if domainCount - maxShownPermissionsEntries == 1 {
                descriptions.append(forUpdate ? "Access your data on another domain." : "Access your data on another domain")
            } else {
                descriptions.append(forUpdate ? "Access your data on other domains." : "Access your data on other domains")
            }
        }
        
        if siteCount > maxShownPermissionsEntries {
            if siteCount - maxShownPermissionsEntries == 1 {
                descriptions.append(forUpdate ? "Access your data on another site." : "Access your data on another site")
            } else {
                descriptions.append(forUpdate ? "Access your data on other sites." : "Access your data on other sites")
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
