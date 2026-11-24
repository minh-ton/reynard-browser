//
//  UIDragItem+Tab.swift
//  Reynard
//
//  Created by Minh Ton on 24/11/26.
//

import UIKit

extension NSUserActivity {
    private static let createWindowActivityType = "\(Bundle.main.bundleIdentifier!).UserActivity.create-window"
    private static let tabIDKey = "tabID"
    
    var draggedTabID: UUID? {
        guard activityType == Self.createWindowActivityType,
              let tabID = userInfo?[Self.tabIDKey] as? String else {
            return nil
        }
        return UUID(uuidString: tabID)
    }
    
    fileprivate convenience init(draggedTabID: UUID) {
        self.init(activityType: Self.createWindowActivityType)
        userInfo = [Self.tabIDKey: draggedTabID.uuidString]
    }
}

extension UIDragItem {
    convenience init(tab: Tab) {
        let itemProvider = NSItemProvider()
        if UIApplication.shared.supportsMultipleScenes {
            itemProvider.registerObject(NSUserActivity(draggedTabID: tab.id), visibility: .all)
        }
        
        self.init(itemProvider: itemProvider)
        localObject = tab
    }
    
    var draggedTab: Tab? {
        return localObject as? Tab
    }
}
