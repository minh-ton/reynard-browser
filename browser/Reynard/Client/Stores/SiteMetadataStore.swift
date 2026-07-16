//
//  SiteMetadataStore.swift
//  Reynard
//
//  Created by Minh Ton on 24/6/26.
//

import CryptoKit
import Foundation
import UIKit

struct SiteMetadataSnapshot {
    let url: URL
    let finalURL: URL
    let metadata: [String: String]
    let ogImageKey: String?
    let ogImage: UIImage?
}

struct SiteMetadataRecord: Codable {
    let url: String
    let finalURL: String
    let metadata: [String: String]
    let ogImageKey: String?
    let updatedAt: Date
}

final class SiteMetadataStore {
    static let shared = SiteMetadataStore()
    
    private static let directoryName = "SiteMetadata"
    private static let indexFileName = "SiteMetadataStore"
    private static let imageFilePrefix = "img-"
    private static let maxHTMLBytes = 768 * 1024
    private static let maxImageBytes = 4 * 1024 * 1024
    private static let maxRedirectDepth = 3
    
    private struct StorageURLs {
        let directoryURL: URL
        let indexURL: URL
    }
    
    private struct HTMLDocument {
        let html: String
        let url: URL
    }
    
    private struct RemoteImage {
        let image: UIImage
        let data: Data
        let url: URL
    }
    
