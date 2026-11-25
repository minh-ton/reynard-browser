//
//  DNSOverHTTPSSettings.swift
//  Reynard
//
//  Created by Minh Ton on 4/9/26.
//

enum DNSOverHTTPSProtectionLevel: Int, CaseIterable {
    case defaultProtection = 0
    case increasedProtection = 2
    case maxProtection = 3
    case noProtection = 5
}

enum SecureDNSProvider: String, CaseIterable {
    case cloudflare
    case nextDNS
    case quad9
    case adGuardDNS
    case foundationForAppliedPrivacy
    case njalla
    case custom

    var url: String? {
        switch self {
        case .cloudflare:
            return "https://mozilla.cloudflare-dns.com/dns-query"
        case .nextDNS:
            return "https://firefox.dns.nextdns.io/"
        case .quad9:
            return "https://dns.quad9.net/dns-query"
        case .adGuardDNS:
            return "https://dns.adguard-dns.com/dns-query"
        case .foundationForAppliedPrivacy:
            return "https://doh.applied-privacy.net/query"
        case .njalla:
            return "https://dns.njal.la/dns-query"
        case .custom:
            return nil
        }
    }
}
