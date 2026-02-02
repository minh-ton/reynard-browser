//
//  GeckoView.swift
//  Reynard
//
//  Created by Minh Ton on 1/2/26.
//

import UIKit

public class GeckoView: UIView {
    public var session: GeckoSession? {
        didSet {
            for view in subviews {
                view.removeFromSuperview()
            }

            guard let window = session?.window else {
                NSLog("GeckoView: session has no window!")
                return
            }
            
            guard let sessionView = window.view() else {
                 NSLog("GeckoView: session window has no view!")
                 return
            }
            
            if sessionView.superview != nil {
                fatalError("attempt to assign GeckoSession to multiple GeckoView instances")
            }
            
            sessionView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(sessionView)

            NSLayoutConstraint.activate([
                sessionView.topAnchor.constraint(equalTo: topAnchor),
                sessionView.leadingAnchor.constraint(equalTo: leadingAnchor),
                sessionView.bottomAnchor.constraint(equalTo: bottomAnchor),
                sessionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
            
            setNeedsLayout()
            layoutIfNeeded()
        }
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}
