//
//  BrowserLayout.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

struct BrowserLayout: Equatable {
    enum ViewportOrientation: Equatable {
        case portrait
        case landscape
    }
    
    let interfaceIdiom: UIUserInterfaceIdiom
    let orientation: ViewportOrientation
    let chromeMode: BrowserChromeMode
    let chromePosition: BrowserChromePosition
    let tabOverviewToolbarPosition: TabOverview.ToolbarPosition
    let overlayHost: OverlayCoordinator.Host
    
    static func initial(interfaceIdiom: UIUserInterfaceIdiom) -> BrowserLayout {
        BrowserLayout(
            interfaceIdiom: interfaceIdiom,
            orientation: .portrait,
            chromeMode: interfaceIdiom == .pad ? .pad : .phone,
            chromePosition: .bottom,
            tabOverviewToolbarPosition: interfaceIdiom == .pad ? .top : .bottom,
            overlayHost: interfaceIdiom == .pad ? .detached : .embedded
        )
    }
}