    private let fileManager: FileManager
    private let storage: StorageURLs
    private let stateQueue = DispatchQueue(label: "com.minh-ton.Reynard.SiteMetadataStore.Queue", qos: .utility)
    private var records: [String: SiteMetadataRecord] = [:]
    private var activeRequests: [String: Task<SiteMetadataSnapshot?, Never>] = [:]
    
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 15
        return URLSession(configuration: configuration)
    }()
    
    private lazy var metaTagExpression = try! NSRegularExpression(
        pattern: "(?is)<meta\\b[^>]*>",
        options: []
    )
    private lazy var attributeExpression = try! NSRegularExpression(
        pattern: "(?is)([A-Za-z_:][-A-Za-z0-9_:.]*)\\s*=\\s*(\"([^\"]*)\"|'([^']*)'|([^\\s>]+))",
        options: []
    )
    
    // MARK: - Lifecycle
    
    init(
        fileManager: FileManager = .default,
        directories: ReynardDirectories = .shared
    ) {
        self.fileManager = fileManager
        let directoryURL = directories.appData
            .appendingPathComponent(Self.directoryName, isDirectory: true)
        
        self.storage = StorageURLs(
            directoryURL: directoryURL,
            indexURL: directoryURL.appendingPathComponent(Self.indexFileName, isDirectory: false)
        )
        
        stateQueue.sync {
            prepareStorageLocked()
            loadRecordsLocked()
        }
    }
    
    // MARK: - Metadata
    
    func cachedMetadata(for url: URL) -> SiteMetadataSnapshot? {
        guard let sanitizedURL = URLUtils.sanitizedURL(for: url) else {
            return nil
        }
        
        return stateQueue.sync {
            snapshotLocked(for: sanitizedURL)
        }
    }
    
    func metadata(for url: URL) async -> SiteMetadataSnapshot? {
        guard let sanitizedURL = URLUtils.sanitizedURL(for: url) else {
            return nil
        }
        
        if let snapshot = stateQueue.sync(execute: { snapshotLocked(for: sanitizedURL) }) {
            return snapshot
        }
        
        return await saveMetadata(for: sanitizedURL)
    }
    
    func saveMetadata(for url: URL) async -> SiteMetadataSnapshot? {
        guard let sanitizedURL = URLUtils.sanitizedURL(for: url) else {
            return nil
        }
        
        let requestKey = sanitizedURL.absoluteString
        if let activeRequest = stateQueue.sync(execute: { activeRequests[requestKey] }) {
            return await activeRequest.value
        }
        
        let task = Task<SiteMetadataSnapshot?, Never>(priority: .utility) { [weak self] in
            guard let self else {
                return nil
            }
            
            let snapshot = await self.fetchAndStoreMetadata(for: sanitizedURL)
            self.stateQueue.async {
                self.activeRequests[requestKey] = nil
            }
            return snapshot
        }
        
        stateQueue.sync {
            activeRequests[requestKey] = task
        }
        return await task.value
    }
    
    func prune(keeping urls: [URL]) {
        let retainedKeys = Set(urls.compactMap { URLUtils.sanitizedURL(for: $0)?.absoluteString })
        stateQueue.async {
            let removedRecords = self.records.filter { key, _ in
                !retainedKeys.contains(key)
            }
            
            guard !removedRecords.isEmpty else {
                return
            }
            
            for key in removedRecords.keys {
                self.records[key] = nil
            }
            
            self.removeUnreferencedImagesLocked(removedImageKeys: removedRecords.values.compactMap(\.ogImageKey))
            self.saveRecordsLocked()
        }
    }
    
    // MARK: - Storage
    
    private func prepareStorageLocked() {
        try? fileManager.createDirectory(at: storage.directoryURL, withIntermediateDirectories: true)
    }
    
    private func loadRecordsLocked() {
        guard let data = try? Data(contentsOf: storage.indexURL) else {
            records = [:]
            return
        }
        
        records = (try? JSONDecoder().decode([String: SiteMetadataRecord].self, from: data)) ?? [:]
    }
    
    private func saveRecordsLocked() {
        guard let data = try? JSONEncoder().encode(records) else {
            return
        }
        
        try? data.write(to: storage.indexURL, options: .atomic)
    }
    
    private func snapshotLocked(for sanitizedURL: URL) -> SiteMetadataSnapshot? {
        guard let record = records[sanitizedURL.absoluteString],
              let url = URL(string: record.url),
              let finalURL = URL(string: record.finalURL) else {
            return nil
        }
        
        return SiteMetadataSnapshot(
            url: url,
            finalURL: finalURL,
            metadata: record.metadata,
            ogImageKey: record.ogImageKey,
            ogImage: record.ogImageKey.flatMap(loadImageLocked)
        )
    }
    
    private func storeLocked(sanitizedURL: URL, finalURL: URL, metadata: [String: String], remoteImage: RemoteImage?) -> SiteMetadataSnapshot {
        let imageKey: String?
        if let remoteImage {
            let key = Self.sha256(remoteImage.data)
            let imageURL = imageFileURL(for: key)
            if !fileManager.fileExists(atPath: imageURL.path) {
                try? remoteImage.data.write(to: imageURL, options: .atomic)
            }
            imageKey = key
        } else {
            imageKey = nil
        }
        
        let record = SiteMetadataRecord(
            url: sanitizedURL.absoluteString,
            finalURL: finalURL.absoluteString,
            metadata: metadata,
            ogImageKey: imageKey,
            updatedAt: Date()
        )
        records[sanitizedURL.absoluteString] = record
        saveRecordsLocked()
        
        return SiteMetadataSnapshot(
            url: sanitizedURL,
            finalURL: finalURL,
            metadata: metadata,
            ogImageKey: imageKey,
            ogImage: remoteImage?.image
        )
    }
    
    private func loadImageLocked(for imageKey: String) -> UIImage? {
        guard let data = try? Data(contentsOf: imageFileURL(for: imageKey)),
              let image = UIImage(data: data) else {
            return nil
        }
        
        return image
    }
    
    private func removeUnreferencedImagesLocked(removedImageKeys: [String]) {
        let retainedImageKeys = Set(records.values.compactMap(\.ogImageKey))
        for imageKey in removedImageKeys where !retainedImageKeys.contains(imageKey) {
            let imageURL = imageFileURL(for: imageKey)
            if fileManager.fileExists(atPath: imageURL.path) {
                try? fileManager.removeItem(at: imageURL)
            }
        }
    }
    
    private func imageFileURL(for imageKey: String) -> URL {
        storage.directoryURL.appendingPathComponent(Self.imageFilePrefix + imageKey, isDirectory: false)
    }
    
    // MARK: - Fetching
    
    private func fetchAndStoreMetadata(for sanitizedURL: URL) async -> SiteMetadataSnapshot? {
        guard let document = await fetchHTMLDocument(for: sanitizedURL, redirectDepth: 0) else {
            return nil
        }
        
        let metadata = openGraphMetadata(in: document.html)
        let remoteImage: RemoteImage?
        if let imageValue = metadata["og:image"],
           let imageURL = URL(string: decodeHTMLEntities(in: imageValue), relativeTo: document.url)?.absoluteURL {
            remoteImage = await fetchRemoteImage(from: imageURL)
        } else {
            remoteImage = nil
        }
        
        return stateQueue.sync {
            storeLocked(
                sanitizedURL: sanitizedURL,
                finalURL: document.url,
                metadata: metadata,
                remoteImage: remoteImage
            )
        }
    }
    
    private func fetchHTMLDocument(for url: URL, redirectDepth: Int) async -> HTMLDocument? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        
        guard let (data, response) = await data(for: request),
              data.count <= Self.maxHTMLBytes else {
            return nil
        }
        
        let mimeType = (response.mimeType ?? "").lowercased()
        guard mimeType.isEmpty || mimeType.contains("html") || mimeType.contains("xml") else {
            return nil
        }
        
        let html = string(from: data, response: response)
        guard !html.isEmpty else {
            return nil
        }
        
        let finalURL = response.url ?? url
        if redirectDepth < Self.maxRedirectDepth,
           let redirectURL = metaRefreshRedirectURL(in: html, baseURL: finalURL),
           redirectURL != finalURL {
            return await fetchHTMLDocument(for: redirectURL, redirectDepth: redirectDepth + 1)
        }
        
        return HTMLDocument(html: html, url: finalURL)
    }
    
    private func fetchRemoteImage(from url: URL) async -> RemoteImage? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        
        guard let (data, response) = await data(for: request),
              data.count <= Self.maxImageBytes,
              let image = UIImage(data: data) else {
            return nil
        }
        
        return RemoteImage(image: image, data: data, url: response.url ?? url)
    }
    
    private func data(for request: URLRequest) async -> (Data, URLResponse)? {
        await withCheckedContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                guard error == nil,
                      let data,
                      let response else {
                    continuation.resume(returning: nil)
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    continuation.resume(returning: nil)
                    return
                }
                
                continuation.resume(returning: (data, response))
            }
            task.resume()
        }
    }
    
    // MARK: - HTML Parsing
    
    private func openGraphMetadata(in html: String) -> [String: String] {
        let nsHTML = html as NSString
        let matches = metaTagExpression.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        var result: [String: String] = [:]
        
        for match in matches {
            let tag = nsHTML.substring(with: match.range)
            let attributes = attributes(in: tag)
            let property = attributes["property"] ?? attributes["name"] ?? ""
            let content = attributes["content"] ?? ""
            
            guard property.lowercased().hasPrefix("og:"),
                  !content.isEmpty else {
                continue
            }
            
            result[property.lowercased()] = decodeHTMLEntities(in: content)
        }
        
        return result
    }
    
    private func attributes(in tag: String) -> [String: String] {
        let nsTag = tag as NSString
        let matches = attributeExpression.matches(in: tag, range: NSRange(location: 0, length: nsTag.length))
        var result: [String: String] = [:]
        
        for match in matches {
            guard match.numberOfRanges >= 6 else {
                continue
            }
            
            let name = nsTag.substring(with: match.range(at: 1)).lowercased()
            let value: String
            if match.range(at: 3).location != NSNotFound {
                value = nsTag.substring(with: match.range(at: 3))
            } else if match.range(at: 4).location != NSNotFound {
                value = nsTag.substring(with: match.range(at: 4))
            } else if match.range(at: 5).location != NSNotFound {
                value = nsTag.substring(with: match.range(at: 5))
            } else {
                value = ""
            }
            
            result[name] = value
        }
        
        return result
    }
    
    private func metaRefreshRedirectURL(in html: String, baseURL: URL) -> URL? {
        let nsHTML = html as NSString
        let matches = metaTagExpression.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        
        for match in matches {
            let tag = nsHTML.substring(with: match.range)
            let attributes = attributes(in: tag)
            let httpEquiv = attributes["http-equiv"]?.lowercased() ?? ""
            guard httpEquiv == "refresh",
                  let content = attributes["content"] else {
                continue
            }
            
            let parts = content.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else {
                continue
            }
            
            let redirectPart = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard redirectPart.lowercased().hasPrefix("url=") else {
                continue
            }
            
            let value = redirectPart.dropFirst(4).trimmingCharacters(in: .whitespacesAndNewlines)
            let unquotedValue = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if let redirectURL = URL(string: decodeHTMLEntities(in: unquotedValue), relativeTo: baseURL)?.absoluteURL {
                return redirectURL
            }
        }
        
        return nil
    }
    
    private func string(from data: Data, response: URLResponse) -> String {
        if let encodingName = response.textEncodingName,
           let encoding = String.Encoding.ianaCharacterSetName(encodingName),
           let string = String(data: data, encoding: encoding) {
            return string
        }
        
        if let string = String(data: data, encoding: .utf8) {
            return string
        }
        
        if let string = String(data: data, encoding: .isoLatin1) {
            return string
        }
        
        return ""
    }
    
    private func decodeHTMLEntities(in string: String) -> String {
        string
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
    
    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
