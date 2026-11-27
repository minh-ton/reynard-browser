//
//  SearchContentMode.swift
//  Reynard
//
//  Created by Minh Ton on 21/6/26.
//

enum SearchContentMode: Equatable {
    case embedded
    case detached
    
    var overlayHost: OverlayCoordinator.Host {
        switch self {
        case .embedded:
            return .embedded
        case .detached:
            return .detached
        }
    }
    
    static func current(
        layout: BrowserLayout,
        widthMode: SearchWidthMode = .standard
    ) -> SearchContentMode {
        if layout.interfaceIdiom == .pad,
           widthMode == .narrow {
            return .embedded
        }
        
        switch layout.overlayHost {
        case .embedded:
            return .embedded
        case .detached:
            return .detached
        }
    }
}

enum SearchWidthMode: Equatable {
    case standard
    case narrow
}
