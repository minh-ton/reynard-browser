//
//  EnginePromptCoordinator.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import GeckoView
import UIKit

@MainActor
final class EnginePromptCoordinator: PromptDelegate {
    // MARK: - State

    private var activeSelectPickers: [String: SelectPicker] = [:]
    private var activeColorPickers: [String: ColorPicker] = [:]
    private var activeDateTimePickers: [String: DateTimePicker] = [:]
    private var activeFilePickers: [String: FilePicker] = [:]

    // MARK: - Lifecycle

    init() {}

    // MARK: - PromptDelegate

    func onPrompt(session: GeckoSession, request: PromptRequest) async -> PromptResponse? {
        switch request {
        case .alert(let request):
            await presentAlert(session: session, request: request)
            return nil

        case .button(let request):
            return await presentButtonPrompt(session: session, request: request)

        case .text(let request):
            return await presentTextPrompt(session: session, request: request)

        case .folderUpload(let request):
            return await presentFolderUploadPrompt(session: session, request: request)

        case .color(let request):
            return await presentColorPrompt(session: session, request: request)

        case .dateTime(let request):
            return await presentDateTimePrompt(session: session, request: request)

        case .file(let request):
            return await presentFilePrompt(session: session, request: request)

        case .choice(let request):
            return await presentSelectPrompt(session: session, request: request)
        }
    }

    func onPromptUpdate(session: GeckoSession, request: PromptRequest) {
        guard case .choice(let request) = request,
              let picker = activeSelectPickers[request.id] else {
            return
        }

        picker.updateChoices(request.choices, mode: request.mode)
    }

    func onPromptDismiss(session: GeckoSession, promptId: String) {
        if activeDateTimePickers[promptId] != nil {
            // Gecko fires dismiss when native date UI steals focus; the picker owns completion.
            return
        }
        activeSelectPickers.removeValue(forKey: promptId)?.cancelAndDismiss()
        activeColorPickers.removeValue(forKey: promptId)?.cancelAndDismiss()
        activeDateTimePickers.removeValue(forKey: promptId)?.cancelAndDismiss()
        activeFilePickers.removeValue(forKey: promptId)?.cancelAndDismiss()
    }

    // MARK: - Basic Prompts

