//
//  ContextMenuTabActions.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import GeckoView

enum TabOpenDisposition: Equatable {
    case currentTab
    case newTab
    case newPrivateTab
    case backgroundTab
}

struct ContextMenuTabActions {
    private let tabManager: TabManager
    private let sessionManager: SessionManager
    
    init(tabManager: TabManager, sessionManager: SessionManager) {
        self.tabManager = tabManager
        self.sessionManager = sessionManager
    }
    
    func openPreviewSession(
        _ session: GeckoSession,
        url: String,
        title: String?,
        disposition: TabOpenDisposition
    ) {
        switch disposition {
        case .currentTab:
            tabManager.adoptPreview(session, url: url, title: title)
            
        case .newTab, .backgroundTab:
            tabManager.addTransferredSession(
                session,
                url: url,
                title: title,
                selecting: disposition != .backgroundTab,
                at: tabManager.index(for: .afterSelected, mode: tabManager.selectedTabMode),
                isPrivate: tabManager.selectedTabMode == .private
            )
            
        case .newPrivateTab:
            sessionManager.close(session)
            let tab = tabManager.createTab(
                selecting: true,
                target: tabManager.selectedTabMode == .private ? .afterSelected : .end,
                mode: .private
            )
            tabManager.browse(to: url, in: tab)
        }
    }
}
