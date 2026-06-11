//
//  SearchController.swift
//  Reynard
//
//  Created by Minh Ton on 1/6/26.
//

import Foundation

enum SearchAuxiliaryMatchKind {
    case bookmark
    case history
    case tab
}

struct SearchAuxiliaryMatch {
    let kind: SearchAuxiliaryMatchKind
    let title: String
    let url: URL
    let tabID: UUID?
    let historyLastVisitedAt: Date?
}

final class SearchController {
    private static let primarySearchCandidateLimit = 10
    private static let auxiliarySearchResultLimit = 5
    
    private struct RequestState {
        let query: String
        var primaryMatch: SearchAuxiliaryMatch?
        var suggestions: [String]
        var auxiliaryMatches: [SearchAuxiliaryMatch]
    }
    
    private weak var controller: BrowserViewController?
    private let urlSession: URLSession
    private let bookmarkStore: BookmarkStore
    private let historyStore: HistoryStore
    private let tabManagementStore: TabManagementStore
    private var requestGeneration = 0
    private var currentTask: URLSessionDataTask?
    private var requestState: RequestState?
    private var displayedSuggestions: [String] = []
    
    init(
        controller: BrowserViewController? = nil,
        urlSession: URLSession = .shared,
        bookmarkStore: BookmarkStore = .shared,
        historyStore: HistoryStore = .shared,
        tabManagementStore: TabManagementStore = .shared
    ) {
        self.controller = controller
        self.urlSession = urlSession
        self.bookmarkStore = bookmarkStore
        self.historyStore = historyStore
        self.tabManagementStore = tabManagementStore
    }
    
    func clearSuggestions() {
        requestGeneration += 1
        currentTask?.cancel()
        currentTask = nil
        requestState = nil
        displayedSuggestions = []
        DispatchQueue.main.async { [weak self] in
            self?.controller?.searchViewController.setSuggestions(
                [],
                forQuery: "",
                primaryMatch: nil,
                auxiliaryMatches: []
            )
        }
    }
    
    func fetchSuggestions(for query: String) {
        guard !query.isEmpty else {
            clearSuggestions()
            return
        }
        
        requestGeneration += 1
        let generation = requestGeneration
        currentTask?.cancel()
        let activeTabMode = controller?.tabManager.selectedTabMode
        let selectedTabID = controller?.tabManager.selectedTab?.id
        let previousPrimaryMatch = requestState?.primaryMatch
        let previousAuxiliaryMatches = requestState?.auxiliaryMatches ?? []
        requestState = RequestState(
            query: query,
            primaryMatch: previousPrimaryMatch,
            suggestions: displayedSuggestions,
            auxiliaryMatches: previousAuxiliaryMatches
        )
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                return
            }
            
