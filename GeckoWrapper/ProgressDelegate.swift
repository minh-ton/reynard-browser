//
//  ProgressDelegate.swift
//  Reynard
//
//  Created by Minh Ton on 22/2/26.
//

import Foundation

public protocol ProgressDelegate {
    func onPageStart(session: GeckoSession, url: String)
    func onPageStop(session: GeckoSession, success: Bool)
    func onProgressChange(session: GeckoSession, progress: Int)
}

extension ProgressDelegate {
    public func onPageStart(session: GeckoSession, url: String) {}
    public func onPageStop(session: GeckoSession, success: Bool) {}
    public func onProgressChange(session: GeckoSession, progress: Int) {}
}

enum ProgressEvents: String, CaseIterable {
    case pageStart = "GeckoView:PageStart"
    case pageStop = "GeckoView:PageStop"
    case progressChanged = "GeckoView:ProgressChanged"
    case securityChanged = "GeckoView:SecurityChanged"
    case stateUpdated = "GeckoView:StateUpdated"
}

func newProgressHandler(_ session: GeckoSession) -> GeckoSessionHandler<ProgressDelegate, ProgressEvents> {
    GeckoSessionHandler(moduleName: "GeckoViewProgress", session: session) {
        @MainActor session, delegate, event, message in
        switch event {
        case .pageStart:
            guard let url = message?["uri"] as? String else {
                return nil
            }
            delegate?.onPageStart(session: session, url: url)
            return nil
        case .pageStop:
            delegate?.onPageStop(session: session, success: message?["success"] as? Bool ?? false)
            return nil
        case .progressChanged:
            delegate?.onProgressChange(session: session, progress: message?["progress"] as? Int ?? 0)
            return nil
        case .securityChanged:
            return nil
        case .stateUpdated:
            return nil
        }
    }
}
