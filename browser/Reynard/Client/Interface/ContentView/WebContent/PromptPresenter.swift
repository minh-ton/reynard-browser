//
//  PromptPresenter.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import GeckoView
import UIKit

@MainActor
final class PromptPresenter: PromptPresenting {
    private var beforeUnloadAlerts: [String: PromptAlertController] = [:]
    private var selectPickers: [String: SelectPicker] = [:]
    private var colorPickers: [String: ColorPicker] = [:]
    private var dateTimePickers: [String: DateTimePicker] = [:]
    private var filePickers: [String: FilePicker] = [:]
    
    // MARK: - Lifecycle
    
    init() {}
    
    func present(_ request: PromptRequest, for session: GeckoSession) async -> PromptResponse? {
        switch request {
        case .alert(let request):
            await presentAlert(request: request)
            return nil
            
        case .button(let request):
            return await presentButton(request: request)
            
        case .text(let request):
            return await presentText(request: request)
            
        case .auth(let request):
            return await presentAuth(request: request)
            
        case .beforeUnload(let request):
            return await presentBeforeUnload(request: request)
            
        case .folderUpload(let request):
            return await presentFolderUpload(request: request)
            
        case .color(let request):
            return await presentColorPicker(session: session, request: request)
            
        case .dateTime(let request):
            return await presentDateTimePicker(session: session, request: request)
            
        case .file(let request):
            return await presentFilePicker(session: session, request: request)
            
        case .choice(let request):
            return await presentSelectPicker(session: session, request: request)
            
        case .share(let request):
            return await presentShare(session: session, request: request)
        }
    }
    
    func update(_ request: PromptRequest) {
        guard case .choice(let request) = request,
              let picker = selectPickers[request.id] else {
            return
        }
        
        picker.updateChoices(request.choices, mode: request.mode)
    }
    
    func dismiss(promptID: String) {
        if dateTimePickers[promptID] != nil {
            // Gecko fires dismiss when native date UI steals focus; the picker owns completion.
            return
        }
        beforeUnloadAlerts.removeValue(forKey: promptID)?.dismiss(animated: true)
        selectPickers.removeValue(forKey: promptID)?.cancelAndDismiss()
        colorPickers.removeValue(forKey: promptID)?.cancelAndDismiss()
        dateTimePickers.removeValue(forKey: promptID)?.cancelAndDismiss()
        filePickers.removeValue(forKey: promptID)?.cancelAndDismiss()
    }
    
    // MARK: - Basic Prompts
    
    private func presentAlert(request: AlertPromptRequest) async {
        guard let presenter = UIApplication.shared.topViewController() else {
            return
        }
        
        await withCheckedContinuation { continuation in
            let alert = PromptAlertController(
                title: request.title.isEmpty ? nil : request.title,
                message: request.message.isEmpty ? nil : request.message,
                preferredStyle: .alert
            )
            alert.onDismissed = {
                continuation.resume()
            }
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
            presenter.present(alert, animated: true)
        }
    }
    
    private func presentButton(request: ButtonPromptRequest) async -> PromptResponse? {
        guard let presenter = UIApplication.shared.topViewController() else {
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            var response: PromptResponse?
            let alert = PromptAlertController(
                title: request.title.isEmpty ? nil : request.title,
                message: request.message.isEmpty ? nil : request.message,
                preferredStyle: .alert
            )
            alert.onDismissed = {
                continuation.resume(returning: response)
            }
            
            for index in 0..<3 {
                let title = buttonTitle(at: index, request: request)
                guard !title.isEmpty else { continue }
                
                let isCancel = index == 2 &&
                request.buttonTitles.indices.contains(index) &&
                request.buttonTitles[index] == "cancel"
                alert.addAction(UIAlertAction(
                    title: title,
                    style: isCancel ? .cancel : .default
                ) { _ in
                    response = .button(index)
                })
            }
            
            if alert.actions.isEmpty {
                alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default) { _ in
                    response = .button(0)
                })
            }
            
