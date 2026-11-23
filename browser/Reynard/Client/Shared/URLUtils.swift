//
//  URLUtils.swift
//  Reynard
//
//  Created by Minh Ton on 11/6/26.
//

import Foundation

enum URLUtils {
    struct URLMatchComponents {
        let hostAndPort: String
        let suffix: String
    }
    
    static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              let host = url.host,
              !host.isEmpty else {
            return false
        }
        
        return scheme == "http" || scheme == "https"
    }
    
    static func isWebURL(_ value: String) -> Bool {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return false
        }
        
        if let url = URL(string: trimmedValue),
           isWebURL(url) {
            return true
        }
        
        let schemePrefixedValue = "https://\(trimmedValue)"
        guard let url = URL(string: schemePrefixedValue),
              isWebURL(url) else {
            return false
        }
        
        return true
    }
    
    static func webURL(from value: String?) -> URL? {
        guard let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: trimmedValue),
              isWebURL(url) else {
            return nil
        }
        
        return url
    }
    
    static func restorableURL(from value: String?) -> String? {
        guard let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedValue.isEmpty,
              trimmedValue.lowercased() != "about:blank" else {
            return nil
        }
        
        return trimmedValue
    }
    
    static func fixTLDTypo(in value: String) -> String {
        let hasScheme = value.contains("://")
        let prefixedValue = hasScheme ? value : "https://\(value)"
        guard var components = URLComponents(string: prefixedValue),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              let dot = host.lastIndex(of: ".") else {
            return value
        }
        
        let suffix = host[host.index(after: dot)...].lowercased()
        let correctedSuffix: String
        switch suffix {
        case "ocm", "con", "cmo", "xom", "vom", "cpm", "com'":
            correctedSuffix = "com"
        case "ent", "ner", "nte", "met":
            correctedSuffix = "net"
        case "rog", "ogr", "prg", "orh":
            correctedSuffix = "org"
        default:
            return value
        }
        
        components.host = String(host[...dot]) + correctedSuffix
        guard let correctedValue = components.string else {
            return value
        }
        
        return hasScheme ? correctedValue : String(correctedValue.dropFirst("https://".count))
    }
    
    static func normalizedCustomURL(from value: String) -> URL? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isWebURL(trimmedValue) else {
            return nil
        }
        
        if let url = URL(string: trimmedValue),
           isWebURL(url) {
            return url
        }
        
        return URL(string: "https://\(trimmedValue)")
    }
    
    static func normalizedNewTabURL(from value: String) -> URL? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmedValue),
           url.scheme?.lowercased() == "moz-extension",
           let host = url.host,
           !host.isEmpty {
            return url
        }
        
        return normalizedCustomURL(from: trimmedValue)
    }
    
    static func sanitizedURL(for url: URL) -> URL? {
        guard isWebURL(url),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased() else {
            return nil
        }
        
        components.scheme = scheme
        components.host = host
        components.fragment = nil
        return components.url
    }
    
    static func isAbsoluteURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.trimmingCharacters(in: .whitespacesAndNewlines),
              !scheme.isEmpty else {
            return false
        }
        
        return !url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    static func httpOriginString(for url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(),
              let host = normalizedHost(url.host),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        
        if let port = url.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }
    
    static func normalizedHost(fromRawURI rawURI: String?) -> String? {
        guard let rawURI,
              let url = URL(string: rawURI) else {
            return nil
        }
        
        return normalizedHost(url.host)
    }
    
    static func normalizedHost(_ host: String?) -> String? {
        guard let host = host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !host.isEmpty else {
            return nil
        }
        
        return host
    }
    
    static func displayString(for url: URL) -> String {
        strippedURLString(url.absoluteString, trimsTrailingSlash: true)
    }
    
    static func hostDisplayString(for url: URL) -> String {
        let host = strippedHostString(from: url.host ?? "")
        guard !host.isEmpty else {
            return displayString(for: url)
        }
        
        return host
    }
    
    static func strippedURLString(
        _ value: String,
        trimsWWW: Bool = true,
        trimsTrailingSlash: Bool = false
    ) -> String {
        let lowered = value.lowercased()
        var strippedValue: String
        if lowered.hasPrefix("https://") {
            strippedValue = String(value.dropFirst("https://".count))
        } else if lowered.hasPrefix("http://") {
            strippedValue = String(value.dropFirst("http://".count))
        } else if lowered.hasPrefix("ftp://") {
            strippedValue = String(value.dropFirst("ftp://".count))
        } else {
            strippedValue = value
        }
        
        if trimsWWW, strippedValue.lowercased().hasPrefix("www.") {
            strippedValue = String(strippedValue.dropFirst("www.".count))
        }
        
        return trimsTrailingSlash ? trimmedTrailingSlash(strippedValue) : strippedValue
    }
    
    static func normalizedURLMatchString(from value: String) -> String {
        strippedURLString(value, trimsTrailingSlash: false).lowercased()
    }
    
    static func strippedHostString(from value: String) -> String {
        let lowered = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard lowered.hasPrefix("www.") else {
            return lowered
        }
        
        return String(lowered.dropFirst("www.".count))
    }
    
    nonisolated static func normalizedURLStringForMatching(from value: String) -> String {
        let remainder = removingSchemePrefix(from: value)
        guard let userInfoEnd = remainder.range(of: "@") else {
            return remainder.lowercased()
        }
        
        return String(remainder[userInfoEnd.upperBound...]).lowercased()
    }
    
    static func urlMatchComponents(from value: String) -> URLMatchComponents {
        let remainder = removingSchemePrefix(from: value)
        let suffixStart = remainder.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) ?? remainder.endIndex
        let authority = remainder[..<suffixStart]
        let userInfoEnd = authority.lastIndex(of: "@")
        let hostStart = userInfoEnd.map { remainder.index(after: $0) } ?? remainder.startIndex
        return URLMatchComponents(
            hostAndPort: String(remainder[hostStart..<suffixStart]),
            suffix: String(remainder[suffixStart...])
        )
    }
    
    static func autocompleteURLString(for query: String, url: URL) -> String? {
        let loweredQuery = query.lowercased()
        for value in autocompleteURLVariants(for: url) {
            if value.lowercased().hasPrefix(loweredQuery) {
                return value
            }
        }
        
        return nil
    }
    
    static func domainCompletion(for query: String, url: URL) -> String? {
        let displayURL = strippedURLString(url.absoluteString, trimsTrailingSlash: true)
        let host = strippedHostString(from: url.host ?? "")
        guard !host.isEmpty,
              displayURL.lowercased().hasPrefix(host.lowercased()) else {
            return nil
        }
        
        let hostWithDotPrefix = ".\(host)"
        guard let range = hostWithDotPrefix.range(of: ".\(query)", options: .caseInsensitive),
              let dotRange = hostWithDotPrefix[range.lowerBound...].firstIndex(of: ".") else {
            return nil
        }
        
        let matchedHost = String(hostWithDotPrefix[hostWithDotPrefix.index(after: dotRange)...])
        guard matchedHost.contains(".") else {
            return nil
        }
        
        let path = String(displayURL.dropFirst(host.count))
        return matchedHost + path
    }
    
    private static func autocompleteURLVariants(for url: URL) -> [String] {
        let fullURL = trimmedTrailingSlash(url.absoluteString)
        let schemeStrippedURL = strippedURLString(url.absoluteString, trimsWWW: false, trimsTrailingSlash: true)
        let normalizedURL = strippedURLString(url.absoluteString, trimsTrailingSlash: true)
        return [fullURL, schemeStrippedURL, normalizedURL]
    }
    
    nonisolated private static func removingSchemePrefix(from value: String) -> Substring {
        let prefix = value.prefix(64)
        guard let colon = prefix.firstIndex(of: ":") else {
            return value[...]
        }
        
        var end = value.index(after: colon)
        if value.distance(from: end, to: value.endIndex) >= 2,
           value[end] == "/",
           value[value.index(after: end)] == "/" {
            end = value.index(end, offsetBy: 2)
        }
        return value[end...]
    }
    
    private static func trimmedTrailingSlash(_ value: String) -> String {
        if value.count > 1, value.hasSuffix("/") {
            return String(value.dropLast())
        }
        
        return value
    }
}
