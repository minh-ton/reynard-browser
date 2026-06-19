//
//  Haptics.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import UIKit

enum Haptics {
    private static let impactGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private static let notificationGenerator = UINotificationFeedbackGenerator()
    
    static func prepareRigid() {
        impactGenerator.prepare()
    }
    
    static func rigid() {
        impactGenerator.impactOccurred()
    }
    
    static func success() {
        notificationGenerator.notificationOccurred(.success)
    }
}
