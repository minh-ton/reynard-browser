//
//  SelectionActionRequest.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import CoreGraphics
import Foundation

public struct SelectionActionRequest {
    public let actionId: String
    public let actions: [String]
    public let selection: String
    public let editable: Bool
    public let screenRect: CGRect
}

public enum SelectionActionCommand {
    public static let copy = "org.mozilla.geckoview.COPY"
    public static let selectAll = "org.mozilla.geckoview.SELECT_ALL"
}
