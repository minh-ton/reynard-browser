//
//  UserDataSearch.swift
//  Reynard
//
//  Created by Minh Ton on 11/6/26.
//

import Foundation

struct UserDataSearchResult: Equatable {
    enum Source {
        case bookmark
        case history
        case tab
    }
    
    let source: Source
    let title: String
    let url: URL
    let tabID: UUID?
    let lastVisitedAt: Date?
}

struct UserDataSearchResults {
    let bestMatch: UserDataSearchResult?
    let results: [UserDataSearchResult]
}

final class UserDataSearch {
    struct OpenTab {
        let id: UUID
        let title: String
        let url: String?
    }
    
    private enum Limits {
        static let bestMatchCandidateCount = 10
        static let resultCount = 5
    }
    
    private let bookmarkStore: BookmarkStore
    private let historyStore: HistoryStore
    
    init(
        bookmarkStore: BookmarkStore = .shared,
        historyStore: HistoryStore = .shared
    ) {
        self.bookmarkStore = bookmarkStore
        self.historyStore = historyStore
    }
    
    // MARK: - Search
    
    func search(query: String, openTabs: [OpenTab]) -> UserDataSearchResults {
        let bestMatch = findBestMatch(query: query, openTabs: openTabs)
        let results = findResults(query: query, openTabs: openTabs, bestMatch: bestMatch)
        return UserDataSearchResults(bestMatch: bestMatch, results: results)
    }
    
    private func findBestMatch(query: String, openTabs: [OpenTab]) -> UserDataSearchResult? {
        let limit = Limits.bestMatchCandidateCount
        let tabMatches = Prefs.SearchSettings.searchOpenedTabs
        ? matchingOpenTabs(openTabs, query: query, limit: limit)
        : []
        let historyMatches = Prefs.SearchSettings.searchBrowsingHistory
        ? historyStore.search(matching: query, limit: limit).items
        : []
        let bookmarkMatches = Prefs.SearchSettings.searchBookmarks
        ? bookmarkStore.bookmarks(matchingPrefix: query, limit: limit)
        : []
        
        var bestMatchCandidates: [UserDataSearchResult] = []
        bestMatchCandidates += bookmarkMatches
            .map(bookmarkResult)
            .filter { SearchRanking.isBestMatchCandidate($0, query: query) }
        bestMatchCandidates += tabMatches
            .compactMap(tabResult)
            .filter { SearchRanking.isBestMatchCandidate($0, query: query) }
        bestMatchCandidates += historyMatches
            .map(historyResult)
            .filter { SearchRanking.isBestMatchCandidate($0, query: query) }
        
        return SearchRanking.rankedMatches(from: bestMatchCandidates, query: query, limit: 1).first
    }
    
    private func findResults(
        query: String,
        openTabs: [OpenTab],
        bestMatch: UserDataSearchResult?
    ) -> [UserDataSearchResult] {
        let limit = Limits.resultCount
        let tabMatches = Prefs.SearchSettings.searchOpenedTabs
        ? matchingOpenTabs(openTabs, query: query, limit: limit)
        : []
        let historyMatches = Prefs.SearchSettings.searchBrowsingHistory
        ? historyStore.search(matching: query, limit: limit).items
        : []
        let bookmarkMatches = Prefs.SearchSettings.searchBookmarks
        ? bookmarkStore.bookmarks(matching: query, limit: limit)
        : []
        
        var matches: [UserDataSearchResult] = []
        matches += tabMatches.compactMap(tabResult)
        matches += historyMatches.map(historyResult)
        matches += bookmarkMatches
            .map(bookmarkResult)
            .filter { $0.url != bestMatch?.url }
        
        return SearchRanking.rankedMatches(from: matches, query: query, limit: limit)
    }
    
    private func matchingOpenTabs(_ openTabs: [OpenTab], query: String, limit: Int) -> [OpenTab] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty, limit > 0 else {
            return []
        }
        
        let strippedQuery = URLUtils.normalizedURLMatchString(from: normalizedQuery)
        let matches = openTabs.lazy.filter { tab in
            let title = tab.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let urlValue = tab.url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let strippedURL = URLUtils.normalizedURLMatchString(from: urlValue)
            let titleMatches = !title.isEmpty && title.contains(normalizedQuery)
            let urlMatches = !strippedURL.isEmpty && !strippedQuery.isEmpty && strippedURL.hasPrefix(strippedQuery)
            return titleMatches || urlMatches
        }
        return Array(matches.prefix(limit))
    }
    
    // MARK: - Result Mapping
    
    private func bookmarkResult(from bookmark: BookmarkSnapshot) -> UserDataSearchResult {
        UserDataSearchResult(
            source: .bookmark,
            title: resultTitle(bookmark.title, fallbackURL: bookmark.url),
            url: bookmark.url,
            tabID: nil,
            lastVisitedAt: nil
        )
    }
    
    private func tabResult(from tab: OpenTab) -> UserDataSearchResult? {
        guard let urlString = tab.url, let url = URL(string: urlString) else {
            return nil
        }
        
        return UserDataSearchResult(
            source: .tab,
            title: resultTitle(tab.title, fallbackURL: url),
            url: url,
            tabID: tab.id,
            lastVisitedAt: nil
        )
    }
    
    private func historyResult(from site: HistorySiteSnapshot) -> UserDataSearchResult {
        UserDataSearchResult(
            source: .history,
            title: resultTitle(site.title, fallbackURL: site.url),
            url: site.url,
            tabID: nil,
            lastVisitedAt: site.lastVisitedAt
        )
    }
    
    private func resultTitle(_ title: String, fallbackURL: URL) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? fallbackURL.host ?? fallbackURL.absoluteString : trimmedTitle
    }
}
