//
//  UIView+CommonAncestor.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

extension UIView {
    func hasCommonAncestor(with view: UIView) -> Bool {
        var ancestors = Set<ObjectIdentifier>()
        var currentView: UIView? = self
        
        while let view = currentView {
            ancestors.insert(ObjectIdentifier(view))
            currentView = view.superview
        }
        
        currentView = view
        while let view = currentView {
            if ancestors.contains(ObjectIdentifier(view)) {
                return true
            }
            currentView = view.superview
        }
        
        return false
    }
}
