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
    private var jitDisabledTemporarily = false
    private let preflightTimeoutSeconds: Int = 5
    private let failurePresentationRetryLimit = 12
    
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
        
        guard BrowserPreferences.shared.isJITEnabled, !jitDisabledTemporarily else {
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
            self.schedulePreflightWatchdog(for: pid)
            self.attachToProcess(pid: pid)
        }
    }
    
    private func attachToProcess(pid: Int32) {
        do {
            try JITEnabler.shared.enableJIT(forPID: pid) { _ in }
            cancelPreflightWatchdog(for: pid)
            ReportChildProcessJITEnabled(pid, true)
        } catch {
            let nsError = error as NSError
            cancelPreflightWatchdog(for: pid)
            ReportChildProcessJITEnabled(pid, false)
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
            
            ReportChildProcessJITEnabled(pid, false)
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
    
    private func handleJITFailure(error: NSError) {
        DispatchQueue.main.async {
            guard !self.hasHandledFailure else {
                return
            }
            self.hasHandledFailure = true
            self.presentFailureScreen(
                error: error,
                showsErrorDetails: error.code != Int(ETIMEDOUT)
            )
        }
    }
    
    private func presentFailureScreen(error: NSError, showsErrorDetails: Bool, retryCount: Int = 0) {
        guard retryCount <= failurePresentationRetryLimit else {
            return
        }
        
        guard let presenter = Self.topViewControllerForPresentation() else {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150)) {
                self.presentFailureScreen(error: error, showsErrorDetails: showsErrorDetails, retryCount: retryCount + 1)
            }
            return
        }
        
        let description = error.localizedDescription.isEmpty ? "Unknown error." : error.localizedDescription
        let viewController = JITFailureViewController(
            errorCode: error.code,
            errorDescription: description,
            showsErrorDetails: showsErrorDetails,
            onUseJITLessMode: { [weak self] in
                self?.activateJITLessMode()
            }
        )
        viewController.modalPresentationStyle = .pageSheet
        viewController.modalTransitionStyle = .coverVertical
        presenter.present(viewController, animated: true)
    }
    
    private func activateJITLessMode() {
        jitDisabledTemporarily = true
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NSNotification.Name(rawValue: "me.minh-ton.reynard.jitless-mode-activated"), object: nil)
        }
    }
    
    private static func topViewControllerForPresentation() -> UIViewController? {
        let foregroundScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
        
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
