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
        return interfaceIdiom == .pad
        ? pad(interfaceIdiom: .pad, orientation: .portrait, isHalfSplitScreenOrSmaller: false)
        : phone
    }
    
    static func resolve(
        interfaceIdiom: UIUserInterfaceIdiom,
        orientation: ViewportOrientation,
        addressBarPosition: BrowserChromePosition,
        isCompactPadLayout: Bool,
        isHalfSplitScreenOrSmaller: Bool
    ) -> BrowserLayout {
        if interfaceIdiom == .pad {
            return isCompactPadLayout
            ? compact(interfaceIdiom: .pad, orientation: orientation)
            : pad(interfaceIdiom: .pad, orientation: orientation, isHalfSplitScreenOrSmaller: isHalfSplitScreenOrSmaller)
        }
        
        guard orientation == .portrait else {
            return pad(interfaceIdiom: .phone, orientation: .landscape, isHalfSplitScreenOrSmaller: isHalfSplitScreenOrSmaller)
        }
        
        return addressBarPosition == .top
        ? compact(interfaceIdiom: .phone, orientation: .portrait)
        : phone
    }
    
    private static let phone = BrowserLayout(
        interfaceIdiom: .phone,
        orientation: .portrait,
        chromeMode: .phone,
        chromePosition: .bottom,
        tabOverviewToolbarPosition: .bottom,
        overlayHost: .embedded
    )
    
    private static func compact(
        interfaceIdiom: UIUserInterfaceIdiom,
        orientation: ViewportOrientation
    ) -> BrowserLayout {
        return BrowserLayout(
            interfaceIdiom: interfaceIdiom,
            orientation: orientation,
            chromeMode: .compact,
            chromePosition: interfaceIdiom == .phone ? .top : .bottom,
            tabOverviewToolbarPosition: .bottom,
            overlayHost: .embedded
        )
    }
    
    private static func pad(
        interfaceIdiom: UIUserInterfaceIdiom,
        orientation: ViewportOrientation,
        isHalfSplitScreenOrSmaller: Bool
    ) -> BrowserLayout {
        return BrowserLayout(
            interfaceIdiom: interfaceIdiom,
            orientation: orientation,
            chromeMode: .pad,
            chromePosition: .bottom,
            tabOverviewToolbarPosition: isHalfSplitScreenOrSmaller ? .bottom : .top,
            overlayHost: .detached
        )
    }
}
