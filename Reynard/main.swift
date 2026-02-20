//
//  main.swift
//  Reynard
//
//  Created by Minh Ton on 1/2/26.
//

import Foundation
import GeckoWrapper
import UIKit

// Set logging
setenv("MOZ_LOG", "GeckoView:5,Widget:5,WidgetPopup:5,Layers:5,Layout:5,DisplayList:5,RenderCompositor:5,DocShell:5,DocLoader:5,Document:5,ScriptLoader:5", 1)
setenv("RUST_LOG", "debug", 1)

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
