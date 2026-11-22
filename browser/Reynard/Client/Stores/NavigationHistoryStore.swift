//
//  NavigationHistoryStore.swift
//  Reynard
//
//  Created by Minh Ton on 17/5/26.
//

import GeckoView
import UIKit

final class NavigationHistoryStore {
    static let shared = NavigationHistoryStore()
    
    private let thumbnailJPEGQuality = 0.7
    private let keptEntriesPerSide = 5
    private let encodingQueue = DispatchQueue(label: "com.minh-ton.Reynard.NavigationHistoryStore.EncodingQueue", qos: .utility)
    private var thumbnails: [UUID: [GeckoSessionHistoryIdentifier: Data]] = [:]
    
    // MARK: - Thumbnails
    
    func thumbnail(for entry: GeckoSessionHistoryIdentifier?, in tabID: UUID) -> UIImage? {
        return entry.flatMap { thumbnails[tabID]?[$0] }.flatMap(UIImage.init(data:))
    }
    
    func updateThumbnail(
        _ image: UIImage,
        for entry: GeckoSessionHistoryIdentifier,
        in history: [GeckoSessionHistoryIdentifier],
        tabID: UUID,
        completion: @escaping () -> Void
    ) {
        var keptEntries: Set = [entry]
        if let entryIndex = history.firstIndex(of: entry) {
            let lowerBound = max(entryIndex - keptEntriesPerSide, 0)
            let upperBound = min(entryIndex + keptEntriesPerSide, history.count - 1)
            keptEntries.formUnion(history[lowerBound...upperBound])
        }
        
        encodingQueue.async {
            guard let thumbnailData = image.jpegData(compressionQuality: self.thumbnailJPEGQuality) else {
                return
            }
            
            DispatchQueue.main.async {
                var tabThumbnails = self.thumbnails[tabID, default: [:]].filter { keptEntries.contains($0.key) }
                tabThumbnails[entry] = thumbnailData
                self.thumbnails[tabID] = tabThumbnails
                completion()
            }
        }
    }
    
    func invalidateThumbnails() {
        thumbnails.removeAll()
    }
    
    func removeThumbnails(for tabID: UUID) {
        thumbnails.removeValue(forKey: tabID)
    }
}
