//
//  ContextMenuContext.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import UIKit

struct ContextMenuContext {
    enum Target {
        case link(URL)
        case image(URL)
    }
    
    let target: Target
    let point: CGPoint
}
