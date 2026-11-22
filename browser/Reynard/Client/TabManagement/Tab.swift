//
//  Tab.swift
//  Reynard
//
//  Created by Minh Ton on 5/3/26.
//

import GeckoView
import UIKit

final class Tab {
    let id: UUID
    var session: GeckoSession
    var title: String
    var url: String?
    let createdAt: Date?
    var isPrivate: Bool
    var favicon: UIImage?
    var thumbnail: UIImage?
    var isMuted: Bool
    let state = TabSessionState()
    
    var mode: TabMode {
        return isPrivate ? .private : .regular
    }
    
    init(
        id: UUID = UUID(),
        session: GeckoSession,
        title: String = "",
        url: String? = nil,
        createdAt: Date? = Date(),
        favicon: UIImage? = nil,
        thumbnail: UIImage? = nil,
        isMuted: Bool = false,
        isPrivate: Bool = false
    ) {
        self.id = id
        self.session = session
        self.title = title
        self.url = url
        self.createdAt = createdAt
        self.favicon = favicon
        self.thumbnail = thumbnail
        self.isMuted = isMuted
        self.isPrivate = isPrivate
    }
}
