//
//  DomainMatcher.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import Foundation

enum DomainMatcher {
    static func host(from url: String) -> String? {
        if let host = URL(string: url)?.host?.lowercased() {
            return host
        }
        return URL(string: "https://" + url)?.host?.lowercased()
    }
    
    static func matches(host: String, domain: String) -> Bool {
        let domain = domain.lowercased()
        return host == domain || host.hasSuffix("." + domain)
    }
}
