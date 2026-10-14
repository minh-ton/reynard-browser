//
//  SyncStorageClient.swift
//  Reynard
//
//  Tokenserver + Sync 1.5 storage API client (Hawk authenticated).
//

import Foundation

nonisolated struct SyncBSO {
    let id: String
    let modified: Double
    let payload: String
    var sortIndex: Int?
    var ttl: Int?

    init(id: String, modified: Double = 0, payload: String, sortIndex: Int? = nil, ttl: Int? = nil) {
        self.id = id
        self.modified = modified
        self.payload = payload
        self.sortIndex = sortIndex
        self.ttl = ttl
    }

    init?(json: [String: Any]) {
        guard let id = json["id"] as? String,
              let payload = json["payload"] as? String else {
            return nil
        }
        self.id = id
        self.modified = (json["modified"] as? NSNumber)?.doubleValue ?? 0
        self.payload = payload
        self.sortIndex = (json["sortindex"] as? NSNumber)?.intValue
        self.ttl = nil
    }

    var uploadJSON: [String: Any] {
        var json: [String: Any] = ["id": id, "payload": payload]
        if let sortIndex {
            json["sortindex"] = sortIndex
        }
        if let ttl {
            json["ttl"] = ttl
        }
        return json
    }
}

nonisolated struct SyncToken {
    let id: String
    let key: String
    let uid: String
    let apiEndpoint: String
    let expiresAt: Date
}

nonisolated enum SyncStorageError: Error, LocalizedError {
    case tokenserverRejected(Int, String)
    case unauthorized
    case notSetUp
    case unsupportedStorageVersion(Int)
    case keysUnavailable
    case serverBackoff(Int)
    case conflict

    var errorDescription: String? {
        switch self {
        case let .tokenserverRejected(status, body):
            return "The Sync token server refused the request (HTTP \(status)). \(body)"
        case .unauthorized:
            return "The Sync server rejected Reynard's credentials."
        case .notSetUp:
            return "Firefox Sync hasn't been set up for this account yet. Sign in to Firefox on a computer or Android device once, then try again."
        case let .unsupportedStorageVersion(version):
            return "This account uses Sync storage version \(version), which Reynard doesn't support."
        case .keysUnavailable:
            return "Reynard couldn't decrypt your Sync keys. If you recently reset your password, sign out and sign in again."
        case let .serverBackoff(seconds):
            return "The Sync server asked Reynard to wait \(seconds) seconds before syncing again."
        case .conflict:
            return "Another device changed your data during the sync. It will be retried."
        }
    }
}

final class SyncStorageClient {
    static let recordTTL = 1_814_400 // 21 days, matching Firefox for clients and tabs records.
    private static let maxRecordsPerPost = 50
    private static let maxBytesPerPost = 1_000_000

    let token: SyncToken
    private var clockSkew: Int64 = 0

    init(token: SyncToken) {
        self.token = token
    }

    // MARK: - Tokenserver

    static func fetchToken(tokenServerURL: URL, accessToken: String, keyID: String) async throws -> SyncToken {
        let request = try FxAHTTP.makeRequest(
            url: tokenServerURL,
            headers: [
                "Authorization": "Bearer \(accessToken)",
                "X-KeyID": keyID,
            ]
        )
        let response = try await FxAHTTP.send(request)
        if response.status == 401 {
            throw SyncStorageError.unauthorized
        }
        guard response.isSuccess else {
            throw SyncStorageError.tokenserverRejected(response.status, response.bodyText)
        }
        guard let json = response.jsonObject(),
              let id = json["id"] as? String,
              let key = json["key"] as? String,
              let apiEndpoint = json["api_endpoint"] as? String else {
            throw FxAHTTPError.invalidResponse("Malformed tokenserver response")
        }
        let uid = (json["uid"] as? NSNumber)?.stringValue ?? (json["uid"] as? String) ?? ""
        let duration = (json["duration"] as? NSNumber)?.doubleValue ?? 300
        return SyncToken(
            id: id,
            key: key,
            uid: uid,
            apiEndpoint: apiEndpoint,
            expiresAt: Date().addingTimeInterval(duration)
        )
    }

    // MARK: - Requests

    func makeURL(path: String, query: [URLQueryItem] = []) -> URL? {
        var base = token.apiEndpoint
        while base.hasSuffix("/") {
            base.removeLast()
        }
        guard var components = URLComponents(string: base + "/" + path) else {
            return nil
        }
        if !query.isEmpty {
            components.queryItems = query
        }
        return components.url
    }

    func send(
        method: String,
        path: String,
        query: [URLQueryItem] = [],
        json: Any? = nil,
        headers: [String: String] = [:]
    ) async throws -> FxAHTTPResponse {
        guard let url = makeURL(path: path, query: query) else {
            throw FxAHTTPError.invalidResponse("Invalid Sync storage URL for \(path)")
        }

        var attempt = 0
        while true {
            attempt += 1
            var request = try FxAHTTP.makeRequest(url: url, method: method, json: json, headers: headers)
            let timestamp = Int64(Date().timeIntervalSince1970) + clockSkew
            let nonce = (try? FxACrypto.randomBase64URL(byteCount: 8)) ?? UUID().uuidString
            guard let authorization = Hawk.header(
                credentials: HawkCredentials(id: token.id, key: Data(token.key.utf8)),
                method: method,
                url: url,
                timestamp: timestamp,
                nonce: nonce
            ) else {
                throw FxAHTTPError.invalidResponse("Could not sign the Sync request")
            }
            request.setValue(authorization, forHTTPHeaderField: "Authorization")

            let response = try await FxAHTTP.send(request)

            if response.status == 401,
               attempt == 1,
               let serverTime = response.header("X-Weave-Timestamp").flatMap(Double.init) {
                // Hawk rejects clocks that are more than a minute off; adopt the server's clock and retry.
                let skew = Int64(serverTime) - Int64(Date().timeIntervalSince1970)
                if abs(skew - clockSkew) > 30 {
                    clockSkew = skew
                    continue
                }
            }
            if response.status == 401 {
                throw SyncStorageError.unauthorized
            }
            if response.status == 503 {
                let seconds = Int(response.header("Retry-After") ?? response.header("X-Weave-Backoff") ?? "") ?? 300
                throw SyncStorageError.serverBackoff(seconds)
            }
            if response.status == 412 {
                throw SyncStorageError.conflict
            }
            return response
        }
    }

