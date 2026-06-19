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
    private enum Limits {
        static let bestMatchCandidateCount = 10
        static let resultCount = 5
    }
    
    private let bookmarkStore: BookmarkStore
    private let historyStore: HistoryStore
    private let tabManagementStore: TabManagementStore
    
    init(
        bookmarkStore: BookmarkStore = .shared,
        historyStore: HistoryStore = .shared,
        tabManagementStore: TabManagementStore = .shared
    ) {
        self.bookmarkStore = bookmarkStore
        self.historyStore = historyStore
        self.tabManagementStore = tabManagementStore
    }
    
    // MARK: - Search
    
    func search(
        query: String,
        activeTabMode: TabMode?,
        excludingTabID: UUID?
    ) -> UserDataSearchResults {
        let bestMatch = findBestMatch(
            query: query,
            activeTabMode: activeTabMode,
            excludingTabID: excludingTabID
        )
        let results = findResults(
            query: query,
            activeTabMode: activeTabMode,
            bestMatch: bestMatch,
            excludingTabID: excludingTabID
        )
        return UserDataSearchResults(bestMatch: bestMatch, results: results)
    }
    
    private func findBestMatch(
        query: String,
        activeTabMode: TabMode?,
        excludingTabID: UUID?
    ) -> UserDataSearchResult? {
        let limit = Limits.bestMatchCandidateCount
        let tabMatches = tabManagementStore.tabs(
            matching: query,
            limit: limit,
            isPrivate: activeTabMode == .private
        ).filter { $0.id != excludingTabID }
        let historyMatches = historyStore.search(matching: query, limit: limit).items
        let bookmarkMatches = bookmarkStore.bookmarks(matchingPrefix: query, limit: limit)
        
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
        activeTabMode: TabMode?,
        bestMatch: UserDataSearchResult?,
        excludingTabID: UUID?
    ) -> [UserDataSearchResult] {
        let limit = Limits.resultCount
        let tabMatches = tabManagementStore.tabs(
            matching: query,
            limit: limit,
            isPrivate: activeTabMode == .private
        ).filter { $0.id != excludingTabID }
        let historyMatches = historyStore.search(matching: query, limit: limit).items
        let bookmarkMatches = bookmarkStore.bookmarks(matching: query, limit: limit)
        
        var matches: [UserDataSearchResult] = []
        matches += tabMatches.compactMap(tabResult)
        matches += historyMatches.map(historyResult)
        matches += bookmarkMatches
            .map(bookmarkResult)
            .filter { $0.url != bestMatch?.url }
        
        return SearchRanking.rankedMatches(from: matches, query: query, limit: limit)
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
    
    private func tabResult(from tab: TabManagementStore.TabSnapshot) -> UserDataSearchResult? {
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
