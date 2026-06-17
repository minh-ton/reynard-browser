//
//  AddonEvents.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import Foundation

enum AddonRuntimeEvent: String, CaseIterable {
    case browserActionUpdate = "GeckoView:BrowserAction:Update"
    case browserActionOpenPopup = "GeckoView:BrowserAction:OpenPopup"
    case pageActionUpdate = "GeckoView:PageAction:Update"
    case pageActionOpenPopup = "GeckoView:PageAction:OpenPopup"
    case openOptionsPage = "GeckoView:WebExtension:OpenOptionsPage"
    case newTab = "GeckoView:WebExtension:NewTab"
    case installPrompt = "GeckoView:WebExtension:InstallPrompt"
    case optionalPrompt = "GeckoView:WebExtension:OptionalPrompt"
    case updatePrompt = "GeckoView:WebExtension:UpdatePrompt"
    case installationFailed = "GeckoView:WebExtension:OnInstallationFailed"
    case optionalPermissionsChanged = "GeckoView:WebExtension:OnOptionalPermissionsChanged"
    case ready = "GeckoView:WebExtension:OnReady"
    case disabling = "GeckoView:WebExtension:OnDisabling"
    case disabled = "GeckoView:WebExtension:OnDisabled"
    case enabling = "GeckoView:WebExtension:OnEnabling"
    case enabled = "GeckoView:WebExtension:OnEnabled"
    case uninstalling = "GeckoView:WebExtension:OnUninstalling"
    case uninstalled = "GeckoView:WebExtension:OnUninstalled"
    case installing = "GeckoView:WebExtension:OnInstalling"
    case installed = "GeckoView:WebExtension:OnInstalled"
}
