//
//  PayloadValue.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import CoreGraphics
import Foundation

enum PayloadValue {
    static func string(_ value: Any?) -> String? {
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    static func strings(_ value: Any?) -> [String] {
        if let strings = value as? [String] {
            return strings.filter { !$0.isEmpty }
        }
        if let strings = value as? [NSString] {
            return strings.map { $0 as String }.filter { !$0.isEmpty }
        }
        if let values = value as? [Any] {
            return values.compactMap { string($0) }.filter { !$0.isEmpty }
        }
        return []
    }

    static func int(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        return nil
    }

    static func bool(_ value: Any?) -> Bool? {
        if let value = value as? Bool {
            return value
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        return nil
    }

    static func int32(_ value: Any?) -> Int32? {
        if let value = value as? Int32 {
            return value
        }
        if let number = value as? NSNumber {
            return number.int32Value
        }
        return nil
    }

    static func int64(_ value: Any?) -> Int64? {
        if let value = value as? Int64 {
            return value
        }
        if let value = value as? Int {
            return Int64(value)
        }
        if let number = value as? NSNumber {
            return number.int64Value
        }
        return nil
    }

    static func double(_ value: Any?) -> Double? {
        if let value = value as? Double {
            return value
        }
        if let value = value as? Int {
            return Double(value)
        }
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        return nil
    }

    static func cgFloat(_ value: Any?) -> CGFloat? {
        if let value = value as? CGFloat {
            return value
        }
        return double(value).map { CGFloat($0) }
    }
}
