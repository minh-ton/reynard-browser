//
//  AddonPopupViewController.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import GeckoView
import UIKit

final class AddonPopupViewController: UIViewController, ContentDelegate, NavigationDelegate {
    private enum UX {
        static let maxSheetWidth: CGFloat = 430
        static let portraitSheetHeight: CGFloat = 430
        static let sheetCornerRadius: CGFloat = 20
        static let closeButtonTopInset: CGFloat = 12
        static let closeButtonTrailingInset: CGFloat = 12
        static let closeButtonSize: CGFloat = 36
        static let shadowOpacity: Float = 0.22
        static let shadowRadius: CGFloat = 18
        static let shadowOffset = CGSize(width: 0, height: -6)
    }
    
    private let url: String
    private let sessionManager: SessionManager
    private let openInNewTab: (String) -> Void
    private let createSession: (String, String) -> GeckoSession?
    private let didDismiss: () -> Void
    private let geckoView = GeckoView()
    private let session: GeckoSession
    private var hasClosedSession = false
    
    // MARK: - Lifecycle
    
    init(
        url: String,
        sessionManager: SessionManager,
        openInNewTab: @escaping (String) -> Void,
        createSession: @escaping (String, String) -> GeckoSession?,
        didDismiss: @escaping () -> Void
    ) {
        self.url = url
        self.sessionManager = sessionManager
        self.openInNewTab = openInNewTab
        self.createSession = createSession
        self.didDismiss = didDismiss
        session = sessionManager.createSession(
            url: url,
            tabID: nil,
            isPrivate: false,
            isAddonPopup: true,
            opening: .manual,
            delegates: SessionDelegates()
        )
        super.init(nibName: nil, bundle: nil)
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(beginRegionSelection),
            name: Notification.Name("GeckoView.WebExtension.BeginRegionSelection"),
            object: nil
        )
        configureView()
        loadPopup()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || isMovingFromParent || navigationController?.isBeingDismissed == true else {
            return
        }
        
        closeSessionIfNeeded()
        didDismiss()
    }

    // MARK: - Setup
    
    private func configureSession() {
        sessionManager.bindDelegates(
            to: session,
            delegates: SessionDelegates(content: self, navigation: self)
        )
        sessionManager.open(session)
    }
    
    private func configureView() {
        view.backgroundColor = .clear
        
        let backdropControl = makeBackdropControl()
        let containerView = makeContainerView()
        let sheetView = makeSheetView()
        let closeButton = makeCloseButton()
        
        view.addSubview(backdropControl)
        view.addSubview(containerView)
        containerView.addSubview(sheetView)
        sheetView.addSubview(geckoView)
        sheetView.addSubview(closeButton)
        
        constrainBackdropControl(backdropControl)
        constrainContainerView(containerView)
        constrainSheetView(sheetView, in: containerView)
        constrainCloseButton(closeButton, in: sheetView)
        constrainGeckoView(in: sheetView)
    }
    
    private func loadPopup() {
        geckoView.session = session
        sessionManager.activate(session)
        session.load(url)
    }
    
    // MARK: - View Construction

    private func makeBackdropControl() -> UIControl {
        let control = UIControl()
        control.translatesAutoresizingMaskIntoConstraints = false
        control.backgroundColor = UIColor.black.withAlphaComponent(0.28)
        control.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        return control
    }
    
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
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        button.setImage(UIImage(systemName: "xmark", withConfiguration: symbolConfiguration), for: .normal)
        button.tintColor = .label
        button.backgroundColor = .secondarySystemBackground
        button.layer.cornerRadius = UX.closeButtonSize / 2
        button.accessibilityLabel = "Close"
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        return button
    }
    
    // MARK: - Constraints

    private func constrainBackdropControl(_ backdropControl: UIControl) {
        NSLayoutConstraint.activate([
            backdropControl.topAnchor.constraint(equalTo: view.topAnchor),
            backdropControl.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdropControl.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backdropControl.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func constrainContainerView(_ containerView: UIView) {
        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.widthAnchor.constraint(lessThanOrEqualToConstant: UX.maxSheetWidth),
            containerView.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor),
            containerView.widthAnchor.constraint(equalTo: view.widthAnchor).withPriority(.defaultLow),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        let portraitHeight = containerView.heightAnchor.constraint(equalToConstant: UX.portraitSheetHeight)
        portraitHeight.priority = .defaultHigh
        let maximumHeight = containerView.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor)
        let largeHeight = containerView.heightAnchor.constraint(equalTo: view.heightAnchor)
        
        if traitCollection.horizontalSizeClass == .compact && traitCollection.verticalSizeClass == .compact {
            largeHeight.isActive = true
        } else {
            portraitHeight.isActive = true
            maximumHeight.isActive = true
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
    
    private func constrainGeckoView(in sheetView: UIView) {
        geckoView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            geckoView.topAnchor.constraint(equalTo: sheetView.topAnchor),
            geckoView.leadingAnchor.constraint(equalTo: sheetView.leadingAnchor),
            geckoView.trailingAnchor.constraint(equalTo: sheetView.trailingAnchor),
            geckoView.bottomAnchor.constraint(equalTo: sheetView.bottomAnchor)
        ])
    }

    // MARK: - Actions & Delegates
    
    @objc private func closeTapped() {
        onCloseRequest(session: session)
    }

    @objc private func beginRegionSelection() {
        closeSessionIfNeeded()
        dismiss(animated: true)
    }
    
    func onCloseRequest(session: GeckoSession) {
        closeSessionIfNeeded()
        if let navigationController {
            navigationController.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }
    
    func onLoadRequest(session: GeckoSession, request: LoadRequest) async -> AllowOrDeny {
        guard request.target == .new else {
            return .allow
        }
        
        openInNewTab(request.uri)
        return .deny
    }
    
    func onNewSession(session: GeckoSession, uri: String, windowId: String) async -> GeckoSession? {
        return createSession(uri, windowId)
    }

    private func closeSessionIfNeeded() {
        guard !hasClosedSession else {
            return
        }
        
        hasClosedSession = true
        geckoView.session = nil
        sessionManager.close(session)
    }
}
