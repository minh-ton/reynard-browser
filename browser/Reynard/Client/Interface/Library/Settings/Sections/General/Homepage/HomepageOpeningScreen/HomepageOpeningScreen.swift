//
//  HomepageOpeningScreen.swift
//  Reynard
//
//  Created by Minh Ton on 27/6/26.
//

enum HomepageOpeningScreen: String, CaseIterable {
    case homepage
    case lastTab
    
    var title: String {
        switch self {
        case .homepage:
            return NSLocalizedString("Homepage", comment: "")
        case .lastTab:
            return NSLocalizedString("Last Tab", comment: "")
        }
    }
}