    static func formatTimestamp(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    // MARK: - Info

    func infoCollections() async throws -> [String: Double] {
        let response = try await send(method: "GET", path: "info/collections")
        guard response.isSuccess else {
            throw FxAHTTPError.unexpectedStatus(response.status, response.bodyText)
        }
        guard let json = response.jsonObject() else {
            return [:]
        }
        var result: [String: Double] = [:]
        for (name, value) in json {
            if let number = value as? NSNumber {
                result[name] = number.doubleValue
            }
        }
        return result
    }

    // MARK: - Records

    func getRecord(collection: String, id: String) async throws -> SyncBSO? {
        let response = try await send(method: "GET", path: "storage/\(collection)/\(id)")
        if response.status == 404 {
            return nil
        }
        guard response.isSuccess else {
            throw FxAHTTPError.unexpectedStatus(response.status, response.bodyText)
        }
        return response.jsonObject().flatMap(SyncBSO.init(json:))
    }

    struct CollectionResult {
        let records: [SyncBSO]
        let lastModified: Double
    }

    /// Fetches full records, following `X-Weave-Next-Offset` pagination.
    func getCollection(
        _ collection: String,
        newer: Double? = nil,
        ids: [String]? = nil,
        sort: String? = nil,
        pageSize: Int = 1_000,
        maxRecords: Int = 50_000
    ) async throws -> CollectionResult {
        var records: [SyncBSO] = []
        var offset: String?
        var lastModified: Double = 0

        repeat {
            var query = [URLQueryItem(name: "full", value: "1")]
            if let newer, newer > 0 {
                query.append(URLQueryItem(name: "newer", value: Self.formatTimestamp(newer)))
            }
            if let ids, !ids.isEmpty {
                query.append(URLQueryItem(name: "ids", value: ids.joined(separator: ",")))
            }
            if let sort {
                query.append(URLQueryItem(name: "sort", value: sort))
            }
            query.append(URLQueryItem(name: "limit", value: String(min(pageSize, maxRecords - records.count))))
            if let offset {
                query.append(URLQueryItem(name: "offset", value: offset))
            }

            let response = try await send(method: "GET", path: "storage/\(collection)", query: query)
            if response.status == 404 {
                return CollectionResult(records: [], lastModified: 0)
            }
            guard response.isSuccess else {
                throw FxAHTTPError.unexpectedStatus(response.status, response.bodyText)
            }
            if let modified = response.header("X-Last-Modified").flatMap(Double.init) {
                lastModified = max(lastModified, modified)
            }
            let page = (response.jsonArray() ?? []).compactMap(SyncBSO.init(json:))
            records.append(contentsOf: page)
            offset = response.header("X-Weave-Next-Offset")
        } while offset != nil && records.count < maxRecords

        if lastModified == 0 {
            lastModified = records.map(\.modified).max() ?? 0
        }
        return CollectionResult(records: records, lastModified: lastModified)
    }

    struct PostResult {
        var succeeded: [String] = []
        var failed: [String] = []
        var lastModified: Double = 0
    }

    /// Uploads records in chunks the server accepts.
    func post(collection: String, records: [SyncBSO], ifUnmodifiedSince: Double? = nil) async throws -> PostResult {
        var result = PostResult()
        var chunk: [[String: Any]] = []
        var chunkBytes = 0
        var unmodifiedSince = ifUnmodifiedSince

        func flush() async throws {
            guard !chunk.isEmpty else {
                return
            }
            var headers: [String: String] = [:]
            if let unmodifiedSince {
                headers["X-If-Unmodified-Since"] = Self.formatTimestamp(unmodifiedSince)
            }
            let response = try await send(method: "POST", path: "storage/\(collection)", json: chunk, headers: headers)
            guard response.isSuccess else {
                throw FxAHTTPError.unexpectedStatus(response.status, response.bodyText)
            }
            let json = response.jsonObject() ?? [:]
            result.succeeded.append(contentsOf: json["success"] as? [String] ?? [])
            if let failed = json["failed"] as? [String: Any] {
                result.failed.append(contentsOf: failed.keys)
            }
            if let modified = (json["modified"] as? NSNumber)?.doubleValue
                ?? response.header("X-Last-Modified").flatMap(Double.init) {
                result.lastModified = max(result.lastModified, modified)
                // Later chunks must be checked against our own write, not the original timestamp.
                if unmodifiedSince != nil {
                    unmodifiedSince = modified
                }
            }
            chunk.removeAll()
            chunkBytes = 0
        }

        for record in records {
            let json = record.uploadJSON
            let size = record.payload.utf8.count + 128
            if chunk.count >= Self.maxRecordsPerPost || chunkBytes + size > Self.maxBytesPerPost {
                try await flush()
            }
            chunk.append(json)
            chunkBytes += size
        }
        try await flush()
        return result
    }
}
