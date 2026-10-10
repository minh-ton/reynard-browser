//
//  RuntimePreferences.swift
//  Reynard
//
//  Created by Minh Ton on 30/8/26.
//

import Darwin
import GeckoView

enum RuntimePreferences {
    static func apply() {
        // On sites with heavy graphics, the GPU process would crash
        // multiple times during user interactions on the iPad Air 2.
        // I originally thought this is due to OOM, but it turns out
        // to be an AGXGLDriver crash caused by by PBO uploads.
        
        // I'm not entirely sure why this happens or if it is related
        // to bug 1773128 on Android (as the iPad Air 2 uses a PowerVR
        // GX6850 GPU which belongs to the same Series6* as in the bug)
        // or not, but disabling PBO uploads seems to fix the issue.
        
        // TODO: The Apple A8 also uses the same Series6* GPU, but I don't
        // have a device to see if the issue also happens there.
        
        // Therefore I'll just disable PBO uploads for A8X for now.
        // batched-texture-uploads is also enabled to prevent texture
        // corruption when PBO uploads are disabled on the device.
        var systemInfo = utsname()
        uname(&systemInfo)
        let hardware = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
        
        if hardware == "iPad5,3" || hardware == "iPad5,4" {
            GeckoRuntime.setDefaultPrefs([
                "gfx.webrender.pbo-uploads": false,
                "gfx.webrender.batched-texture-uploads": true
            ])
        }
        
        // Disable mobile viewport on iPad
        if UIDevice.current.userInterfaceIdiom == .pad {
            GeckoRuntime.setDefaultPrefs([
                "dom.meta-viewport.enabled": false
            ])
        }
        
        // HTTPS-only mode
        HTTPSOnlyModePolicyController.applyHTTPSOnlyMode()
        
        // System proxy
        SystemProxyPreferences.apply()
        SystemProxyPreferences.observeChanges()
        
        // DNS over HTTPS
        DNSOverHTTPSPolicyController.applyDNSOverHTTPS()
        
        // Tracking Protection
        TrackingProtectionPolicyController.applyEnhancedTrackingProtection()
        TrackingProtectionPolicyController.applyGlobalPrivacyControl()
        
        // Remote Debugging
        RemoteDebuggingSettingController.applyRemoteDebugging()
    }
}
