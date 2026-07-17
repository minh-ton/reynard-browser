//
//  PageZoomCompatibilityPolicy.swift
//  Reynard
//
//  Created by Minh Ton on 17/7/26.
//

import Foundation

enum PageZoomCompatibilityPolicy {
    nonisolated private static let githubMinimumLayoutWidth = 256.0

    nonisolated static func minimumLayoutWidth(for url: String) -> Double? {
        guard let host = DomainMatcher.host(from: url),
              DomainMatcher.matches(host: host, domain: "github.com") else {
            return nil
        }
        return githubMinimumLayoutWidth
    }
}
