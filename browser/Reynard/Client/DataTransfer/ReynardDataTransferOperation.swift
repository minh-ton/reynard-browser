//
//  ReynardDataTransferOperation.swift
//  Reynard
//

import Foundation

enum ReynardDataTransferOperation: Equatable {
    case export
    case importBackup(bookmarkData: Data)
}
