//
//  AddonUpdateController.swift
//  Reynard
//
//  Created by Minh Ton on 24/5/26.
//

import GeckoView
import Foundation

struct AddonUpdateBatchResult {
    let updatedCount: Int
    let noUpdateCount: Int
    let pendingApprovalCount: Int
    let failedCount: Int
}

final class AddonUpdateController {
    private var shouldRunAutomaticCheck: Bool
    private var isRunningBatch = false
    private var shouldPresentUpdatePrompts = false
    private var isSettingsVisible = false
    
    init() {
        if let lastGlobalCheckAt = Prefs.AddonSettings.lastGlobalCheckAt {
            shouldRunAutomaticCheck = Date().timeIntervalSince(lastGlobalCheckAt) >= 12 * 60 * 60
        } else {
            shouldRunAutomaticCheck = true
        }
    }
    
    var hasPendingApprovals: Bool {
        !Prefs.AddonSettings.pendingApprovalAddonIDs.isEmpty
    }
    
    var isUpdating: Bool {
        isRunningBatch
    }
    
    func start() {
        prunePendingApprovalAddonIDs()
        guard shouldRunAutomaticCheck else {
            return
        }
        shouldRunAutomaticCheck = false
        Task {
            await runAutomaticCheck()
        }
    }
    
    func setSettingsVisible(_ visible: Bool) {
        isSettingsVisible = visible
        if visible {
            prunePendingApprovalAddonIDs()
        }
    }
    
    @MainActor
    func responseForUpdatePrompt(
        _ prompt: AddonPermissionPrompt,
        presentPrompt: @escaping (AddonPermissionPrompt) async -> AddonPermissionPromptResponse
    ) async -> AddonPermissionPromptResponse {
        guard shouldPresentUpdatePrompts && isSettingsVisible else {
            addPendingApprovalAddonID(prompt.addon.id)
            return .deny
        }
        
        let response = await presentPrompt(prompt)
        if response.allow {
            removePendingApprovalAddonID(prompt.addon.id)
        } else {
            addPendingApprovalAddonID(prompt.addon.id)
        }
        return response
    }
    
    func updateAllAddons(
        status: @escaping @MainActor (String, String?) -> Void
    ) async -> AddonUpdateBatchResult {
        await runBatch(
            addons: updatableAddons(),
            status: status
        )
    }
    
    func completePendingUpdates(
        status: @escaping @MainActor (String, String?) -> Void
    ) async -> AddonUpdateBatchResult {
        let pendingIDs = Set(Prefs.AddonSettings.pendingApprovalAddonIDs)
        let addons = updatableAddons().filter { pendingIDs.contains($0.id) }
        return await runBatch(addons: addons, status: status)
    }
    
    private func runAutomaticCheck() async {
        guard !isRunningBatch else {
            return
        }
        
        isRunningBatch = true
        defer {
            isRunningBatch = false
        }
        
        for addon in updatableAddons() {
            do {
                let updatedAddon = try await AddonRuntime.shared.update(addon)
                if updatedAddon == nil {
                    removePendingApprovalAddonID(addon.id)
                }
            } catch {
                if AddonErrors.updateRequiresPermissions(error) {
                    addPendingApprovalAddonID(addon.id)
                }
            }
        }
        
        Prefs.AddonSettings.lastGlobalCheckAt = Date()
    }
    
    private func runBatch(
        addons: [Addon],
        status: @escaping @MainActor (String, String?) -> Void
    ) async -> AddonUpdateBatchResult {
        guard !isRunningBatch else {
            return AddonUpdateBatchResult(
                updatedCount: 0,
                noUpdateCount: 0,
                pendingApprovalCount: Prefs.AddonSettings.pendingApprovalAddonIDs.count,
                failedCount: 0
            )
        }
        
        isRunningBatch = true
        shouldPresentUpdatePrompts = true
        
        var updatedCount = 0
        var noUpdateCount = 0
        var failedCount = 0
        
        defer {
            shouldPresentUpdatePrompts = false
            isRunningBatch = false
            Prefs.AddonSettings.lastGlobalCheckAt = Date()
        }
        
        for addon in addons {
            await MainActor.run {
                status(addon.id, L("Updating..."))
            }
            
            do {
                let updatedAddon = try await AddonRuntime.shared.update(addon)
                if updatedAddon == nil {
                    noUpdateCount += 1
                    removePendingApprovalAddonID(addon.id)
                    await MainActor.run {
                        status(addon.id, L("No update available"))
                    }
                } else {
                    updatedCount += 1
                    removePendingApprovalAddonID(addon.id)
                    await MainActor.run {
                        status(addon.id, L("Successfully updated"))
                    }
                }
            } catch {
                if AddonErrors.updateRequiresPermissions(error) {
                    addPendingApprovalAddonID(addon.id)
                    await MainActor.run {
                        status(addon.id, L("Needs permission to update"))
                    }
                    continue
                }
                
                failedCount += 1
                let presentation = AddonErrors.updateErrPresentation(
                    for: error,
                    addonName: addon.metaData.name ?? addon.id
                )
                await MainActor.run {
                    status(addon.id, presentation.statusText)
                }
            }
        }
        
        return AddonUpdateBatchResult(
            updatedCount: updatedCount,
            noUpdateCount: noUpdateCount,
            pendingApprovalCount: Prefs.AddonSettings.pendingApprovalAddonIDs.count,
            failedCount: failedCount
        )
    }
    
    private func updatableAddons() -> [Addon] {
        prunePendingApprovalAddonIDs()
        return AddonRuntime.shared.installedAddons.filter {
            !$0.isBuiltIn && !$0.metaData.isUnsupported
        }
    }
    
    private func prunePendingApprovalAddonIDs() {
        let validAddonIDs = Set(AddonRuntime.shared.installedAddons.filter {
            !$0.isBuiltIn && !$0.metaData.isUnsupported
        }.map(\ .id))
        let filteredIDs = Prefs.AddonSettings.pendingApprovalAddonIDs.filter { validAddonIDs.contains($0) }
        if filteredIDs != Prefs.AddonSettings.pendingApprovalAddonIDs {
            Prefs.AddonSettings.pendingApprovalAddonIDs = filteredIDs
        }
    }
    
    private func addPendingApprovalAddonID(_ addonID: String) {
        var pendingApprovalAddonIDs = Prefs.AddonSettings.pendingApprovalAddonIDs
        if !pendingApprovalAddonIDs.contains(addonID) {
            pendingApprovalAddonIDs.append(addonID)
            Prefs.AddonSettings.pendingApprovalAddonIDs = pendingApprovalAddonIDs
        }
    }
    
    private func removePendingApprovalAddonID(_ addonID: String) {
        let filteredIDs = Prefs.AddonSettings.pendingApprovalAddonIDs.filter { $0 != addonID }
        if filteredIDs != Prefs.AddonSettings.pendingApprovalAddonIDs {
            Prefs.AddonSettings.pendingApprovalAddonIDs = filteredIDs
        }
    }
}
