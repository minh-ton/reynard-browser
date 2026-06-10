//
//  TopBar.swift
//  Reynard
//
//  Created by Minh Ton on 5/3/26.
//

import UIKit

final class TopBar {
    let barView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemGray6
        return view
    }()
    
    let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        return view
    }()
    
    let safeAreaFillView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemGray6
        return view
    }()
    
    var heightConstraint: NSLayoutConstraint!
    var topConstraint: NSLayoutConstraint!
    var contentHeightConstraint: NSLayoutConstraint!
}
