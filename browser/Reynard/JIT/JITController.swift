//
//  JITController.swift
//  Reynard
//
//  Created by Minh Ton on 11/3/26.
//

import Foundation

final class JITController {
    static let shared = JITController()
    
    private let attachQueue = DispatchQueue(label: "me.minh-ton.jit.jit-attach-queue", qos: .userInitiated)
    private var attachedPIDs: Set<Int32> = []
    
    private init() {}
    
    func start() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleChildProcessNotification(_:)),
            name: NSNotification.Name("GeckoRuntimeChildProcessDidStart"),
            object: nil
        )
    }
    
    private func shouldAttach(to processType: String) -> Bool {
        let normalized = processType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "tab"
    }
    
    func childProcessDidStart(pid: Int32, processType: String) {
        guard pid > 0 else {
            return
        }
        
        let preferences = BrowserPreferences.shared
        print("REYNARD_DEBUG: Child process JIT observer saw pid=\(pid), type=\(processType)")
        guard preferences.isJITEnabled else {
            ReportChildProcessJITEnabled(pid, false)
            return
        }
        
        guard shouldAttach(to: processType) else {
            ReportChildProcessJITEnabled(pid, false)
            return
        }
        
        attachQueue.async {
            if self.attachedPIDs.contains(pid) {
                return
            }
            self.attachedPIDs.insert(pid)
            self.attachToProcess(pid: pid)
        }
    }
    
    private func attachToProcess(pid: Int32) {
        print("REYNARD_DEBUG: Starting JIT attach workflow for pid=\(pid)")
        do {
            try JITEnabler.shared.enableJIT(forPID: pid) { message in print("REYNARD_DEBUG: \(message)") }
            ReportChildProcessJITEnabled(pid, true)
        } catch {
            print("REYNARD_DEBUG: JIT enablement failed for pid=\(pid), error=\(error)")
            ReportChildProcessJITEnabled(pid, false)
        }
    }
    
    @objc private func handleChildProcessNotification(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let pidNumber = userInfo["pid"] as? NSNumber,
            let processType = userInfo["processType"] as? String
        else {
            return
        }
        
        childProcessDidStart(pid: pidNumber.int32Value, processType: processType)
    }
}
