//
//  GeckoView.swift
//  Reynard
//
//  Created by Minh Ton on 1/2/26.
//

import UIKit

public class GeckoView: UIView {
    public override init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    public var session: GeckoSession? {
        didSet {
            embedSessionView()
        }
    }
    
    private func embedSessionView() {
        subviews.forEach { $0.removeFromSuperview() }
        
        guard let session else {
            return
        }
        
        guard let window = session.window else {
            NSLog("GeckoView: session window is unavailable during assignment")
            return
        }
        
        guard let engineView = window.view() else {
            NSLog("GeckoView: session window has no view!")
            return
        }
        
        if engineView.superview != nil {
            fatalError("attempt to assign GeckoSession to multiple GeckoView instances")
        }
        
        engineView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(engineView)
        
        NSLayoutConstraint.activate([
            engineView.topAnchor.constraint(equalTo: topAnchor),
            engineView.leadingAnchor.constraint(equalTo: leadingAnchor),
            engineView.bottomAnchor.constraint(equalTo: bottomAnchor),
            engineView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        
        setNeedsLayout()
        layoutIfNeeded()
    }
}
