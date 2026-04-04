//
//  OpenInViewController.swift
//  Reynard
//
//  Created by Minh Ton on 3/4/26.
//

import UIKit
import UniformTypeIdentifiers

final class OpenInViewController: UIViewController {
    private var hasStartedOpenFlow = false
    
    override func loadView() {
        let view = UIView()
        view.backgroundColor = .clear
        view.isOpaque = false
        self.view = view
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        clearBackgrounds(startingAt: view)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        guard !hasStartedOpenFlow else {
            return
        }
        
        hasStartedOpenFlow = true
        openSharedLinkInBrowser()
    }
    
    private func openSharedLinkInBrowser() {
        extractSharedURL { [weak self] sharedURL in
            guard let self else {
                return
            }
            
            guard let sharedURL else {
                self.finishWithError(message: "No link was provided.")
                return
            }
            
            guard let browserURL = self.browserOpenURL(for: sharedURL) else {
                self.finishWithError(message: "Unable to open Reynard.")
                return
            }
            
            self.openHostApp(with: browserURL)
        }
    }
    
    private func extractSharedURL(completion: @escaping (URL?) -> Void) {
        let inputItems = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        let providers = inputItems.flatMap { $0.attachments ?? [] }
        
        if let urlProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            urlProvider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                let sharedURL = (item as? URL) ?? (item as? NSURL as URL?)
                DispatchQueue.main.async {
                    completion(sharedURL)
                }
            }
            return
        }
        
        completion(nil)
    }
    
    private func browserOpenURL(for sharedURL: URL) -> URL? {
        guard var components = URLComponents(string: "reynard://open") else {
            return nil
        }
        
        components.queryItems = [
            URLQueryItem(name: "url", value: sharedURL.absoluteString)
        ]
        return components.url
    }
    
    private func openHostApp(with url: URL) {
        let workspaceDefaultSelector = NSSelectorFromString("defaultWorkspace")
        let workspaceOpenSelector = NSSelectorFromString("openSensitiveURL:withOptions:")
        
        if let workspaceClass = NSClassFromString("LSApplicationWorkspace") {
            let workspaceClassObject: AnyObject = workspaceClass
            let workspace = workspaceClassObject.perform(workspaceDefaultSelector)?.takeUnretainedValue()
            
            if let workspace, workspace.responds(to: workspaceOpenSelector) {
                _ = workspace.perform(workspaceOpenSelector, with: url, with: nil as NSDictionary?)
                extensionContext?.completeRequest(returningItems: nil)
                return
            }
        }
        
        finishWithError(message: "Unable to open Reynard.")
    }
    
    private func clearBackgrounds(startingAt view: UIView?) {
        var currentView = view
        
        while let resolvedView = currentView {
            resolvedView.backgroundColor = .clear
            resolvedView.isOpaque = false
            currentView = resolvedView.superview
        }
        
        navigationController?.view.backgroundColor = .clear
        navigationController?.view.isOpaque = false
    }
    
    private func finishWithError(message: String) {
        let error = NSError(
            domain: "me.minh-ton.reynard.open-in",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
        extensionContext?.cancelRequest(withError: error)
    }
}
