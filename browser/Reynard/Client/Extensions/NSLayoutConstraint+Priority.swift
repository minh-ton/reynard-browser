//
//  NSLayoutConstraint+Priority.swift
//  Reynard
//
//  Created by Minh Ton on 11/6/26.
//

extension NSLayoutConstraint {
    func withPriority(_ priority: UILayoutPriority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}
