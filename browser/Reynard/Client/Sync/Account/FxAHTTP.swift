//
//  FxAHTTP.swift
//  Reynard
//
//  Small async wrapper over URLSession that works on iOS 13
//  (URLSession's own async APIs require iOS 15).
//

import Foundation

nonisolated struct FxAHTTPResponse {
    let status: Int
    let headers: [AnyHashable: Any]
    let body: Data

    var isSuccess: Bool {
        (200..<300).contains(status)
    }

    func header(_ name: String) -> String? {
        let lowered = name.lowercased()
        for (key, value) in headers {
            if let key = key as? String, key.lowercased() == lowered {
                return value as? String ?? "\(value)"
            }
        }
        return nil
    }

    func jsonObject() -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    }

    func jsonArray() -> [[String: Any]]? {
        (try? JSONSerialization.jsonObject(with: body)) as? [[String: Any]]
    }

    var bodyText: String {
        String(decoding: body.prefix(2_000), as: UTF8.self)
    }
}

nonisolated enum FxAHTTPError: Error, LocalizedError {
    case transport(String)
    case unexpectedStatus(Int, String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case let .transport(message):
            return message
        case let .unexpectedStatus(status, body):
            let detail = body.isEmpty ? "" : " \(body)"
            return "Server returned HTTP \(status).\(detail)"
        case let .invalidResponse(message):
            return message
        }
    }
}

nonisolated enum FxAHTTP {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: configuration)
    }()

    static func send(_ request: URLRequest) async throws -> FxAHTTPResponse {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: FxAHTTPError.transport(error.localizedDescription))
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                    continuation.resume(throwing: FxAHTTPError.invalidResponse("No HTTP response"))
                    return
                }
                continuation.resume(returning: FxAHTTPResponse(
                    status: httpResponse.statusCode,
                    headers: httpResponse.allHeaderFields,
                    body: data ?? Data()
                ))
            }
            task.resume()
        }
    }

    static func makeRequest(
        url: URL,
        method: String = "GET",
        json: Any? = nil,
        headers: [String: String] = [:]
    ) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let json {
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    static func getJSON(_ url: URL, headers: [String: String] = [:]) async throws -> [String: Any] {
        let response = try await send(makeRequest(url: url, headers: headers))
        guard response.isSuccess else {
            throw FxAHTTPError.unexpectedStatus(response.status, response.bodyText)
        }
        guard let object = response.jsonObject() else {
            throw FxAHTTPError.invalidResponse("Expected a JSON object from \(url.host ?? "server")")
        }
        return object
    }

    static func postJSON(_ url: URL, body: Any, headers: [String: String] = [:]) async throws -> [String: Any] {
        let response = try await send(makeRequest(url: url, method: "POST", json: body, headers: headers))
        guard response.isSuccess else {
            throw FxAHTTPError.unexpectedStatus(response.status, response.bodyText)
        }
        return response.jsonObject() ?? [:]
    }
}
