//
//  PromptDelegate.swift
//  Reynard
//
//  Created by Minh Ton on 8/4/26.
//

import UIKit

struct ChoiceItem {
    let id: String
    let label: String
    let disabled: Bool
    let selected: Bool
    let items: [ChoiceItem]?
    let separator: Bool
}

private func parseChoices(_ raw: Any?) -> [ChoiceItem] {
    guard let array = raw as? [[String: Any]] else { return [] }
    return array.map { dict in
        ChoiceItem(
            id: dict["id"] as? String ?? "",
            label: dict["label"] as? String ?? "",
            disabled: dict["disabled"] as? Bool ?? false,
            selected: dict["selected"] as? Bool ?? false,
            items: (dict["items"] != nil) ? parseChoices(dict["items"]) : nil,
            separator: dict["separator"] as? Bool ?? false
        )
    }
}

enum PromptEvents: String, CaseIterable {
    case prompt = "GeckoView:Prompt"
    case promptUpdate = "GeckoView:Prompt:Update"
    case promptDismiss = "GeckoView:Prompt:Dismiss"
}

@MainActor
private var activePickers: [String: SelectPicker] = [:]

func newPromptHandler(_ session: GeckoSession) -> GeckoSessionHandler {
    GeckoSessionHandler(
        moduleName: "GeckoViewPrompter",
        events: PromptEvents.allCases.map(\.rawValue),
        session: session
    ) { @MainActor session, delegate, type, message in
        guard let message else { return nil }
        guard let promptEvent = PromptEvents(rawValue: type) else { return nil }
        
        switch promptEvent {
        case .prompt:
            guard let promptData = message["prompt"] as? [String: Any] else {
                return nil
            }
            let promptType = promptData["type"] as? String
            guard promptType == "choice" else {
                return nil
            }
            
            let promptId = promptData["id"] as? String ?? ""
            let mode = promptData["mode"] as? String ?? "single"
            let rawChoices = promptData["choices"]
            let choices = parseChoices(rawChoices)
            
            let rectDict = promptData["rect"] as? [String: Any]
            var rect = CGRect(
                x: (rectDict?["left"] as? Double) ?? 0,
                y: (rectDict?["top"] as? Double) ?? 0,
                width: (rectDict?["width"] as? Double) ?? 0,
                height: (rectDict?["height"] as? Double) ?? 0
            )
            
            guard let childView = session.window?.view() else { return nil }
            guard let geckoView = childView.superview else { return nil }
            
            if let window = geckoView.window {
                let windowPoint = window.convert(rect.origin, from: nil)
                let localPoint = geckoView.convert(windowPoint, from: nil)
                rect.origin = localPoint
            }
            
            let picker = SelectPicker(
                promptId: promptId,
                mode: mode,
                choices: choices,
                sourceRect: rect,
                geckoView: geckoView
            )
            activePickers[promptId] = picker
            
            let result = await picker.present()
            activePickers.removeValue(forKey: promptId)
            
            if let selectedIds = result {
                return ["choices": selectedIds]
            }
            return nil
            
        case .promptUpdate:
            guard let promptData = message["prompt"] as? [String: Any] else {
                return nil
            }
            let promptId = promptData["id"] as? String ?? ""
            if let picker = activePickers[promptId] {
                let newChoices = parseChoices(promptData["choices"])
                let newMode = promptData["mode"] as? String ?? picker.mode
                picker.updateChoices(newChoices, mode: newMode)
            }
            return nil
            
        case .promptDismiss:
            // Gecko fires dismiss when the <select> element blurs, which happens when
            // we present native UI (the modal steals focus). Our picker manages its own
            // lifecycle through user interaction, so we intentionally ignore dismiss
            // while a picker is actively presented.
            return nil
        }
    }
}

@MainActor
final class SelectPicker {
    let promptId: String
    var mode: String
    var choices: [ChoiceItem]
    let sourceRect: CGRect
    weak var geckoView: UIView?
    
    private var continuation: CheckedContinuation<[String]?, Never>?
    private var anchorButton: MenuAnchorButton?
    private var presentedController: UIViewController?
    
