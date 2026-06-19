//
//  UIView+DescendantSearch.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import UIKit

extension UIView {
    func firstDescendantLabel(withText text: String) -> UILabel? {
        if let label = self as? UILabel,
           label.text == text {
            return label
        }
        
        for subview in subviews {
            if let match = subview.firstDescendantLabel(withText: text) {
                return match
            }
        }
        
        return nil
    }
    
    func firstDescendantButton(withTitle title: String) -> UIButton? {
        if let button = self as? UIButton,
           button.currentTitle == title {
            return button
        }
        
        for subview in subviews {
            if let match = subview.firstDescendantButton(withTitle: title) {
                return match
            }
        }
        
        return nil
    }
    
    func firstDescendantView(containingLabelText text: String) -> UIView? {
        if subviews.contains(where: { ($0 as? UILabel)?.text == text }) {
            return self
        }
        
        for subview in subviews {
            if let match = subview.firstDescendantView(containingLabelText: text) {
                return match
            }
        }
        
        return nil
    }
}
