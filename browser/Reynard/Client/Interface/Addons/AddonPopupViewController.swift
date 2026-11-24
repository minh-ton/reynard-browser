//
//  AddonPopupViewController.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import GeckoView
import UIKit

final class AddonPopupViewController: UIViewController, ContentDelegate, NavigationDelegate, UIPopoverPresentationControllerDelegate, UIGestureRecognizerDelegate {
    enum Presentation {
        case sheet
        case popover
    }
    
    private enum UX {
        static let mediumHeightMultiplier: CGFloat = 0.7
        static let popoverMaximumWidth: CGFloat = 380
        static let sheetCornerRadius: CGFloat = 16
        static let modernSheetCornerRadius: CGFloat = 40
        static let modernSheetInset: CGFloat = 8
        static let closeButtonTopInset: CGFloat = 8
        static let closeButtonTrailingInset: CGFloat = 12
        static let closeButtonSize: CGFloat = 30
        static let geckoViewTopSpacing: CGFloat = 8
        static let shadowOpacity: Float = 0.18
        static let shadowRadius: CGFloat = 12
        static let shadowOffset = CGSize(width: 0, height: -4)
        static let borderWidth: CGFloat = 0.5
    }
    
    private let url: String
    private let sessionManager: SessionManager
    private let openInNewTab: (String) -> Void
    private let createSession: (String, String) -> GeckoSession?
    private let didDismiss: () -> Void
    private let presentation: Presentation
    private let geckoView = GeckoView()
    private let modalTopBorderView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.separator.withAlphaComponent(0.2)
        return view
    }()
    private let session: GeckoSession
    private lazy var promptCoordinator = PromptCoordinator(presenter: PromptPresenter(window: { [weak self] in self?.view.window }))
    private var outsideTapGestureRecognizer: UITapGestureRecognizer?
    private var hasClosedSession = false
    private var hasNotifiedDismissal = false
    
    // MARK: - Lifecycle
    
    init(
        url: String,
        sessionManager: SessionManager,
        openInNewTab: @escaping (String) -> Void,
        createSession: @escaping (String, String) -> GeckoSession?,
        didDismiss: @escaping () -> Void,
        presentation: Presentation
    ) {
        self.url = url
        self.sessionManager = sessionManager
        self.openInNewTab = openInNewTab
        self.createSession = createSession
        self.didDismiss = didDismiss
        self.presentation = presentation
        session = sessionManager.createSession(
            url: url,
            tabID: nil,
            isPrivate: false,
            isAddonPopup: true,
            opening: .manual,
            delegates: SessionDelegates()
        )
        super.init(nibName: nil, bundle: nil)
        if case .popover = presentation {
            modalPresentationStyle = .popover
        } else if #available(iOS 26.0, *) {
            modalPresentationStyle = .pageSheet
            configureModernSheetPresentation()
        }
        configureSession()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        closeSessionIfNeeded()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        loadPopup()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updatePopoverContentSize()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        session.focusForHardwareKeyboard()
        if #available(iOS 26.0, *), case .sheet = presentation {
            // remove the sheet interaction's pan gesture and scroll handoff
            if let interaction = sheetPresentationController?.value(forKey: "_sheetInteraction") as? UIInteraction {
                interaction.view?.removeInteraction(interaction)
            }
            installOutsideTapDismissal()
        }
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        guard size != view.bounds.size,
              !isBeingPresented,
              !isBeingDismissed,
              presentingViewController != nil else {
            return
        }
        
        dismiss(animated: false)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if let outsideTapGestureRecognizer {
            outsideTapGestureRecognizer.view?.removeGestureRecognizer(outsideTapGestureRecognizer)
            self.outsideTapGestureRecognizer = nil
        }
        guard isBeingDismissed || isMovingFromParent || navigationController?.isBeingDismissed == true else {
            return
        }
        
        notifyDismissalIfNeeded()
    }
    
    // MARK: - Setup
    
    private func configureSession() {
        sessionManager.bindDelegates(
            to: session,
            delegates: SessionDelegates(
                content: self,
                navigation: self,
                prompt: promptCoordinator
            )
        )
        sessionManager.open(session)
    }
    
    private func configureView() {
        view.backgroundColor = .clear
        
        switch presentation {
        case .popover:
            configurePopoverView()
        case .sheet:
            if #available(iOS 26.0, *) {
                configureModernSheetView()
            } else {
                configureLegacySheetView()
            }
        }
    }
    
    private func configureLegacySheetView() {
        let containerView = makeContainerView()
        let sheetView = makeSheetView()
        let closeButton = makeCloseButton()
        
        view.addSubview(containerView)
        containerView.addSubview(sheetView)
        sheetView.addSubview(closeButton)
        sheetView.addSubview(geckoView)
        if #unavailable(iOS 26.0) {
            sheetView.addSubview(modalTopBorderView)
        }
        
        constrainContainerView(containerView)
        constrainSheetView(sheetView, in: containerView)
        constrainCloseButton(closeButton, in: sheetView)
        constrainGeckoView(in: sheetView, below: closeButton)
        if #unavailable(iOS 26.0) {
            constrainModalTopBorder(in: sheetView)
        }
    }
    
    @available(iOS 26.0, *)
    private func configureModernSheetPresentation() {
        guard let sheet = sheetPresentationController else {
            return
        }
        
        sheet.prefersGrabberVisible = false
        sheet.preferredCornerRadius = UX.modernSheetCornerRadius
        sheet.setValue(UIVisualEffect(), forKey: "backgroundEffect")
        // avoid scaling the rendered web content to create the sheet's outer insets
        // which causes blurry text. the inset is being created manually btw
        sheet.setValue(true, forKey: "disableSolariumInsets")
        sheet.prefersEdgeAttachedInCompactHeight = true
        sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
        sheet.detents = [.custom(identifier: .init("addon-popup")) { [weak self] context in
            guard let self else {
                return nil
            }
            
            let presentingHeight = self.presentingViewController?.view.bounds.height ?? context.maximumDetentValue
            let isCompactHeight = self.traitCollection.horizontalSizeClass == .compact
            && self.traitCollection.verticalSizeClass == .compact
            let height = isCompactHeight ? presentingHeight : presentingHeight * UX.mediumHeightMultiplier
            
            return min(height, context.maximumDetentValue)
        }]
    }
    
    @available(iOS 26.0, *)
    private func configureModernSheetView() {
        geckoView.translatesAutoresizingMaskIntoConstraints = false
        geckoView.backgroundColor = .systemBackground
        geckoView.layer.cornerCurve = .continuous
        geckoView.layer.cornerRadius = UX.modernSheetCornerRadius
        geckoView.clipsToBounds = true
        view.addSubview(geckoView)
        
        NSLayoutConstraint.activate([
            geckoView.topAnchor.constraint(equalTo: view.topAnchor),
            geckoView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: UX.modernSheetInset),
            geckoView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -UX.modernSheetInset),
            geckoView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -UX.modernSheetInset)
        ])
    }
    
    @available(iOS 26.0, *)
    private func installOutsideTapDismissal() {
        guard let containerView = presentationController?.containerView else {
            return
        }
        
        let gestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(outsideTapRecognized))
        gestureRecognizer.delegate = self
        gestureRecognizer.cancelsTouchesInView = false
        containerView.addGestureRecognizer(gestureRecognizer)
        outsideTapGestureRecognizer = gestureRecognizer
    }
    
    private func configurePopoverView() {
        view.backgroundColor = .systemBackground
        geckoView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(geckoView)
        
        NSLayoutConstraint.activate([
            geckoView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            geckoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            geckoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            geckoView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
    
    private func updatePopoverContentSize() {
        guard case .popover = presentation,
              let presentingView = presentingViewController?.view else {
            return
        }
        
        let isCompact = traitCollection.horizontalSizeClass == .compact
        && traitCollection.verticalSizeClass == .compact
        let height = isCompact
        ? presentingView.bounds.height
        : presentingView.bounds.height * UX.mediumHeightMultiplier
        
        preferredContentSize = CGSize(
            width: min(UX.popoverMaximumWidth, presentingView.bounds.width),
            height: height
        )
    }
    
    private func loadPopup() {
        geckoView.session = session
        sessionManager.activate(session)
        session.load(url)
    }
    
    // MARK: - View Construction
    
    private func makeContainerView() -> UIView {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        view.layer.cornerRadius = UX.sheetCornerRadius
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = UX.shadowOpacity
        view.layer.shadowRadius = UX.shadowRadius
        view.layer.shadowOffset = UX.shadowOffset
        return view
    }
    
    private func makeSheetView() -> UIView {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBackground
        view.layer.cornerRadius = UX.sheetCornerRadius
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.clipsToBounds = true
        return view
    }
    
    private func makeCloseButton() -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(named: "reynard.xmark"), for: .normal)
        button.tintColor = .label
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        return button
    }
    
    // MARK: - Constraints
    
    private func constrainContainerView(_ containerView: UIView) {
        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        let mediumHeight = containerView.heightAnchor.constraint(
            equalTo: view.heightAnchor,
            multiplier: UX.mediumHeightMultiplier
        )
        let largeHeight = containerView.heightAnchor.constraint(equalTo: view.heightAnchor)
        
        if traitCollection.horizontalSizeClass == .compact && traitCollection.verticalSizeClass == .compact {
            largeHeight.isActive = true
        } else {
            mediumHeight.isActive = true
        }
    }
    
    private func constrainSheetView(_ sheetView: UIView, in containerView: UIView) {
        NSLayoutConstraint.activate([
            sheetView.topAnchor.constraint(equalTo: containerView.topAnchor),
            sheetView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            sheetView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            sheetView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
    }
    
    private func constrainCloseButton(_ closeButton: UIButton, in sheetView: UIView) {
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: sheetView.safeAreaLayoutGuide.topAnchor, constant: UX.closeButtonTopInset),
            closeButton.trailingAnchor.constraint(equalTo: sheetView.safeAreaLayoutGuide.trailingAnchor, constant: -UX.closeButtonTrailingInset),
            closeButton.heightAnchor.constraint(equalToConstant: UX.closeButtonSize),
            closeButton.widthAnchor.constraint(equalToConstant: UX.closeButtonSize)
        ])
    }
    
    private func constrainModalTopBorder(in sheetView: UIView) {
        NSLayoutConstraint.activate([
            modalTopBorderView.topAnchor.constraint(equalTo: sheetView.topAnchor),
            modalTopBorderView.leadingAnchor.constraint(equalTo: sheetView.leadingAnchor),
            modalTopBorderView.trailingAnchor.constraint(equalTo: sheetView.trailingAnchor),
            modalTopBorderView.heightAnchor.constraint(equalToConstant: UX.borderWidth),
        ])
    }
    
    private func constrainGeckoView(in sheetView: UIView, below closeButton: UIButton) {
        geckoView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            geckoView.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: UX.geckoViewTopSpacing),
            geckoView.leadingAnchor.constraint(equalTo: sheetView.leadingAnchor),
            geckoView.trailingAnchor.constraint(equalTo: sheetView.trailingAnchor),
            geckoView.bottomAnchor.constraint(equalTo: sheetView.bottomAnchor)
        ])
    }
    
    // MARK: - Actions & Delegates
    
    @objc private func closeTapped() {
        onCloseRequest(session: session)
    }
    
    func onCloseRequest(session: GeckoSession) {
        closeSessionIfNeeded()
        if let navigationController {
            navigationController.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }
    
    // MARK: - UIPopoverPresentationControllerDelegate
    
    nonisolated func adaptivePresentationStyle(
        for controller: UIPresentationController,
        traitCollection: UITraitCollection
    ) -> UIModalPresentationStyle {
        return .none
    }
    
    nonisolated func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        Task { @MainActor [weak self] in
            self?.notifyDismissalIfNeeded()
        }
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === outsideTapGestureRecognizer else {
            return false
        }
        
        return !geckoView.bounds.contains(touch.location(in: geckoView))
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return gestureRecognizer === outsideTapGestureRecognizer
    }
    
    @objc private func outsideTapRecognized() {
        dismiss(animated: true)
    }
    
    func onLoadRequest(session: GeckoSession, request: LoadRequest) async -> AllowOrDeny {
        guard request.target != .current else {
            return .allow
        }
        
        openInNewTab(request.uri)
        return .deny
    }
    
    func onNewSession(session: GeckoSession, uri: String, windowId: String,target: LoadRequestTarget) async -> GeckoSession? {
        return createSession(uri, windowId)
    }
    
    private func closeSessionIfNeeded() {
        guard !hasClosedSession else {
            return
        }
        
        hasClosedSession = true
        geckoView.endEditing(true)
        geckoView.session = nil
        sessionManager.close(session)
    }
    
    private func notifyDismissalIfNeeded() {
        guard !hasNotifiedDismissal else {
            return
        }
        
        hasNotifiedDismissal = true
        closeSessionIfNeeded()
        didDismiss()
    }
}