    init(promptId: String, mode: String, choices: [ChoiceItem], sourceRect: CGRect, geckoView: UIView) {
        self.promptId = promptId
        self.mode = mode
        self.choices = choices
        self.sourceRect = sourceRect
        self.geckoView = geckoView
    }
    
    func present() async -> [String]? {
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            if mode == "multiple" {
                showMultiSelect()
            } else {
                showSingleSelect()
            }
        }
    }
    
    func updateChoices(_ newChoices: [ChoiceItem], mode newMode: String) {
        choices = newChoices
        mode = newMode
        if let nav = presentedController as? UINavigationController,
           let vc = nav.viewControllers.first as? MultiSelectViewController {
            vc.updateChoices(newChoices)
        }
    }
    
    func cancelAndDismiss() {
        anchorButton?.removeFromSuperview()
        anchorButton = nil
        presentedController?.dismiss(animated: false)
        presentedController = nil
        if let cont = continuation {
            continuation = nil
            cont.resume(returning: nil)
        }
    }
    
    private func showSingleSelect() {
        guard let geckoView = geckoView else {
            finishWithResult(nil)
            return
        }
        
        let button = MenuAnchorButton(frame: sourceRect)
        button.backgroundColor = .clear
        
        let menuElements = buildMenuElements(from: choices)
        button.menu = UIMenu(children: menuElements)
        button.showsMenuAsPrimaryAction = true
        
        button.onMenuDismissed = { [weak self] in
            self?.handleMenuDismissed()
        }
        
        geckoView.addSubview(button)
        anchorButton = button
        
        DispatchQueue.main.async { [weak self] in
            guard let button = self?.anchorButton else { return }
            let interaction = button.interactions.compactMap { $0 as? UIContextMenuInteraction }.first
            guard let interaction = interaction else {
                self?.handleMenuDismissed()
                return
            }
            
            // Ugh we have to use private API here
            let sel = NSSelectorFromString("_presentMenuAtLocation:")
            if interaction.responds(to: sel) {
                let center = CGPoint(x: button.bounds.midX, y: button.bounds.midY)
                let imp = interaction.method(for: sel)
                typealias PresentFunc = @convention(c) (AnyObject, Selector, CGPoint) -> Void
                let present = unsafeBitCast(imp, to: PresentFunc.self)
                present(interaction, sel, center)
            } else {
                self?.handleMenuDismissed()
            }
        }
    }
    
    private func buildMenuElements(from items: [ChoiceItem]) -> [UIMenuElement] {
        var elements: [UIMenuElement] = []
        var pendingItems: [UIMenuElement] = []
        
        for item in items {
            if item.separator {
                if !pendingItems.isEmpty {
                    let group = UIMenu(title: "", options: .displayInline, children: pendingItems)
                    elements.append(group)
                    pendingItems = []
                }
                continue
            }
            
            if let subItems = item.items {
                if !pendingItems.isEmpty {
                    let group = UIMenu(title: "", options: .displayInline, children: pendingItems)
                    elements.append(group)
                    pendingItems = []
                }
                let subActions = buildMenuElements(from: subItems)
                let submenu = UIMenu(title: item.label, options: .displayInline, children: subActions)
                elements.append(submenu)
            } else {
                let choiceId = item.id
                let action = UIAction(
                    title: item.label,
                    attributes: item.disabled ? .disabled : [],
                    state: item.selected ? .on : .off
                ) { [weak self] _ in
                    self?.finishWithResult([choiceId])
                }
                pendingItems.append(action)
            }
        }
        
        if !pendingItems.isEmpty {
            if elements.isEmpty {
                return pendingItems
            }
            let group = UIMenu(title: "", options: .displayInline, children: pendingItems)
            elements.append(group)
        }
        
        return elements
    }
    
    private func handleMenuDismissed() {
        anchorButton?.removeFromSuperview()
        anchorButton = nil
        // If no selection was made yet, resume with nil (cancel)
        if let cont = continuation {
            continuation = nil
            cont.resume(returning: nil)
        }
    }
    
    private func showMultiSelect() {
        guard let geckoView = geckoView,
              let presentingVC = geckoView.nearestViewController() else {
            finishWithResult(nil)
            return
        }
        
        let vc = MultiSelectViewController(choices: choices) { [weak self] selectedIds in
            self?.presentedController = nil
            self?.finishWithResult(selectedIds)
        }
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        
        if let popover = nav.popoverPresentationController {
            popover.sourceView = geckoView
            popover.sourceRect = sourceRect
        }
        
        presentingVC.present(nav, animated: true)
        presentedController = nav
    }
    
    private func finishWithResult(_ result: [String]?) {
        anchorButton?.removeFromSuperview()
        anchorButton = nil
        guard let cont = continuation else { return }
        continuation = nil
        cont.resume(returning: result)
    }
}

