//
//  SearchCompletion.swift
//  Reynard
//
//  Created by Minh Ton on 11/6/26.
//

import Foundation

final class SearchCompletion {
    enum Provider {
        case google
        case yahoo
        case bing
        case duckduckgo
        case ecosia
        case startpage
    }
    
    let provider: Provider
    private let urlSession: URLSession
    
    init(provider: Provider = .google, urlSession: URLSession = .shared) {
        self.provider = provider
        self.urlSession = urlSession
    }
    
    func fetchCompletions(
        for query: String,
        completion: @escaping ([String]) -> Void
    ) -> URLSessionDataTask? {
        guard let url = provider.url(for: query) else {
            completion([])
            return nil
        }
        
        let task = urlSession.dataTask(with: url) { data, response, error in
            if let error = error as NSError?,
               error.domain == NSURLErrorDomain,
               error.code == NSURLErrorCancelled {
                return
            }
            
            completion(Self.parse(data: data, response: response))
        }
        task.resume()
        return task
    }
}

extension SearchCompletion.Provider {
    var name: String {
        switch self {
        case .google: return "Google"
        case .yahoo: return "Yahoo"
        case .bing: return "Bing"
        case .duckduckgo: return "DuckDuckGo"
        case .ecosia: return "Ecosia"
        case .startpage: return "Startpage"
        }
    }
}

private extension SearchCompletion.Provider {
    func url(for query: String) -> URL? {
        let endpoint: String
        let queryItems: [URLQueryItem]
        switch self {
        case .google:
            endpoint = "https://www.google.com/complete/search"
            queryItems = [
                URLQueryItem(name: "client", value: "firefox"),
                URLQueryItem(name: "q", value: query),
            ]
        case .yahoo:
            endpoint = "https://search.yahoo.com/sugg/chrome"
            queryItems = [
                URLQueryItem(name: "output", value: "fxjson"),
                URLQueryItem(name: "command", value: query),
            ]
        case .bing:
            endpoint = "https://api.bing.com/osjson.aspx"
            queryItems = [URLQueryItem(name: "query", value: query)]
        case .duckduckgo:
            endpoint = "https://duckduckgo.com/ac/"
            queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "type", value: "list"),
            ]
        case .ecosia:
            endpoint = "https://ac.ecosia.org/autocomplete"
            queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "type", value: "list"),
            ]
        case .startpage:
            endpoint = "https://www.startpage.com/osuggestions"
            queryItems = [URLQueryItem(name: "q", value: query)]
        }
        
        var components = URLComponents(string: endpoint)
        components?.queryItems = queryItems
        return components?.url
    }
}

private extension SearchCompletion {
    static func parse(data: Data?, response: URLResponse?) -> [String] {
        guard let data,
              let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              let payload = decodePayload(data: data, response: response),
              payload.count > 1,
              let suggestions = payload[1] as? [Any] else {
            return []
        }
        
        return suggestions.compactMap { value in
            guard let suggestion = value as? String else {
                return nil
            }
            
            let trimmed = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
    
    static func decodePayload(data: Data, response: URLResponse) -> [Any]? {
        if let payload = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            return payload
        }
        
        guard let encodingName = response.textEncodingName,
              let encoding = String.Encoding.ianaCharacterSetName(encodingName),
              let text = String(data: data, encoding: encoding),
              let utf8Data = text.data(using: .utf8) else {
            return nil
        }
        
        return try? JSONSerialization.jsonObject(with: utf8Data) as? [Any]
    }
}
