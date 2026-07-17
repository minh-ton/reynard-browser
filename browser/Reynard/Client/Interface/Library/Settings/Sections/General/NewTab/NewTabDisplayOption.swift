//
//  NewTabDisplayOption.swift
//  Reynard
//
//  Created by Minh Ton on 22/6/26.
//

enum NewTabDisplayOption: String {
    case homepage
    case blankPage
    case customURL

    var supportsAutomaticKeyboardFocus: Bool {
        switch self {
        case .homepage, .blankPage:
            return true
        case .customURL:
            return false
        }
    }
}
