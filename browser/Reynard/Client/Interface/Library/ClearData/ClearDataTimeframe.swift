//
//  ClearDataTimeframe.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import UIKit

enum ClearDataTimeframe: Int, CaseIterable {
    case lastHour
    case today
    case todayAndYesterday
    case allTime
    
    var title: String {
        switch self {
        case .lastHour:
            return NSLocalizedString("Last hour", comment: "")
        case .today:
            return NSLocalizedString("Today", comment: "")
        case .todayAndYesterday:
            return NSLocalizedString("Today and yesterday", comment: "")
        case .allTime:
            return NSLocalizedString("All history", comment: "")
        }
    }
    
    func cutoffDate(from now: Date = Date(), calendar: Calendar = .current) -> Date? {
        switch self {
        case .lastHour:
            return now.addingTimeInterval(-3_600)
        case .today:
            return calendar.startOfDay(for: now)
        case .todayAndYesterday:
            return calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))
        case .allTime:
            return nil
        }
    }
    
    static func configureCell(_ cell: UITableViewCell, at indexPath: IndexPath, selectedTimeframe: ClearDataTimeframe) {
        let option = allCases[indexPath.row]
        cell.textLabel?.text = option.title
        cell.accessoryView = nil
        cell.accessoryType = option == selectedTimeframe ? .checkmark : .none
        cell.selectionStyle = .default
    }
}
