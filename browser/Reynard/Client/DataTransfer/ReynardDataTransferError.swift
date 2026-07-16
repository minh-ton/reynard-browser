//
//  ReynardDataTransferError.swift
//  Reynard
//

import Foundation

enum ReynardDataTransferError: Error, Equatable {
    case unsupportedVersion
    case unsafePath
    case unsupportedFileType
    case invalidManifest
    case missingFile
    case extraFile
    case sizeMismatch
    case checksumMismatch
    case insufficientSpace
    case stagingFailure
    case applyFailure
    case rollbackFailure
}
