//
//  Haptics.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import UIKit

enum Haptics {
    private static let rigidGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    static func prepareRigid() {
        rigidGenerator.prepare()
    }

    static func rigid() {
        rigidGenerator.impactOccurred()
    }

    static func success() {
        notificationGenerator.notificationOccurred(.success)
    }
}
