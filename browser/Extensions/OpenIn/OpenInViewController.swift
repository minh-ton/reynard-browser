//
//  OpenInViewController.swift
//  Reynard
//
//  Created by Minh Ton on 3/4/26.
//

import UIKit
import UniformTypeIdentifiers
import MobileCoreServices

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
        
        let urlTypeIdentifier = kUTTypeURL as String
        if let urlProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(urlTypeIdentifier) }) {
            urlProvider.loadItem(forTypeIdentifier: urlTypeIdentifier, options: nil) { item, _ in
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
        let defaultSelector = NSSelectorFromString("defaultWorkspace")
        let openSelector = NSSelectorFromString("openSensitiveURL:withOptions:")
        if let cls = NSClassFromString("LSApplicationWorkspace"),
        let workspace = (cls as AnyObject).perform(defaultSelector)?.takeUnretainedValue(),
        workspace.responds(to: openSelector) {
            workspace.perform(openSelector, with: url, with: nil as NSDictionary?)
            extensionContext?.completeRequest(returningItems: nil)
            return
        }

        let selector = NSSelectorFromString("openURL:")
        var responder: UIResponder? = self
        while let r = responder {
            if r is UIApplication {
                r.perform(selector, with: url)
                extensionContext?.completeRequest(returningItems: nil)
                return
            }
            responder = r.next
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
            domain: "com.minh-ton.Reynard.OpenIn",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
        extensionContext?.cancelRequest(withError: error)
    }
}
