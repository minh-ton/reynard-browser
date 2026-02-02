//
//  main.swift
//  Reynard
//
//  Created by Minh Ton on 1/2/26.
//

import Foundation
import GeckoWrapper
import UIKit

// We need to start Gecko and XPCOM before UIApplicationMain,
// so call GeckoRuntime.main instead of having @main on AppDelegate.

// Disabling JIT because I've commented out JIT stuff in the Gecko source.
let defaultArgs = CommandLine.arguments
let quickArgs = [
    "-pref", "javascript.options.baselinejit=false",
    "-pref", "javascript.options.ion=false",
    "-pref", "javascript.options.asmjs=false",
    "-pref", "javascript.options.wasm=false",
    "-pref", "javascript.options.native_regexp=false",
    "-pref", "javascript.options.jit_trustedprincipals=true",
    
    // Miscellaneous configs
    "-pref", "toolkit.defaultChromeURI=about:blank",
    "-pref", "security.sandbox.content.level=0",
    "-pref", "gfx.webrender.software=false",
    
    // I got some security restrictions here while testing some
    // URLs, and this is still not resolved, so I'll just put here anyways
    "-pref", "security.allow_unsafe_parent_loads=true",
    "-pref", "security.fileuri.strict_origin_policy=false",
    "-pref", "security.mixed_content.block_active_content=false",
    "-pref", "security.data_uri.block_toplevel_data_uri_navigations=false"
]

// Set logging
setenv("MOZ_LOG", "GeckoView:5,Widget:5,WidgetPopup:5,Layers:5,Layout:5,DisplayList:5,RenderCompositor:5", 1)
setenv("RUST_LOG", "debug", 1)
let allArgs = defaultArgs + quickArgs

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
