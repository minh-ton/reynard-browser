//
//  WebsiteLanguageCatalog.swift
//  Reynard
//
//  Created by Minh Ton on 11/7/26.
//

import Foundation

struct WebsiteLanguage: Equatable {
    let code: String
    let title: String
}

enum WebsiteLanguageCatalog {
    private static let titleLocale = Locale(identifier: "en")
    
    private static let fallbackTitles = [
        "cak": "Kaqchikel",
        "meh": "Southwestern Tlaxiaco Mixtec",
        "mix": "Mixtepec Mixtec",
        "skr": "Saraiki",
        "son": "Songhay",
        "son-ml": "Songhay (Mali)",
        "trs": "Triqui",
        "zam": "Miahuatlán Zapotec",
    ]
    
    static let supportedCodes = [
        "aa",
        "ab",
        "ach",
        "ae",
        "af",
        "ak",
        "am",
        "an",
        "ar",
        "ar-ae",
        "ar-bh",
        "ar-dz",
        "ar-eg",
        "ar-iq",
        "ar-jo",
        "ar-kw",
        "ar-lb",
        "ar-ly",
        "ar-ma",
        "ar-om",
        "ar-qa",
        "ar-sa",
        "ar-sy",
        "ar-tn",
        "ar-ye",
        "as",
        "ast",
        "av",
        "ay",
        "az",
        "ba",
        "be",
        "bg",
        "bh",
        "bi",
        "bm",
        "bn",
        "bo",
        "br",
        "bs",
        "ca",
        "ca-valencia",
        "cak",
        "ce",
        "ch",
        "co",
        "cr",
        "crh",
        "cs",
        "csb",
        "cu",
        "cv",
        "cy",
        "da",
        "de",
        "de-at",
        "de-ch",
        "de-de",
        "de-li",
        "de-lu",
        "dsb",
        "dv",
        "dz",
        "ee",
        "el",
        "en",
        "en-au",
        "en-bz",
        "en-ca",
        "en-gb",
        "en-ie",
        "en-jm",
        "en-nz",
        "en-ph",
        "en-tt",
        "en-us",
        "en-za",
        "en-zw",
        "eo",
        "es",
        "es-ar",
        "es-bo",
        "es-cl",
        "es-co",
        "es-cr",
        "es-do",
        "es-ec",
        "es-es",
        "es-gt",
        "es-hn",
        "es-mx",
        "es-ni",
        "es-pa",
        "es-pe",
        "es-pr",
        "es-py",
        "es-sv",
        "es-uy",
        "es-ve",
        "et",
        "eu",
        "fa",
        "fa-ir",
        "ff",
        "fi",
        "fj",
        "fo",
        "fr",
        "fr-be",
        "fr-ca",
        "fr-ch",
        "fr-fr",
        "fr-lu",
        "fr-mc",
        "fur",
        "fy",
        "ga",
        "gd",
        "gl",
        "gn",
        "gu",
        "gv",
        "ha",
        "haw",
        "he",
        "hi",
        "hil",
        "ho",
        "hr",
        "hsb",
        "ht",
        "hu",
        "hy",
        "hz",
        "ia",
        "id",
        "ie",
        "ig",
        "ii",
        "ik",
        "io",
        "is",
        "it",
        "it-ch",
        "iu",
        "ja",
        "jv",
        "ka",
        "kab",
        "kg",
        "ki",
        "kk",
        "kl",
        "km",
        "kn",
        "ko",
        "ko-kp",
        "ko-kr",
        "kok",
        "kr",
        "ks",
        "ku",
        "kv",
        "kw",
        "ky",
        "la",
        "lb",
        "lg",
        "li",
        "lij",
        "ln",
        "lo",
        "lt",
        "ltg",
        "lu",
        "lv",
        "mai",
        "meh",
        "mg",
        "mh",
        "mi",
        "mix",
        "mk",
        "mk-mk",
        "ml",
        "mn",
        "mr",
        "ms",
        "mt",
        "my",
        "na",
        "nb",
        "nd",
        "ne",
        "ng",
        "nl",
        "nl-be",
        "nn",
        "no",
        "nr",
        "nso",
        "nv",
        "ny",
        "oc",
        "oj",
        "om",
        "or",
        "os",
        "pa",
        "pa-in",
        "pa-pk",
        "pi",
        "pl",
        "ps",
        "pt",
        "pt-br",
        "pt-pt",
        "qu",
        "rm",
        "rn",
        "ro",
        "ro-md",
        "ro-ro",
        "ru",
        "ru-md",
        "rw",
        "sa",
        "sat",
        "sc",
        "sco",
        "sd",
        "sg",
        "si",
        "sk",
        "skr",
        "sl",
        "sm",
        "so",
        "son",
        "son-ml",
        "sq",
        "sr",
        "ss",
        "st",
        "su",
        "sv",
        "sv-fi",
        "sv-se",
        "sw",
        "szl",
        "ta",
        "te",
        "tg",
        "th",
        "ti",
        "tig",
        "tk",
        "tl",
        "tlh",
        "tn",
        "to",
        "tr",
        "trs",
        "ts",
        "tt",
        "tw",
        "ty",
        "ug",
        "uk",
        "ur",
        "uz",
        "ve",
        "vi",
        "vo",
        "wa",
        "wo",
        "xh",
        "yi",
        "yo",
        "za",
        "zam",
        "zh",
        "zh-cn",
        "zh-hk",
        "zh-sg",
        "zh-tw",
        "zu",
    ]
    
