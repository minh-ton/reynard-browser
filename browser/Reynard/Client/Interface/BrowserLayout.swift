//
//  BrowserLayout.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

struct BrowserLayout: Equatable {
    private enum UX {
        static let compactPadLayoutMaximumWidth: CGFloat = 506
        static let narrowPadLayoutMaximumWidth: CGFloat = 666
        static let sidebarOverlayMaximumWidth: CGFloat = 1366
        static let sidebarOverlayMaximumAspectRatio: CGFloat = 1.3
    }
    
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
        ? pad(interfaceIdiom: .pad, orientation: .portrait, isNarrowPadLayout: false)
        : phone
    }
    
    static func resolve(
        interfaceIdiom: UIUserInterfaceIdiom,
        orientation: ViewportOrientation,
        addressBarPosition: BrowserChromePosition,
        in view: UIView
    ) -> BrowserLayout {
        if interfaceIdiom == .pad {
            return isCompactPadLayout(in: view)
            ? compact(interfaceIdiom: .pad, orientation: orientation)
            : pad(interfaceIdiom: .pad, orientation: orientation, isNarrowPadLayout: isNarrowPadLayout(in: view))
        }
        
        guard orientation == .portrait else {
            return pad(interfaceIdiom: .phone, orientation: .landscape, isNarrowPadLayout: false)
        }
        
        return addressBarPosition == .top
        ? compact(interfaceIdiom: .phone, orientation: .portrait)
        : phone
    }
    
    static func isCompactPadLayout(in view: UIView) -> Bool {
        return windowSize(of: view).width <= UX.compactPadLayoutMaximumWidth
    }
    
    static func isNarrowPadLayout(in view: UIView) -> Bool {
        return windowSize(of: view).width <= UX.narrowPadLayoutMaximumWidth
    }
    
    static func isSidebarOverlayLayout(in view: UIView) -> Bool {
        let size = windowSize(of: view)
        guard size.width <= UX.sidebarOverlayMaximumWidth else {
            return false
        }
        
        return size.width / size.height <= UX.sidebarOverlayMaximumAspectRatio
    }
    
    private static func windowSize(of view: UIView) -> CGSize {
        guard let rootView = view.window?.rootViewController?.view,
              rootView.bounds.width > 0 else {
            return view.bounds.size
        }
        
        return rootView.bounds.size
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
        isNarrowPadLayout: Bool
    ) -> BrowserLayout {
        return BrowserLayout(
            interfaceIdiom: interfaceIdiom,
            orientation: orientation,
            chromeMode: .pad,
            chromePosition: .bottom,
            tabOverviewToolbarPosition: isNarrowPadLayout ? .bottom : .top,
            overlayHost: .detached
        )
    }
}
