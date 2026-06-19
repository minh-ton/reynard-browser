//
//  AddonUpdateCoordinator.swift
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

final class AddonUpdateCoordinator {
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
        return !Prefs.AddonSettings.pendingApprovalAddonIDs.isEmpty
    }
    
    func start() {
        prunePendingApprovals()
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
            prunePendingApprovals()
        }
    }
    
    @MainActor
    func responseForUpdatePrompt(
        _ prompt: AddonPermissionPrompt,
        presentPrompt: @escaping (AddonPermissionPrompt) async -> AddonPermissionPromptResponse
    ) async -> AddonPermissionPromptResponse {
        guard shouldPresentUpdatePrompts && isSettingsVisible else {
            markNeedsApproval(prompt.addon.id)
            return .deny
        }
        
        let response = await presentPrompt(prompt)
        if response.allow {
            clearPendingApproval(prompt.addon.id)
        } else {
            markNeedsApproval(prompt.addon.id)
        }
        return response
    }
    
    func updateAllAddons(
        status: @escaping @MainActor (String, String?) -> Void
    ) async -> AddonUpdateBatchResult {
        await runUpdateBatch(
            addons: updateCandidates(),
            status: status
        )
    }
    
    func completePendingUpdates(
        status: @escaping @MainActor (String, String?) -> Void
    ) async -> AddonUpdateBatchResult {
        let pendingIDs = Set(Prefs.AddonSettings.pendingApprovalAddonIDs)
        let addons = updateCandidates().filter { pendingIDs.contains($0.id) }
        return await runUpdateBatch(addons: addons, status: status)
    }
    
    private func runAutomaticCheck() async {
        guard !isRunningBatch else {
            return
        }
        
        isRunningBatch = true
        defer {
            isRunningBatch = false
        }
        
        for addon in updateCandidates() {
            do {
                let updatedAddon = try await AddonRuntime.shared.update(addon)
                if updatedAddon == nil {
                    clearPendingApproval(addon.id)
                }
            } catch {
                if AddonErrorPresenter.updateRequiresPermissions(error) {
                    markNeedsApproval(addon.id)
                }
            }
        }
        
        Prefs.AddonSettings.lastGlobalCheckAt = Date()
    }
    
    private func runUpdateBatch(
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
                status(addon.id, "Updating...")
            }
            
            do {
                let updatedAddon = try await AddonRuntime.shared.update(addon)
                if updatedAddon == nil {
                    noUpdateCount += 1
                    clearPendingApproval(addon.id)
                    await MainActor.run {
                        status(addon.id, "No update available")
                    }
                } else {
                    updatedCount += 1
                    clearPendingApproval(addon.id)
                    await MainActor.run {
                        status(addon.id, "Successfully updated")
                    }
                }
            } catch {
                if AddonErrorPresenter.updateRequiresPermissions(error) {
                    markNeedsApproval(addon.id)
                    await MainActor.run {
                        status(addon.id, "Needs permission to update")
                    }
                    continue
                }
                
                failedCount += 1
                let presentation = AddonErrorPresenter.updateErrorPresentation(
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
    
    private func updateCandidates() -> [Addon] {
        prunePendingApprovals()
        return AddonRuntime.shared.installedAddons.filter {
            !$0.isBuiltIn && !$0.metaData.isUnsupported
        }
    }
    
    private func prunePendingApprovals() {
        let validAddonIDs = Set(AddonRuntime.shared.installedAddons.filter {
            !$0.isBuiltIn && !$0.metaData.isUnsupported
        }.map(\ .id))
        let filteredIDs = Prefs.AddonSettings.pendingApprovalAddonIDs.filter { validAddonIDs.contains($0) }
        if filteredIDs != Prefs.AddonSettings.pendingApprovalAddonIDs {
            Prefs.AddonSettings.pendingApprovalAddonIDs = filteredIDs
        }
    }
    
    private func markNeedsApproval(_ addonID: String) {
        var pendingApprovalAddonIDs = Prefs.AddonSettings.pendingApprovalAddonIDs
        if !pendingApprovalAddonIDs.contains(addonID) {
            pendingApprovalAddonIDs.append(addonID)
            Prefs.AddonSettings.pendingApprovalAddonIDs = pendingApprovalAddonIDs
        }
    }
    
    private func clearPendingApproval(_ addonID: String) {
        let filteredIDs = Prefs.AddonSettings.pendingApprovalAddonIDs.filter { $0 != addonID }
        if filteredIDs != Prefs.AddonSettings.pendingApprovalAddonIDs {
            Prefs.AddonSettings.pendingApprovalAddonIDs = filteredIDs
        }
    }
}
