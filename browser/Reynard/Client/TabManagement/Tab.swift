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
    var isPrivate: Bool
    var favicon: UIImage?
    var thumbnail: UIImage?
    let state = TabSessionState()
    
    init(
        id: UUID = UUID(),
        session: GeckoSession,
        title: String = "",
        url: String? = nil,
        favicon: UIImage? = nil,
        thumbnail: UIImage? = nil,
        isPrivate: Bool = false
    ) {
        self.id = id
        self.session = session
        self.title = title
        self.url = url
        self.favicon = favicon
        self.thumbnail = thumbnail
        self.isPrivate = isPrivate
    }
}
