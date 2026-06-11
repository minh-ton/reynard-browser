//
//  Array+Safe.swift
//  Reynard
//
//  Created by Minh Ton on 4/3/26.
//

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
