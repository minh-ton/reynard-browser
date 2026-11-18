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
    /// Set when the system vertical bar (iOS 27.1) holds the toolbar buttons,
    /// as on a folded foldable iPhone, where the status bar sits in a column at
    /// one side; the address bar then stays at the bottom on its own.
    var usesVerticalBar = false
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
