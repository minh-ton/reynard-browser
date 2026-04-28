//
//  JITController.swift
//  Reynard
//
//  Created by Minh Ton on 11/3/26.
//

import Foundation
import Darwin
import UIKit

final class JITController {
    static let shared = JITController()
    
    private let attachQueue = DispatchQueue(label: "me.minh-ton.jit.jit-attach-queue", qos: .userInitiated)
    private let watchdogQueue = DispatchQueue(label: "me.minh-ton.jit.jit-preflight-watchdog", qos: .userInitiated)
    private var attachedPIDs: Set<Int32> = []
    private var preflightWatchdogs: [Int32: DispatchWorkItem] = [:]
    private var hasHandledFailure = false
    private(set) var isJITLessModeActive = false
    private var pendingFailureAction: (() -> Void)?
    private let preflightTimeoutSeconds: Int = 5
    private let failurePresentationRetryLimit = 12
    
    private init() {}
    
    // For TrollStore or jailbroken devices
    private func usePtraceJIT() -> Bool {
        getEntitlementValue("com.apple.private.security.no-sandbox")
    }
    
    func start() {
        guard usePtraceJIT() || !isDDIMissing() else {
            hasHandledFailure = true
            presentMissingDDIFailureScreen()
            return
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleChildProcessNotification(_:)),
            name: NSNotification.Name("GeckoRuntimeChildProcessDidStart"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleJITDisconnectNotification(_:)),
            name: Notification.Name("me-minh-ton.jit.endpoint-monitor-failed"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleApplicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    private func isDDIMissing() -> Bool {
        BrowserPreferences.shared.isJITEnabled && !DDIManager.shared.hasRequiredDDIFiles()
    }
    
    private func shouldAttach(to processType: String) -> Bool {
        let normalized = processType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "tab"
    }
    
    private func filePath(atPath path: String, withLength length: Int) -> String? {
        guard let file = try? FileManager.default.contentsOfDirectory(atPath: path).first(where: { $0.count == length }) else {
            return nil
        }
        return "\(path)/\(file)"
    }
    
    // Also from StikDebug
    private func hasTXM26() -> Bool {
        guard #available(iOS 26, *) else {
            return false
        }
        
        if let boot = filePath(atPath: "/System/Volumes/Preboot", withLength: 36),
           let file = filePath(atPath: "\(boot)/boot", withLength: 96) {
            return access("\(file)/usr/standalone/firmware/FUD/Ap,TrustedExecutionMonitor.img4", F_OK) == 0
        }
        
        return (filePath(atPath: "/private/preboot", withLength: 96).map {
            access("\($0)/usr/standalone/firmware/FUD/Ap,TrustedExecutionMonitor.img4", F_OK) == 0
        }) ?? false
    }
    
    func childProcessDidStart(pid: Int32, processType: String) {
        guard pid > 0 else {
            return
        }
        
        guard !isJITLessModeActive, !hasHandledFailure else {
            ReportJITStatusForChild(pid, false, hasTXM26())
            return
        }
        
        guard usePtraceJIT() || BrowserPreferences.shared.isJITEnabled else {
            ReportJITStatusForChild(pid, false, hasTXM26())
            return
        }
        
        guard shouldAttach(to: processType) else {
            ReportJITStatusForChild(pid, false, hasTXM26())
            return
        }
        
        attachQueue.async {
            if self.attachedPIDs.contains(pid) {
                return
            }
            self.attachedPIDs.insert(pid)
            self.schedulePreflightWatchdog(for: pid)
            self.attachToProcess(pid: pid)
        }
    }
    
    private func attachToProcess(pid: Int32) {
        do {
            try JITEnabler.shared.enableJIT(forPID: pid, hasTXM26: hasTXM26())
            cancelPreflightWatchdog(for: pid)
            ReportJITStatusForChild(pid, true, hasTXM26())
        } catch {
            let nsError = error as NSError
            cancelPreflightWatchdog(for: pid)
            ReportJITStatusForChild(pid, false, hasTXM26())
            handleJITFailure(error: nsError)
        }
    }
    
    private func schedulePreflightWatchdog(for pid: Int32) {
        var watchdog: DispatchWorkItem?
        watchdog = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }
            
            guard let watchdog, !watchdog.isCancelled else {
                return
            }
            
            ReportJITStatusForChild(pid, false, hasTXM26())
            self.handleJITFailure(error: NSError(domain: "Reynard.JIT", code: Int(ETIMEDOUT), userInfo: nil))
        }
        
        guard let watchdog else {
            return
        }
        