private final class MenuAnchorButton: UIButton {
    var onMenuDismissed: (() -> Void)?
    
    override func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willEndFor configuration: UIContextMenuConfiguration,
        animator: UIContextMenuInteractionAnimating?
    ) {
        super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
        let handler = onMenuDismissed
        if let animator = animator {
            animator.addCompletion {
                handler?()
            }
        } else {
            handler?()
        }
    }
}

private final class MultiSelectViewController: UIViewController,
                                               UITableViewDataSource, UITableViewDelegate
{
    private var choices: [ChoiceItem]
    private var selectedIds: Set<String>
    private var sections: [(title: String?, items: [ChoiceItem])] = []
    private var tableView: UITableView!
    private var onDone: (([String]?) -> Void)?
    
    init(choices: [ChoiceItem], onDone: @escaping ([String]?) -> Void) {
        self.choices = choices
        self.onDone = onDone
        self.selectedIds = Self.collectSelectedIds(from: choices)
        super.init(nibName: nil, bundle: nil)
        rebuildSections()
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
    
    func updateChoices(_ newChoices: [ChoiceItem]) {
        choices = newChoices
        rebuildSections()
        tableView?.reloadData()
    }
    
    private func rebuildSections() {
        sections = []
        var currentItems: [ChoiceItem] = []
        
        for item in choices {
            if item.separator {
                if !currentItems.isEmpty {
                    sections.append((title: nil, items: currentItems))
                    currentItems = []
                }
                continue
            }
            
            if let subItems = item.items {
                if !currentItems.isEmpty {
                    sections.append((title: nil, items: currentItems))
                    currentItems = []
                }
                sections.append((title: item.label, items: subItems.filter { !$0.separator }))
            } else {
                currentItems.append(item)
            }
        }
        
        if !currentItems.isEmpty {
            sections.append((title: nil, items: currentItems))
        }
    }
    
    private static func collectSelectedIds(from choices: [ChoiceItem]) -> Set<String> {
        var ids = Set<String>()
        for choice in choices {
            if choice.selected { ids.insert(choice.id) }
            if let items = choice.items {
                ids.formUnion(collectSelectedIds(from: items))
            }
        }
        return ids
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Select Options"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneTapped)
        )
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        
        tableView = UITableView(frame: view.bounds, style: .insetGrouped)
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
    }
    
    @objc private func doneTapped() {
        let result = Array(selectedIds)
        dismiss(animated: true) { [weak self] in
            self?.onDone?(result)
            self?.onDone = nil
        }
    }
    
    @objc private func cancelTapped() {
        dismiss(animated: true) { [weak self] in
            self?.onDone?(nil)
            self?.onDone = nil
        }
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].items.count
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let item = sections[indexPath.section].items[indexPath.row]
        cell.textLabel?.text = item.label
        cell.accessoryType = selectedIds.contains(item.id) ? .checkmark : .none
        cell.textLabel?.isEnabled = !item.disabled
        cell.selectionStyle = item.disabled ? .none : .default
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = sections[indexPath.section].items[indexPath.row]
        guard !item.disabled else { return }
        
        if selectedIds.contains(item.id) {
            selectedIds.remove(item.id)
        } else {
            selectedIds.insert(item.id)
        }
        tableView.reloadRows(at: [indexPath], with: .automatic)
    }
}

private extension UIView {
    func nearestViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let vc = next as? UIViewController {
                return vc
            }
            responder = next
        }
        return nil
    }
}
