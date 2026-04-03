//
//  BrowserFeedback.swift
//  Reynard
//
//  Created by Minh Ton on 3/4/26.
//

import UIKit

final class BrowserFeedback {
    private let successFeedbackGenerator = UINotificationFeedbackGenerator()
    private var notificationTokens: [NSObjectProtocol] = []
    
    init() {
        observeFeedbackSources()
    }
    
    deinit {
        for notificationToken in notificationTokens {
            NotificationCenter.default.removeObserver(notificationToken)
        }
    }
    
    func prepare() {
        successFeedbackGenerator.prepare()
    }
    
    private func observeFeedbackSources() {
        observe(.downloadStoreDidStartDownload) { [weak self] in
            self?.emitSuccessFeedback()
        }
    }
    
    private func observe(_ notificationName: Notification.Name, handler: @escaping () -> Void) {
        let token = NotificationCenter.default.addObserver(
            forName: notificationName,
            object: nil,
            queue: .main
        ) { _ in
            handler()
        }
        notificationTokens.append(token)
    }
    
    private func emitSuccessFeedback() {
        successFeedbackGenerator.notificationOccurred(.success)
        successFeedbackGenerator.prepare()
    }
}
