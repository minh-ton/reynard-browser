//
//  HomepageContentMode.swift
//  Reynard
//
//  Created by Minh Ton on 21/6/26.
//

enum HomepageContentMode: Equatable {
    case embeddedNarrow
    case embeddedWide
    case embeddedExpanded
    case detachedNarrow
    case detachedWide
    
    var favoriteColumnCount: Int {
        switch self {
        case .embeddedNarrow, .detachedNarrow:
            return 4
        case .embeddedWide, .detachedWide:
            return 6
        case .embeddedExpanded:
            return 8
        }
    }
    
    var isDetached: Bool {
        switch self {
        case .detachedNarrow, .detachedWide:
            return true
        case .embeddedNarrow, .embeddedWide, .embeddedExpanded:
            return false
        }
    }
    
    static func embedded(
        layout: BrowserLayout,
        gridWidth: HomepageGridWidth = .eightColumn
    ) -> HomepageContentMode {
        if layout.interfaceIdiom == .pad {
            switch gridWidth {
            case .fourColumn:
                return .embeddedNarrow
            case .sixColumn:
                return .embeddedWide
            case .eightColumn:
                if layout.chromeMode == .compact {
                    return .embeddedNarrow
                }
                return .embeddedExpanded
            }
        }
        
        switch (layout.interfaceIdiom, layout.chromeMode, layout.orientation) {
        case (.phone, _, .portrait):
            return .embeddedNarrow
        case (.phone, _, .landscape):
            return .embeddedWide
        default:
            return .embeddedNarrow
        }
    }
    
    static func detached(layout: BrowserLayout) -> HomepageContentMode {
        switch layout.interfaceIdiom {
        case .phone:
            return .detachedNarrow
        default:
            return .detachedWide
        }
    }
}

enum HomepageGridWidth: Equatable {
    case fourColumn
    case sixColumn
    case eightColumn
}
