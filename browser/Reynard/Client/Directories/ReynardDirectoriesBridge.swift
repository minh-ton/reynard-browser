//
//  ReynardDirectoriesBridge.swift
//  Reynard
//

import Foundation

@objc(ReynardDirectoriesBridge)
final class ReynardDirectoriesBridge: NSObject {
    @objc static var ddiPath: String {
        ReynardDirectories.shared.ddi.path
    }

    @objc static var pairingFilePath: String {
        ReynardDirectories.shared.pairingFile.path
    }

    @objc static var jitTemporaryPath: String {
        ReynardDirectories.shared.jitTemporary.path
    }
}
