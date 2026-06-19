//
//  SearchRanking.swift
//  Reynard
//
//  Created by Minh Ton on 11/6/26.
//

import Foundation

enum SearchRanking {
    static func rankedMatches(
        from matches: [UserDataSearchResult],
        query: String,
        limit: Int
    ) -> [UserDataSearchResult] {
        let scoredMatches = matches
            .map { (result: $0, score: relevanceScore(for: $0, query: query)) }
            .sorted { lhs, rhs in
                let lhsPriority = priority(for: lhs.result.source)
                let rhsPriority = priority(for: rhs.result.source)
                return lhsPriority == rhsPriority
                ? lhs.score < rhs.score
                : lhsPriority < rhsPriority
            }
        
        var seenURLStrings = Set<String>()
        var rankedMatches: [UserDataSearchResult] = []
        rankedMatches.reserveCapacity(limit)
        for scoredResult in scoredMatches {
            let urlKey = scoredResult.result.url.absoluteString.lowercased()
            guard seenURLStrings.insert(urlKey).inserted else {
                continue
            }
            
            rankedMatches.append(scoredResult.result)
            if rankedMatches.count >= limit {
                break
            }
        }
        
        return rankedMatches
    }
    
    static func isBestMatchCandidate(_ result: UserDataSearchResult, query: String) -> Bool {
        guard !query.isEmpty else {
            return false
        }
        
        let strippedQuery = URLUtils.normalizedURLMatchString(from: query)
        let strippedURL = URLUtils.normalizedURLMatchString(from: result.url.absoluteString)
        return result.title.hasPrefix(query)
        || (!strippedQuery.isEmpty && strippedURL.hasPrefix(strippedQuery))
    }
    
    private static func relevanceScore(for result: UserDataSearchResult, query: String) -> Int {
        let normalizedQuery = query.lowercased()
        let strippedQuery = URLUtils.normalizedURLMatchString(from: normalizedQuery)
        guard !normalizedQuery.isEmpty else {
            return Int.max
        }
        
        let title = result.title.lowercased()
        let host = URLUtils.strippedHostString(from: result.url.host ?? "")
        let strippedURL = URLUtils.normalizedURLMatchString(from: result.url.absoluteString)
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
    
    private static func priority(for source: UserDataSearchResult.Source) -> Int {
        switch source {
        case .tab:
            return 0
        case .bookmark:
            return 1
        case .history:
            return 2
        }
    }
}