    private static let supportedCodeSet = Set(supportedCodes)
    
    static var supportedLanguages: [WebsiteLanguage] {
        return supportedCodes.compactMap { code in
            language(for: code)
        }
    }
    
    static var sortedSupportedLanguages: [WebsiteLanguage] {
        return supportedLanguages.sorted { lhs, rhs in
            let titleComparison = lhs.title.localizedStandardCompare(rhs.title)
            if titleComparison == .orderedSame {
                return lhs.code.localizedStandardCompare(rhs.code) == .orderedAscending
            }
            return titleComparison == .orderedAscending
        }
    }
    
    static func language(for code: String) -> WebsiteLanguage? {
        guard let normalizedCode = normalizedCode(code) else {
            return nil
        }
        return WebsiteLanguage(code: normalizedCode, title: title(for: normalizedCode))
    }
    
    static func title(for code: String) -> String {
        let normalizedCode = normalizedCode(code) ?? code
        let title = fallbackTitles[normalizedCode] ??
        titleLocale.localizedString(forIdentifier: normalizedCode) ??
        normalizedCode
        assert(!title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        return title
    }
    
    static func normalizedCode(_ code: String) -> String? {
        let value = code
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        guard !value.isEmpty else {
            return nil
        }
        
        if supportedCodeSet.contains(value) {
            return value
        }
        
        let parts = value.split(separator: "-").map(String.init)
        guard let languageCode = parts.first else {
            return nil
        }
        
        if let regionCode = parts.last,
           parts.count > 1 {
            let languageRegionCode = "\(languageCode)-\(regionCode)"
            if supportedCodeSet.contains(languageRegionCode) {
                return languageRegionCode
            }
        }
        
        if supportedCodeSet.contains(languageCode) {
            return languageCode
        }
        
        return nil
    }
    
    static func sanitizedLanguageCodes(_ codes: [String]) -> [String] {
        var seenCodes = Set<String>()
        var values: [String] = []
        
        for code in codes {
            guard let normalizedCode = normalizedCode(code),
                  !seenCodes.contains(normalizedCode) else {
                continue
            }
            seenCodes.insert(normalizedCode)
            values.append(normalizedCode)
        }
        
        if values.isEmpty {
            return ["en"]
        }
        return values
    }
    
    static func defaultLanguageCodes() -> [String] {
        return sanitizedLanguageCodes(Locale.preferredLanguages + ["en"])
    }
}
