//
//  SelectionActionCoordinator.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import GeckoView

@MainActor
protocol SelectionActionPresenting {
    func show(_ request: SelectionActionRequest, for session: GeckoSession)
    func hide(for session: GeckoSession)
}

@MainActor
final class SelectionActionCoordinator: SelectionActionDelegate {
    private let presenter: SelectionActionPresenting
    
    init(presenter: SelectionActionPresenting) {
        self.presenter = presenter
    }
    
    func onShowSelectionAction(session: GeckoSession, request: SelectionActionRequest) {
        presenter.show(request, for: session)
    }
    
    func onHideSelectionAction(session: GeckoSession) {
        presenter.hide(for: session)
    }
}
