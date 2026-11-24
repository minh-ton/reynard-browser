//
//  SearchViewModel.swift
//  Reynard
//
//  Created by Minh Ton on 11/6/26.
//

import Foundation

struct SearchResults {
    var query: String
    var bestMatch: UserDataSearchResult?
    var topDomainCompletions: [String]
    var completions: [String]
    var userDataResults: [UserDataSearchResult]
    
    static let empty = SearchResults(
        query: "",
        bestMatch: nil,
        topDomainCompletions: [],
        completions: [],
        userDataResults: []
    )
}

final class SearchViewModel {
    var resultsDidChange: ((SearchResults) -> Void)?
    var searchSuggestionProvider: SearchCompletion.Provider {
        return searchCompletion.provider
    }
    
    private let userDataSearch: UserDataSearch
    private let topDomainCompletion: TopDomainCompletion
    private var searchCompletion: SearchCompletion
    private var requestID = 0
    private var completionTask: URLSessionDataTask?
    private var results = SearchResults.empty
    
    init(
        userDataSearch: UserDataSearch = UserDataSearch(),
        topDomainCompletion: TopDomainCompletion = TopDomainCompletion(),
        searchCompletion: SearchCompletion = SearchCompletion(provider: Prefs.SearchSettings.searchSuggestionProvider)
    ) {
        self.userDataSearch = userDataSearch
        self.topDomainCompletion = topDomainCompletion
        self.searchCompletion = searchCompletion
    }
    
    deinit {
        completionTask?.cancel()
    }
    
    func clear() {
        requestID += 1
        completionTask?.cancel()
        completionTask = nil
        results = .empty
        resultsDidChange?(.empty)
    }
    
    func updateQuery(_ query: String, openTabs: [UserDataSearch.OpenTab]) {
        guard !query.isEmpty else {
            clear()
            return
        }
        
        requestID += 1
        let activeRequestID = requestID
        completionTask?.cancel()
        updateSearchCompletionProviderIfNeeded()
        results.query = query
        results.topDomainCompletions = topDomainCompletion.completions(for: query, limit: 4)
        resultsDidChange?(results)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                return
            }
            
            let userData = self.userDataSearch.search(query: query, openTabs: openTabs)
            
            DispatchQueue.main.async {
                guard activeRequestID == self.requestID else {
                    return
                }
                
                self.results.bestMatch = userData.bestMatch
                self.results.userDataResults = userData.results
                self.resultsDidChange?(self.results)
            }
        }
        
        completionTask = searchCompletion.fetchCompletions(for: query) { [weak self] completions in
            DispatchQueue.main.async {
                guard let self,
                      activeRequestID == self.requestID else {
                    return
                }
                
                self.results.completions = completions
                self.resultsDidChange?(self.results)
            }
        }
    }
    
    private func updateSearchCompletionProviderIfNeeded() {
        let provider = Prefs.SearchSettings.searchSuggestionProvider
        guard searchCompletion.provider != provider else {
            return
        }
        
        searchCompletion = SearchCompletion(provider: provider)
    }
}