            presenter.present(alert, animated: true)
        }
    }
    
    private func presentText(request: TextPromptRequest) async -> PromptResponse? {
        guard let presenter = UIApplication.shared.topViewController() else {
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            var response: PromptResponse?
            let alert = PromptAlertController(
                title: request.title.isEmpty ? nil : request.title,
                message: request.message.isEmpty ? nil : request.message,
                preferredStyle: .alert
            )
            alert.onDismissed = {
                continuation.resume(returning: response)
            }
            alert.addTextField { textField in
                textField.text = request.value
            }
            alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default) { _ in
                response = .text(alert.textFields?.first?.text ?? "")
            })
            presenter.present(alert, animated: true)
        }
    }
    
    private func presentAuth(request: AuthPromptRequest) async -> PromptResponse? {
        guard let presenter = UIApplication.shared.topViewController() else {
            return nil
        }
        
        let host = URL(string: request.uri)?.host
        let title = host.map {
            String(format: NSLocalizedString("Sign in to %@", comment: "Authentication host"), $0)
        } ?? request.title
        let message = request.level == 2
        ? NSLocalizedString("Your login information will be sent securely.", comment: "")
        : NSLocalizedString("Your login information will not be sent securely.", comment: "")
        let passwordOnly = request.mode == "password"
        
        return await withCheckedContinuation { continuation in
            var response: PromptResponse?
            let alert = PromptAlertController(
                title: title.isEmpty ? NSLocalizedString("Sign In", comment: "") : title,
                message: message,
                preferredStyle: .alert
            )
            alert.onDismissed = {
                continuation.resume(returning: response)
            }
            
            if !passwordOnly {
                alert.addTextField { textField in
                    textField.placeholder = NSLocalizedString("User Name", comment: "")
                    textField.text = request.username
                    textField.textContentType = .username
                    textField.autocapitalizationType = .none
                    textField.autocorrectionType = .no
                }
            }
            
            alert.addTextField { textField in
                textField.placeholder = NSLocalizedString("Password", comment: "")
                textField.text = request.password
                textField.textContentType = .password
                textField.isSecureTextEntry = true
            }
            
            alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
            alert.addAction(UIAlertAction(title: NSLocalizedString("Sign In", comment: ""), style: .default) { _ in
                let username = passwordOnly ? request.username : alert.textFields?.first?.text ?? ""
                let password = alert.textFields?.last?.text ?? ""
                response = .auth(username: username, password: password)
            })
            presenter.present(alert, animated: true)
        }
    }
    
    private func presentBeforeUnload(request: BeforeUnloadPromptRequest) async -> PromptResponse? {
        guard let presenter = UIApplication.shared.topViewController() else {
            return nil
        }
        
        defer { beforeUnloadAlerts.removeValue(forKey: request.id) }
        
        return await withCheckedContinuation { continuation in
            var allowed = false
            let alert = PromptAlertController(
                title: NSLocalizedString("Leave Page?", comment: ""),
                message: NSLocalizedString("Changes you made may not be saved.", comment: ""),
                preferredStyle: .alert
            )
            alert.onDismissed = {
                continuation.resume(returning: .beforeUnload(allowed: allowed))
            }
            alert.addAction(UIAlertAction(title: NSLocalizedString("Stay", comment: ""), style: .cancel))
            alert.addAction(UIAlertAction(title: NSLocalizedString("Leave", comment: ""), style: .destructive) { _ in
                allowed = true
            })
            beforeUnloadAlerts[request.id] = alert
            presenter.present(alert, animated: true)
        }
    }
    
    private func presentFolderUpload(request: FolderUploadPromptRequest) async -> PromptResponse? {
        guard let presenter = UIApplication.shared.topViewController() else {
            return nil
        }
        
        let message = request.directoryName.isEmpty
        ? NSLocalizedString("Are you sure you want to upload all files? Only do this if you trust the site.", comment: "")
        : NSLocalizedString("Are you sure you want to upload all files from \"\(request.directoryName)\"? Only do this if you trust the site.", comment: "")
        
        return await withCheckedContinuation { continuation in
            var response: PromptResponse?
            let alert = PromptAlertController(
                title: NSLocalizedString("Confirm Upload", comment: ""),
                message: message,
                preferredStyle: .alert
            )
            alert.onDismissed = {
                continuation.resume(returning: response)
            }
            alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel) { _ in
                response = .folderUpload(allowed: false)
            })
            alert.addAction(UIAlertAction(title: NSLocalizedString("Upload", comment: ""), style: .default) { _ in
                response = .folderUpload(allowed: true)
            })
            presenter.present(alert, animated: true)
        }
    }
    
    // MARK: - Picker Prompts
    
    private func presentColorPicker(
        session: GeckoSession,
        request: ColorPromptRequest
    ) async -> PromptResponse? {
        guard let anchor = promptAnchor(for: request.anchor, session: session) else {
            return nil
        }
        
        let picker = ColorPicker(
            anchorRect: anchor.rect,
            geckoView: anchor.view
        )
        colorPickers[request.id] = picker
        defer { colorPickers.removeValue(forKey: request.id) }
        
        let result = await picker.present(initialColor: UIColor(hexString: request.value) ?? .black)
        
        return result.map(PromptResponse.color)
    }
    
    private func presentDateTimePicker(
        session: GeckoSession,
        request: DateTimePromptRequest
    ) async -> PromptResponse? {
        guard let anchor = promptAnchor(for: request.anchor, session: session) else {
            return nil
        }
        
        let picker = DateTimePicker(
            inputMode: request.mode,
            anchorRect: anchor.rect,
            geckoView: anchor.view
        )
        dateTimePickers[request.id] = picker
        defer { dateTimePickers.removeValue(forKey: request.id) }
        
        let result = await picker.present(
            value: request.value,
            min: request.min,
            max: request.max,
            step: request.step
        )
        
        return result.map(PromptResponse.dateTime)
    }
    
    private func presentFilePicker(
        session: GeckoSession,
        request: FilePickerPromptRequest
    ) async -> PromptResponse? {
        guard let anchor = promptAnchor(for: request.anchor, session: session) else {
            return nil
        }
        
        let picker = FilePicker(
            promptId: request.id,
            mode: request.mode,
            mimeTypes: request.mimeTypes,
            capture: request.capture,
            anchorRect: anchor.rect,
            geckoView: anchor.view
        )
        filePickers[request.id] = picker
        defer { filePickers.removeValue(forKey: request.id) }
        
        let result = await picker.present()
        
        return result.map(PromptResponse.files)
    }
    
    private func presentSelectPicker(
        session: GeckoSession,
        request: SelectPromptRequest
    ) async -> PromptResponse? {
        guard let anchor = promptAnchor(for: request.anchor, session: session) else {
            return nil
        }
        
        let picker = SelectPicker(
            mode: request.mode,
            choices: request.choices,
            sourceRect: anchor.rect,
            geckoView: anchor.view
        )
        selectPickers[request.id] = picker
        defer { selectPickers.removeValue(forKey: request.id) }
        
        let result = await picker.present()
        
        return result.map(PromptResponse.choices)
    }
    
    private func presentShare(
        session: GeckoSession,
        request: SharePromptRequest
    ) async -> PromptResponse? {
        guard let presenter = UIApplication.shared.topViewController() as? BrowserViewController,
              let sourceView = session.engineView else {
            return nil
        }
        
        let itemSource = WebShareActivityItemSource(
            title: request.title,
            text: request.text,
            url: request.url
        )
        return await withCheckedContinuation { continuation in
            let sourcePoint = CGPoint(
                x: sourceView.bounds.midX,
                y: sourceView.bounds.midY
            )
            presenter.presentShareSheet(
                items: [itemSource],
                sourceView: sourceView,
                sourceRect: CGRect(origin: sourcePoint, size: .zero)
            ) { completed, error in
                let result: SharePromptResult
                if error != nil {
                    result = .failure
                } else if completed {
                    result = .success
                } else {
                    result = .aborted
                }
                continuation.resume(returning: .share(result))
            }
        }
    }
    
    private func promptAnchor(
        for anchor: PromptAnchor,
        session: GeckoSession
    ) -> (view: UIView, rect: CGRect)? {
        guard let rect = anchor.rect,
              let geckoView = session.engineView,
              let window = geckoView.window else {
            return nil
        }
        
        if session.isAddonPopup {
            return (geckoView, rect)
        }
        
        var localRect = rect
        let windowPoint = window.convert(rect.origin, from: nil)
        localRect.origin = geckoView.convert(windowPoint, from: nil)
        return (geckoView, localRect)
    }
    
    // MARK: - Helpers
    
    private func buttonTitle(at index: Int, request: ButtonPromptRequest) -> String {
        let label = request.buttonTitles.indices.contains(index) ? request.buttonTitles[index] : ""
        let customLabel = request.customButtonTitles.indices.contains(index) ? request.customButtonTitles[index] : ""
        
        switch label {
        case "ok":
            return NSLocalizedString("OK", comment: "")
        case "cancel":
            return NSLocalizedString("Cancel", comment: "")
        case "yes":
            return NSLocalizedString("Yes", comment: "")
        case "no":
            return NSLocalizedString("No", comment: "")
        case "custom":
            return customLabel.isEmpty ? NSLocalizedString("OK", comment: "") : customLabel
        default:
            return ""
        }
    }
}

private final class WebShareActivityItemSource: NSObject, UIActivityItemSource {
    private let item: Any
    private let title: String
    
    init(title: String, text: String, url: String?) {
        self.title = title
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = url?.trimmingCharacters(in: .whitespacesAndNewlines)
        let shareURL = trimmedURL.flatMap(URL.init(string:))
        
        if !trimmedText.isEmpty, let trimmedURL, !trimmedURL.isEmpty {
            item = "\(trimmedText)\n\(trimmedURL)"
        } else if !trimmedText.isEmpty {
            item = trimmedText
        } else if let shareURL {
            item = shareURL
        } else if let trimmedURL, !trimmedURL.isEmpty {
            item = trimmedURL
        } else {
            item = title
        }
        super.init()
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return item
    }
    
    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        return item
    }
    
    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        return title
    }
}
