//
//  SearchSupport.swift
//  Reynard
//
//  Created by Minh Ton on 28/4/26.
//

import Foundation

enum SearchEngine: String, CaseIterable {
    case google
    case yahoo
    case bing
    case brave
    case duckDuckGo
    case ecosia
    case startpage
    case custom
    
    var displayName: String {
        switch self {
        case .google:
            return "Google"
        case .yahoo:
            return "Yahoo"
        case .bing:
            return "Bing"
        case .brave:
            return "Brave"
        case .duckDuckGo:
            return "DuckDuckGo"
        case .ecosia:
            return "Ecosia"
        case .startpage:
            return "Startpage"
        case .custom:
            return "Custom"
        }
    }
    
    var searchTemplate: String? {
        switch self {
        case .google:
            return "https://www.google.com/search?q=%s"
        case .yahoo:
            return "https://search.yahoo.com/search?p=%s"
        case .bing:
            return "https://www.bing.com/search?q=%s"
        case .brave:
            return "https://search.brave.com/search?q=%s"
        case .duckDuckGo:
            return "https://duckduckgo.com/?q=%s"
        case .ecosia:
            return "https://www.ecosia.org/search?q=%s"
        case .startpage:
            return "https://www.startpage.com/sp/search?query=%s"
        case .custom:
            return nil
        }
    }
}

func searchURL(for query: String) -> String {
    let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    return resolvedSearchTemplate().replacingOccurrences(of: "%s", with: encodedQuery)
}

func isValidCustomSearchTemplate(_ value: String) -> Bool {
    let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmedValue.contains("%s") else {
        return false
    }
    
    let candidate = trimmedValue.replacingOccurrences(of: "%s", with: "reynard")
    guard let components = URLComponents(string: candidate),
          let scheme = components.scheme?.lowercased(),
          ["http", "https"].contains(scheme),
          let host = components.host,
          !host.isEmpty else {
        return false
    }
    
    return true
}

private func resolvedSearchTemplate() -> String {
    switch Prefs.SearchSettings.searchEngine {
    case .custom where isValidCustomSearchTemplate(Prefs.SearchSettings.customSearchTemplate):
        return Prefs.SearchSettings.customSearchTemplate
    case let engine:
        return engine.searchTemplate ?? SearchEngine.google.searchTemplate!
    }
}
