//
//  DownloadSection.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import Foundation

struct DownloadSection {
    let title: String
    let items: [DownloadItemSnapshot]
}

struct DownloadSectionFingerprint: Equatable {
    let title: String
    let itemIDs: [UUID]
}

extension DownloadSection {
    static func make(from items: [DownloadItemSnapshot]) -> [DownloadSection] {
        guard !items.isEmpty else {
            return []
        }
        
        var todayItems: [DownloadItemSnapshot] = []
        var yesterdayItems: [DownloadItemSnapshot] = []
        var previousSevenDayItems: [DownloadItemSnapshot] = []
        var previousThirtyDayItems: [DownloadItemSnapshot] = []
        var monthlyItems: [DateComponents: [DownloadItemSnapshot]] = [:]
        let calendar = Calendar.current
        let now = Date()
        
        for item in items {
            let startOfItemDay = calendar.startOfDay(for: item.addedAt)
            let startOfToday = calendar.startOfDay(for: now)
            let dayDifference = calendar.dateComponents([.day], from: startOfItemDay, to: startOfToday).day ?? 0
            
            switch dayDifference {
            case Int.min..<1:
                todayItems.append(item)
            case 1:
                yesterdayItems.append(item)
            case 2...7:
                previousSevenDayItems.append(item)
            case 8...30:
                previousThirtyDayItems.append(item)
            default:
                let components = calendar.dateComponents([.year, .month], from: item.addedAt)
                monthlyItems[components, default: []].append(item)
            }
        }
        
        var sections: [DownloadSection] = []
        appendRelativeSections(
            to: &sections,
            todayItems: todayItems,
            yesterdayItems: yesterdayItems,
            previousSevenDayItems: previousSevenDayItems,
            previousThirtyDayItems: previousThirtyDayItems
        )
        appendMonthlySections(to: &sections, monthlyItems: monthlyItems, calendar: calendar, now: now)
        return sections
    }
    
    private static func appendRelativeSections(
        to sections: inout [DownloadSection],
        todayItems: [DownloadItemSnapshot],
        yesterdayItems: [DownloadItemSnapshot],
        previousSevenDayItems: [DownloadItemSnapshot],
        previousThirtyDayItems: [DownloadItemSnapshot]
    ) {
        if !todayItems.isEmpty {
            sections.append(DownloadSection(title: "Today", items: todayItems))
        }
        if !yesterdayItems.isEmpty {
            sections.append(DownloadSection(title: "Yesterday", items: yesterdayItems))
        }
        if !previousSevenDayItems.isEmpty {
            sections.append(DownloadSection(title: "Previous 7 Days", items: previousSevenDayItems))
        }
        if !previousThirtyDayItems.isEmpty {
            sections.append(DownloadSection(title: "Previous 30 Days", items: previousThirtyDayItems))
        }
    }
    
    private static func appendMonthlySections(
        to sections: inout [DownloadSection],
        monthlyItems: [DateComponents: [DownloadItemSnapshot]],
        calendar: Calendar,
        now: Date
    ) {
        let currentYear = calendar.component(.year, from: now)
        let sortedMonthComponents = monthlyItems.keys.sorted { lhs, rhs in
            let leftYear = lhs.year ?? 0
            let rightYear = rhs.year ?? 0
            if leftYear != rightYear {
                return leftYear > rightYear
            }
            
            return (lhs.month ?? 0) > (rhs.month ?? 0)
        }
        
        for components in sortedMonthComponents {
            guard let year = components.year,
                  let month = components.month,
                  let items = monthlyItems[components],
                  let titleDate = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else {
                continue
            }
            
            let title = year == currentYear ? monthTitleFormatter.string(from: titleDate) : monthYearTitleFormatter.string(from: titleDate)
            sections.append(DownloadSection(title: title, items: items))
        }
    }
    
    private static let monthTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMMM")
        return formatter
    }()
    
    private static let monthYearTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter
    }()
}
