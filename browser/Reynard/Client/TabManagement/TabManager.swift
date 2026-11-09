//
//  TabManager.swift
//  Reynard
//
//  Created by Minh Ton on 5/3/26.
//

import Foundation
import GeckoView
import UIKit

enum TabMode: String, Codable {
    case regular
    case `private`
}

extension TabMode {
    static var defaultBrowsingMode: TabMode {
        return Prefs.PrivateBrowsingSettings.alwaysUsePrivateBrowsing ? .private : .regular
    }
    
    func defaultingToPrivateBrowsing() -> TabMode {
        return Prefs.PrivateBrowsingSettings.alwaysUsePrivateBrowsing ? .private : self
    }
}

enum TabRemovalBehavior {
    case recent     // activate the most recently used tab
    case adjacent   // activate the tab adjacent to the one being removed
    case none
}

protocol TabManager: AnyObject {
    var regularTabs: [Tab] { get }
    var privateTabs: [Tab] { get }
    var selectedTabMode: TabMode { get }
    var selectedTabIndex: Int { get }
    var selectedTab: Tab? { get }
    
    func applicationDidBecomeActive()
    func createInitialTab()
    func applyDefaultBrowsingMode()
    @discardableResult
    func addTab(selecting: Bool, windowId: String?, at index: Int?, isPrivate: Bool) -> Int
    @discardableResult
    func addTransferredSession(_ session: GeckoSession, url: String, title: String?, selecting: Bool, at index: Int?, isPrivate: Bool) -> Int
    func selectTab(at index: Int, mode: TabMode?)
    func moveTab(from sourceIndex: Int, to destinationIndex: Int, mode: TabMode?)
    func removeTab(at index: Int, mode: TabMode?, behavior: TabRemovalBehavior)
    func removeAllTabs(mode: TabMode?)
    @discardableResult
    func restoreRecentlyClosedTab(id: UUID) -> Bool
    func browse(to term: String)
    func browse(to term: String, in tab: Tab)
    func goBack()
    func goBack(to index: Int)
    func goForward()
    func goForward(to index: Int)
    func replaceSelectedSession(with session: GeckoSession, url: String, title: String?)
    func tabIndex(for session: GeckoSession) -> Int?
    func shareableURL(for tab: Tab) -> URL?
    func updateThumbnail(_ image: UIImage?, forTabAt index: Int, mode: TabMode)
    func updateHistoryThumbnail(_ image: UIImage?, for tab: Tab, url: String, isPreparedForNavigation: Bool)
    func navigationHistory(for tab: Tab) -> NavigationHistoryStore.Snapshot
    func navigationPreviewImages(for tab: Tab) -> NavigationPreviewImages
    func invalidateNavigationThumbnails()
    func setMuted(_ muted: Bool, for tabID: UUID)
    func muteOtherPlayingTabs(excluding tabID: UUID)
    @discardableResult
    func changeWebsiteModeForSelectedTab() -> Bool
}

enum TabManagerUpdateReason {
    case title
    case location
    case favicon
    case navigationState
    case loading
    case loadError
    case thumbnail
    case pageBackgroundColor
    case readerMode
    case audio
}

protocol TabManagerDelegate: AnyObject {
    func tabManagerDidChangeTabs(_ tabManager: TabManager)
    func tabManagerDidTerminateSelectedTab(_ tabManager: TabManager)
    func tabManager(_ tabManager: TabManager, didSelectTabAt index: Int, previousIndex: Int?)
    func tabManager(_ tabManager: TabManager, didReplaceSelectedSession previousSession: GeckoSession, with replacementSession: GeckoSession)
    func tabManager(_ tabManager: TabManager, didUpdateTabAt index: Int, reason: TabManagerUpdateReason)
    func tabManager(_ tabManager: TabManager, didFinishLoading session: GeckoSession)
    func tabManager(_ tabManager: TabManager, captureHistoryThumbnailForTabAt index: Int, mode: TabMode, url: String)
    func tabManager(_ tabManager: TabManager, didChangeFullscreen fullScreen: Bool, for session: GeckoSession)
    func tabManager(_ tabManager: TabManager, animateReturnTo tab: Tab, completion: @escaping () -> Void)
    func tabManager(_ tabManager: TabManager, animateNewTabSelectionAt index: Int, completion: @escaping () -> Void)
    func tabManager(_ tabManager: TabManager, didRequestDownload download: DownloadStore.PendingDownload)
    func tabManager(_ tabManager: TabManager, shouldStartExternalResponse response: ExternalResponseInfo, for session: GeckoSession) async -> Bool
    func tabManager(_ tabManager: TabManager, shouldContinueExternalResponseAt localFilePath: String, bytesReceived: Int64) -> Bool
    func tabManager(_ tabManager: TabManager, didCompleteExternalResponseAt localFilePath: String, succeeded: Bool)
    func tabManager(_ tabManager: TabManager, didRequestContextMenuAt point: CGPoint, for element: ContextElement, in session: GeckoSession)
    func tabManager(_ tabManager: TabManager, didRequestContentKeyboardFocusFor session: GeckoSession)
    func tabManager(_ tabManager: TabManager, didRequestFindInPage query: String, in session: GeckoSession)
}

extension TabManagerDelegate {
    func tabManagerDidTerminateSelectedTab(_ tabManager: TabManager) {}
    func tabManager(_ tabManager: TabManager, didFinishLoading session: GeckoSession) {}
    func tabManager(_ tabManager: TabManager, captureHistoryThumbnailForTabAt index: Int, mode: TabMode, url: String) {}
    func tabManager(_ tabManager: TabManager, didReplaceSelectedSession previousSession: GeckoSession, with replacementSession: GeckoSession) {}
    func tabManager(_ tabManager: TabManager, animateNewTabSelectionAt index: Int, completion: @escaping () -> Void) {
        completion()
    }
    func tabManager(_ tabManager: TabManager, shouldStartExternalResponse response: ExternalResponseInfo, for session: GeckoSession) async -> Bool {
        return false
    }
    func tabManager(_ tabManager: TabManager, shouldContinueExternalResponseAt localFilePath: String, bytesReceived: Int64) -> Bool {
        return false
    }
    func tabManager(_ tabManager: TabManager, didCompleteExternalResponseAt localFilePath: String, succeeded: Bool) {}
    func tabManager(_ tabManager: TabManager, didRequestContextMenuAt point: CGPoint, for element: ContextElement, in session: GeckoSession) {}
}
