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
    var completions: [String]
    var userDataResults: [UserDataSearchResult]
    
    static let empty = SearchResults(
        query: "",
        bestMatch: nil,
        completions: [],
        userDataResults: []
    )
}

final class SearchViewModel {
    var resultsDidChange: ((SearchResults) -> Void)?
    let completionProvider: SearchCompletion.Provider
    
    private let userDataSearch: UserDataSearch
    private let searchCompletion: SearchCompletion
    private var requestID = 0
    private var completionTask: URLSessionDataTask?
    private var results = SearchResults.empty
    
    init(
        userDataSearch: UserDataSearch = UserDataSearch(),
        searchCompletion: SearchCompletion = SearchCompletion()
    ) {
        self.userDataSearch = userDataSearch
        self.searchCompletion = searchCompletion
        completionProvider = searchCompletion.provider
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
    
    func updateQuery(
        _ query: String,
        activeTabMode: TabMode?,
        excludingTabID: UUID?
    ) {
        guard !query.isEmpty else {
            clear()
            return
        }
        
        requestID += 1
        let activeRequestID = requestID
        completionTask?.cancel()
        results.query = query
        resultsDidChange?(results)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                return
            }
            
            let userData = self.userDataSearch.search(
                query: query,
                activeTabMode: activeTabMode,
                excludingTabID: excludingTabID
            )
            
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
}
