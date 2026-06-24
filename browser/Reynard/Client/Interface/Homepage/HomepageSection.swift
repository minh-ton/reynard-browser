//
//  HomepageSection.swift
//  Reynard
//
//  Created by Minh Ton on 21/6/26.
//

enum Recommendations: CaseIterable, Hashable {
    case performance
    case donation
}

enum HomepageSection: CaseIterable, Hashable {
    case recommendation(Recommendations)
    case privateBrowsing
    case favorites
    
    static var allCases: [HomepageSection] {
        return Recommendations.allCases.map { .recommendation($0) } + [
            .privateBrowsing,
            .favorites,
        ]
    }
}