    private func presentAlert(session: GeckoSession, request: AlertPromptRequest) async {
        guard let presenter = resolvePresenter(session: session) else {
            return
        }

        await withCheckedContinuation { continuation in
            let alert = UIAlertController(
                title: request.title.isEmpty ? nil : request.title,
                message: request.message.isEmpty ? nil : request.message,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                continuation.resume()
            })
            presenter.present(alert, animated: true)
        }
    }

    private func presentButtonPrompt(
        session: GeckoSession,
        request: ButtonPromptRequest
    ) async -> PromptResponse? {
        guard let presenter = resolvePresenter(session: session) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(
                title: request.title.isEmpty ? nil : request.title,
                message: request.message.isEmpty ? nil : request.message,
                preferredStyle: .alert
            )

            for index in 0..<3 {
                let title = localizedButtonTitle(at: index, request: request)
                guard !title.isEmpty else { continue }

                let isCancel = index == 2 &&
                    request.buttonTitles.indices.contains(index) &&
                    request.buttonTitles[index] == "cancel"
                alert.addAction(UIAlertAction(
                    title: title,
                    style: isCancel ? .cancel : .default
                ) { _ in
                    continuation.resume(returning: .button(index))
                })
            }

            if alert.actions.isEmpty {
                alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                    continuation.resume(returning: .button(0))
                })
            }

            presenter.present(alert, animated: true)
        }
    }

    private func presentTextPrompt(
        session: GeckoSession,
        request: TextPromptRequest
    ) async -> PromptResponse? {
        guard let presenter = resolvePresenter(session: session) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(
                title: request.title.isEmpty ? nil : request.title,
                message: request.message.isEmpty ? nil : request.message,
                preferredStyle: .alert
            )
            alert.addTextField { textField in
                textField.text = request.value
            }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                continuation.resume(returning: nil)
            })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                continuation.resume(returning: .text(alert.textFields?.first?.text ?? ""))
            })
            presenter.present(alert, animated: true)
        }
    }

    private func presentFolderUploadPrompt(
        session: GeckoSession,
        request: FolderUploadPromptRequest
    ) async -> PromptResponse? {
        guard let presenter = resolvePresenter(session: session) else {
            return nil
        }

        let message = request.directoryName.isEmpty
            ? "Are you sure you want to upload all files? Only do this if you trust the site."
            : "Are you sure you want to upload all files from \"\(request.directoryName)\"? Only do this if you trust the site."

        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(
                title: "Confirm Upload",
                message: message,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                continuation.resume(returning: .folderUpload(allowed: false))
            })
            alert.addAction(UIAlertAction(title: "Upload", style: .default) { _ in
                continuation.resume(returning: .folderUpload(allowed: true))
            })
            presenter.present(alert, animated: true)
        }
    }

    // MARK: - Picker Prompts

    private func presentColorPrompt(
        session: GeckoSession,
        request: ColorPromptRequest
    ) async -> PromptResponse? {
        guard let anchor = resolveAnchorFrame(request.anchor, session: session) else {
            return nil
        }

        let picker = ColorPicker(
            anchorRect: anchor.rect,
            geckoView: anchor.view
        )
        activeColorPickers[request.id] = picker
        defer { activeColorPickers.removeValue(forKey: request.id) }

        let result = await picker.present(initialColor: UIColor(hexString: request.value) ?? .black)

        return result.map(PromptResponse.color)
    }

    private func presentDateTimePrompt(
        session: GeckoSession,
        request: DateTimePromptRequest
    ) async -> PromptResponse? {
        guard let anchor = resolveAnchorFrame(request.anchor, session: session) else {
            return nil
        }

        let picker = DateTimePicker(
            inputMode: request.mode,
            anchorRect: anchor.rect,
            geckoView: anchor.view
        )
        activeDateTimePickers[request.id] = picker
        defer { activeDateTimePickers.removeValue(forKey: request.id) }

        let result = await picker.present(
            value: request.value,
            min: request.min,
            max: request.max,
            step: request.step
        )

        return result.map(PromptResponse.dateTime)
    }

    private func presentFilePrompt(
        session: GeckoSession,
        request: FilePickerPromptRequest
    ) async -> PromptResponse? {
        guard let anchor = resolveAnchorFrame(request.anchor, session: session) else {
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
        activeFilePickers[request.id] = picker
        defer { activeFilePickers.removeValue(forKey: request.id) }

        let result = await picker.present()

        return result.map(PromptResponse.files)
    }

    private func presentSelectPrompt(
        session: GeckoSession,
        request: SelectPromptRequest
    ) async -> PromptResponse? {
        guard let anchor = resolveAnchorFrame(request.anchor, session: session) else {
            return nil
        }

        let picker = SelectPicker(
            mode: request.mode,
            choices: request.choices,
            sourceRect: anchor.rect,
            geckoView: anchor.view
        )
        activeSelectPickers[request.id] = picker
        defer { activeSelectPickers.removeValue(forKey: request.id) }

        let result = await picker.present()

        return result.map(PromptResponse.choices)
    }

    // MARK: - Resolution

    private func resolvePresenter(session: GeckoSession) -> UIViewController? {
        session.engineView?.nearestViewController()?.topPresentedController()
    }

    private func resolveAnchorFrame(
        _ anchor: PromptAnchor,
        session: GeckoSession
    ) -> (view: UIView, rect: CGRect)? {
        guard let rect = anchor.rect,
              let geckoView = session.engineView,
              let window = geckoView.window else {
            return nil
        }

        var localRect = rect
        let windowPoint = window.convert(rect.origin, from: nil)
        localRect.origin = geckoView.convert(windowPoint, from: nil)
        return (geckoView, localRect)
    }

    // MARK: - Helpers

    private func localizedButtonTitle(at index: Int, request: ButtonPromptRequest) -> String {
        let label = request.buttonTitles.indices.contains(index) ? request.buttonTitles[index] : ""
        let customLabel = request.customButtonTitles.indices.contains(index) ? request.customButtonTitles[index] : ""

        switch label {
        case "ok":
            return "OK"
        case "cancel":
            return "Cancel"
        case "yes":
            return "Yes"
        case "no":
            return "No"
        case "custom":
            return customLabel.isEmpty ? "OK" : customLabel
        default:
            return ""
        }
    }
}