            let primaryMatch = self.buildPrimaryMatch(
                for: query,
                activeTabMode: activeTabMode,
                excludingTabID: selectedTabID
            )
            let auxiliaryMatches = self.buildAuxiliaryMatches(
                for: query,
                activeTabMode: activeTabMode,
                primaryMatch: primaryMatch,
                excludingTabID: selectedTabID
            )
            DispatchQueue.main.async {
                guard generation == self.requestGeneration else {
                    return
                }
                
                guard var state = self.requestState else {
                    return
                }
                
                state.primaryMatch = primaryMatch
                state.auxiliaryMatches = auxiliaryMatches
                self.requestState = state
                self.publishRequestState()
            }
        }
        
        guard var components = URLComponents(string: "https://suggestqueries.google.com/complete/search") else {
            return
        }
        components.queryItems = [
            URLQueryItem(name: "client", value: "firefox"),
            URLQueryItem(name: "q", value: query),
        ]
        guard let url = components.url else {
            return
        }
        
        currentTask = urlSession.dataTask(with: url) { [weak self] data, response, error in
            guard let self else {
                return
            }
            
            if let error = error as NSError?,
               error.domain == NSURLErrorDomain,
               error.code == NSURLErrorCancelled {
                return
            }
            
            guard generation == self.requestGeneration else {
                return
            }
            
            let suggestions = self.parseSuggestions(from: data, response: response)
            DispatchQueue.main.async {
                guard generation == self.requestGeneration else {
                    return
                }
                
                guard var state = self.requestState else {
                    return
                }
                
                state.suggestions = suggestions
                self.requestState = state
                self.displayedSuggestions = suggestions
                self.publishRequestState()
            }
        }
        currentTask?.resume()
    }
    
    private func parseSuggestions(from data: Data?, response: URLResponse?) -> [String] {
        guard let data,
              let payload = parsePayload(data: data, response: response),
              payload.count > 1,
              let rawSuggestions = payload[1] as? [Any] else {
            return []
        }
        
        return rawSuggestions.compactMap { value in
            guard let suggestion = value as? String else {
                return nil
            }
            let trimmed = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
    
    private func parsePayload(data: Data, response: URLResponse?) -> [Any]? {
        if let payload = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            return payload
        }
        
        guard let textEncodingName = response?.textEncodingName,
              let encoding = String.Encoding.ianaCharacterSetName(textEncodingName),
              let text = String(data: data, encoding: encoding),
              let utf8Data = text.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: utf8Data) as? [Any] else {
            return nil
        }
        
        return payload
    }
    
    private func publishRequestState() {
        guard let state = requestState else {
            return
        }
        
        controller?.updateAddressBarAutocomplete(for: state.query, primaryMatch: state.primaryMatch)
        controller?.searchViewController.setSuggestions(
            state.suggestions,
            forQuery: state.query,
            primaryMatch: state.primaryMatch,
            auxiliaryMatches: state.auxiliaryMatches
        )
    }
    
    private func buildPrimaryMatch(
        for query: String,
        activeTabMode: TabMode?,
        excludingTabID: UUID?
    ) -> SearchAuxiliaryMatch? {
        let limit = Self.primarySearchCandidateLimit
        let tabMatches = tabManagementStore.searchTabs(
            matching: query,
            limit: limit,
            isPrivate: activeTabMode == .private
        ).filter { $0.id != excludingTabID }
        let historyMatches = historyStore.search(matching: query, limit: limit).items
        let bookmarkMatches = bookmarkStore.searchBookmarksPrefix(matching: query, limit: limit)
        
        var candidates: [SearchAuxiliaryMatch] = []
        
        for bookmark in bookmarkMatches {
            let match = SearchAuxiliaryMatch(
                kind: .bookmark,
                title: normalizedTitle(bookmark.title, fallbackURL: bookmark.url),
                url: bookmark.url,
                tabID: nil,
                historyLastVisitedAt: nil
            )
            if isPrimaryPrefixMatch(match, query: query) {
                candidates.append(match)
            }
        }
        
        for tab in tabMatches {
            guard let urlString = tab.url,
                  let url = URL(string: urlString) else {
                continue
            }
            
            let match = SearchAuxiliaryMatch(
                kind: .tab,
                title: normalizedTitle(tab.title, fallbackURL: url),
                url: url,
                tabID: tab.id,
                historyLastVisitedAt: nil
            )
            if isPrimaryPrefixMatch(match, query: query) {
                candidates.append(match)
            }
        }
        
        for site in historyMatches {
            let match = SearchAuxiliaryMatch(
                kind: .history,
                title: normalizedTitle(site.title, fallbackURL: site.url),
                url: site.url,
                tabID: nil,
                historyLastVisitedAt: site.lastVisitedAt
            )
            if isPrimaryPrefixMatch(match, query: query) {
                candidates.append(match)
            }
        }
        
        candidates.sort { lhs, rhs in
            let lhsPriority = sourcePriority(for: lhs.kind)
            let rhsPriority = sourcePriority(for: rhs.kind)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            
            return relevanceScore(for: lhs, query: query) < relevanceScore(for: rhs, query: query)
        }
        
        return candidates.first
    }
    
    private func buildAuxiliaryMatches(
        for query: String,
        activeTabMode: TabMode?,
        primaryMatch: SearchAuxiliaryMatch?,
        excludingTabID: UUID?
    ) -> [SearchAuxiliaryMatch] {
        let limit = Self.auxiliarySearchResultLimit
        guard limit > 0 else {
            return []
        }
        
        let tabMatches = tabManagementStore.searchTabs(
            matching: query,
            limit: limit,
            isPrivate: activeTabMode == .private
        ).filter { $0.id != excludingTabID }
        let historyMatches = historyStore.search(matching: query, limit: limit).items
        let bookmarkMatches = bookmarkStore.searchBookmarks(matching: query, limit: limit)
        
        var scoredMatches: [(match: SearchAuxiliaryMatch, score: Int)] = []
        for tab in tabMatches {
            guard let urlString = tab.url,
                  let url = URL(string: urlString) else {
                continue
            }
            
            let title = normalizedTitle(tab.title, fallbackURL: url)
            let match = SearchAuxiliaryMatch(
                kind: .tab,
                title: title,
                url: url,
                tabID: tab.id,
                historyLastVisitedAt: nil
            )
            scoredMatches.append((match: match, score: relevanceScore(for: match, query: query)))
        }
        
        for site in historyMatches {
            let title = normalizedTitle(site.title, fallbackURL: site.url)
            let match = SearchAuxiliaryMatch(
                kind: .history,
                title: title,
                url: site.url,
                tabID: nil,
                historyLastVisitedAt: site.lastVisitedAt
            )
            scoredMatches.append((match: match, score: relevanceScore(for: match, query: query)))
        }
        
        for bookmark in bookmarkMatches where bookmark.url != primaryMatch?.url {
            let match = SearchAuxiliaryMatch(
                kind: .bookmark,
                title: normalizedTitle(bookmark.title, fallbackURL: bookmark.url),
                url: bookmark.url,
                tabID: nil,
                historyLastVisitedAt: nil
            )
            scoredMatches.append((match: match, score: relevanceScore(for: match, query: query)))
        }
        
        scoredMatches.sort { lhs, rhs in
            let lhsPriority = sourcePriority(for: lhs.match.kind)
            let rhsPriority = sourcePriority(for: rhs.match.kind)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            
            return lhs.score < rhs.score
        }
        
        var seenURLs = Set<String>()
        var matches: [SearchAuxiliaryMatch] = []
        matches.reserveCapacity(limit)
        for candidate in scoredMatches {
            let canonicalURL = candidate.match.url.absoluteString.lowercased()
            guard seenURLs.insert(canonicalURL).inserted else {
                continue
            }
            
            matches.append(candidate.match)
            if matches.count >= limit {
                break
            }
        }
        
        return matches
    }
    
    private func isPrimaryPrefixMatch(_ match: SearchAuxiliaryMatch, query: String) -> Bool {
        guard !query.isEmpty else {
            return false
        }
        
        let strippedQuery = strippedURLString(from: query.lowercased())
        let strippedURL = strippedURLString(from: match.url.absoluteString)
        return match.title.hasPrefix(query)
        || (!strippedQuery.isEmpty && strippedURL.hasPrefix(strippedQuery))
    }
    
    private func relevanceScore(for match: SearchAuxiliaryMatch, query: String) -> Int {
        let normalizedQuery = query.lowercased()
        let strippedQuery = strippedURLString(from: normalizedQuery)
        guard !normalizedQuery.isEmpty else {
            return Int.max
        }
        
        let title = match.title.lowercased()
        let host = strippedHostString(from: match.url.host ?? "")
        let strippedURL = strippedURLString(from: match.url.absoluteString)
        let hasURLQuery = !strippedQuery.isEmpty
        let hasExactMatch =
        title == normalizedQuery ||
        host == normalizedQuery ||
        (hasURLQuery && strippedURL == strippedQuery)
        if hasExactMatch {
            return 0
        }
        
        let hasPrefixMatch =
        title.hasPrefix(normalizedQuery) ||
        host.hasPrefix(normalizedQuery) ||
        (hasURLQuery && strippedURL.hasPrefix(strippedQuery))
        if hasPrefixMatch {
            return 1
        }
        
        let hasContainsMatch =
        title.contains(normalizedQuery) ||
        host.contains(normalizedQuery) ||
        (hasURLQuery && strippedURL.contains(strippedQuery))
        if hasContainsMatch {
            return 2
        }
        
        return 3
    }
    
    private func sourcePriority(for kind: SearchAuxiliaryMatchKind) -> Int {
        switch kind {
        case .tab:
            return 0
        case .bookmark:
            return 1
        case .history:
            return 2
        }
    }
    
    private func normalizedTitle(_ title: String, fallbackURL: URL) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        
        if let host = fallbackURL.host?.trimmingCharacters(in: .whitespacesAndNewlines),
           !host.isEmpty {
            return host
        }
        
        return fallbackURL.absoluteString
    }
    
    private func strippedURLString(from value: String) -> String {
        let lowered = value.lowercased()
        let strippedValue: String
        if lowered.hasPrefix("https://") {
            strippedValue = String(lowered.dropFirst("https://".count))
        } else if lowered.hasPrefix("http://") {
            strippedValue = String(lowered.dropFirst("http://".count))
        } else if lowered.hasPrefix("ftp://") {
            strippedValue = String(lowered.dropFirst("ftp://".count))
        } else {
            strippedValue = lowered
        }
        
        if strippedValue.hasPrefix("www.") {
            return String(strippedValue.dropFirst("www.".count))
        }
        
        return strippedValue
    }
    
    private func strippedHostString(from value: String) -> String {
        let lowered = value.lowercased()
        if lowered.hasPrefix("www.") {
            return String(lowered.dropFirst("www.".count))
        }
        
        return lowered
    }
}
