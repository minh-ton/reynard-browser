//
//  NavigationState.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import UIKit

struct NavigationAvailability: Equatable {
    let canGoBack: Bool
    let canGoForward: Bool
}

struct NavigationPreviewImages {
    let backImage: UIImage?
    let forwardImage: UIImage?
}
