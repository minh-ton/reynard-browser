//
//  main.swift
//  Reynard
//
//  Created by Minh Ton on 1/2/26.
//

import Foundation
import GeckoWrapper
import UIKit

let defaultArgs = CommandLine.arguments
let debugArgs = [
    // Debug logging
    "-pref", "geckoview.logging=Debug",
]
let allArgs = defaultArgs + debugArgs

let argsCount = Int32(allArgs.count)
let argv = UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>.allocate(capacity: Int(argsCount + 1))
for (index, arg) in allArgs.enumerated() {
    argv[index] = strdup(arg)
}

argv[Int(argsCount)] = nil
defer {
    for i in 0..<Int(argsCount) {
        free(argv[i])
    }
    argv.deallocate()
}

GeckoRuntime.main(argc: argsCount, argv: argv)