        preflightWatchdogs[pid] = watchdog
        watchdogQueue.asyncAfter(deadline: .now() + .seconds(preflightTimeoutSeconds), execute: watchdog)
    }
    
    private func cancelPreflightWatchdog(for pid: Int32) {
        preflightWatchdogs[pid]?.cancel()
        preflightWatchdogs.removeValue(forKey: pid)
    }
    
    private func cancelAllPreflightWatchdogs() {
        for pid in preflightWatchdogs.keys {
            cancelPreflightWatchdog(for: pid)
        }
    }
    
    private func handleJITFailure(error: NSError) {
        DispatchQueue.main.async {
            guard !self.hasHandledFailure else {
                return
            }
            self.hasHandledFailure = true
            self.presentEnablementFailureScreen(
                error: error,
                showsErrorDetails: error.code != Int(ETIMEDOUT)
            )
        }
    }
    
    private func presentEnablementFailureScreen(error: NSError, showsErrorDetails: Bool, retryCount: Int = 0) {
        guard retryCount <= failurePresentationRetryLimit else {
            return
        }
        
        guard Self.canPresentFailureUI() else {
            pendingFailureAction = { [weak self] in
                self?.presentEnablementFailureScreen(error: error, showsErrorDetails: showsErrorDetails)
            }
            return
        }
        
        guard let presenter = Self.topViewControllerForPresentation() else {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150)) {
                self.presentEnablementFailureScreen(error: error, showsErrorDetails: showsErrorDetails, retryCount: retryCount + 1)
            }
            return
        }
        
        let description = error.localizedDescription.isEmpty ? "Unknown error." : error.localizedDescription
        let messageText: String
        if usePtraceJIT() {
            messageText = "It's extremely rare that you encounter this issue! Make sure that your TrollStore installation or jailbroken environment is properly configured.\n\nYou may use the browser without JIT temporarily until the next launch by activating JIT-Less Mode."
        } else {
            messageText = "Please check that your pairing file is valid, your loopback VPN is on, and you're connected to a stable Wi-Fi network.\n\nYou may use the browser without JIT temporarily until the next launch by activating JIT-Less Mode."
        }
        
        let viewController = JITFailureViewController(
            errorCode: error.code,
            errorDescription: description,
            showsErrorDetails: showsErrorDetails,
            titleText: "Failed to enable JIT",
            messageText: messageText,
            actionButtonTitle: "Activate JIT-Less Mode",
            onPrimaryAction: { [weak self] in
                self?.activateJITLessMode()
            }
        )
        viewController.modalPresentationStyle = .pageSheet
        viewController.modalTransitionStyle = .coverVertical
        presenter.present(viewController, animated: true)
    }
    
    private func presentMissingDDIFailureScreen(retryCount: Int = 0) {
        guard retryCount <= failurePresentationRetryLimit else {
            return
        }
        
        guard Self.canPresentFailureUI() else {
            pendingFailureAction = { [weak self] in
                self?.presentMissingDDIFailureScreen()
            }
            return
        }
        
        guard let presenter = Self.topViewControllerForPresentation() else {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150)) {
                self.presentMissingDDIFailureScreen(retryCount: retryCount + 1)
            }
            return
        }
        
        let viewController = JITFailureViewController(
            errorCode: Int(ENOENT),
            errorDescription: "Required DDI files are missing.",
            showsErrorDetails: false,
            titleText: "Failed to enable JIT",
            messageText: "The required Developer Disk Image files for enabling JIT were not found.\n\nJIT has been disabled. Quit the app using the button below, then re-enable JIT from the browser settings.",
            actionButtonTitle: "Quit Reynard",
            onPrimaryAction: {
                self.disableJITAndQuit()
            }
        )
        viewController.modalPresentationStyle = .pageSheet
        viewController.modalTransitionStyle = .coverVertical
        presenter.present(viewController, animated: true)
    }
    
    private func disableJITAndQuit() {
        BrowserPreferences.shared.isJITEnabled = false
        quitApp()
    }
    
    private func quitApp() {
        UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
            exit(EXIT_SUCCESS)
        }
    }
    
    private func activateJITLessMode() {
        guard !isJITLessModeActive else {
            return
        }
        
        isJITLessModeActive = true
        attachQueue.async {
            self.cancelAllPreflightWatchdogs()
            self.attachedPIDs.removeAll()
            JITEnabler.shared.detachAllJITSessions()
        }
        
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NSNotification.Name(rawValue: "me.minh-ton.reynard.jitless-mode-activated"), object: nil)
        }
    }
    
    private static func topViewControllerForPresentation() -> UIViewController? {
        let foregroundScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        
        guard let scene = foregroundScenes.first else {
            return nil
        }
        
        let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController
        ?? scene.windows.first(where: { !$0.isHidden })?.rootViewController
        
        guard let root else {
            return nil
        }
        
        return topPresentedViewController(from: root)
    }
    
    private static func topPresentedViewController(from root: UIViewController) -> UIViewController {
        var current = root
        while let presented = current.presentedViewController {
            current = presented
        }
        return current
    }
    
    private static func canPresentFailureUI() -> Bool {
        guard UIApplication.shared.applicationState == .active else {
            return false
        }
        
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .contains { $0.activationState == .foregroundActive }
    }
    
    @objc private func handleApplicationDidBecomeActive() {
        let action = pendingFailureAction
        pendingFailureAction = nil
        action?()
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
    
    @objc private func handleJITDisconnectNotification(_ notification: Notification) {
        guard BrowserPreferences.shared.isJITEnabled, !isJITLessModeActive else {
            return
        }
        
        if let pid = (notification.userInfo?["pid"] as? NSNumber)?.int32Value, pid > 0 {
            ReportJITStatusForChild(pid, false, hasTXM26())
        }
        
        DispatchQueue.main.async {
            guard !self.hasHandledFailure else {
                return
            }
            
            self.hasHandledFailure = true
            self.presentEnablementFailureScreen(error: NSError(domain: "Reynard.JIT", code: Int(ETIMEDOUT), userInfo: nil), showsErrorDetails: false)
        }
    }
}
