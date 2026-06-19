//
//  HistorySection.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import Foundation

struct HistorySection {
    let day: Date
    let title: String
    var items: [HistorySiteSnapshot]
}

extension HistorySection {
    static func make(from items: [HistorySiteSnapshot]) -> [HistorySection] {
        guard !items.isEmpty else {
            return []
        }
        
        let calendar = Calendar.current
        let groupedItems = Dictionary(grouping: items) { item in
            calendar.startOfDay(for: item.lastVisitedAt)
        }
        
        return groupedItems.keys.sorted(by: >).compactMap { day in
            guard let items = groupedItems[day] else {
                return nil
            }
            
            let sortedItems = items.sorted { $0.lastVisitedAt > $1.lastVisitedAt }
            return HistorySection(day: day, title: title(for: day, calendar: calendar), items: sortedItems)
        }
    }
    
    private static func title(for date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) {
            return "Today"
        }
        
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        
        return dateTitleFormatter.string(from: date)
    }
    
    private static let dateTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEEE, d MMMM")
        return formatter
    }()
}
