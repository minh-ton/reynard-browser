//
//  DateTimePicker.swift
//  Reynard
//
//  Created by Minh Ton on 16/4/26.
//

import UIKit

@MainActor
final class DateTimePicker: NSObject, UIPopoverPresentationControllerDelegate {
    let promptId: String
    let inputMode: String
    let anchorRect: CGRect
    weak var geckoView: UIView?
    
    private var continuation: CheckedContinuation<String?, Never>?
    private weak var pickerVC: DateTimePickerViewController?
    
    init(promptId: String, inputMode: String, anchorRect: CGRect, geckoView: UIView) {
        self.promptId = promptId
        self.inputMode = inputMode
        self.anchorRect = anchorRect
        self.geckoView = geckoView
    }
    
    func present(value: String, min: String, max: String, step: String) async -> String? {
        return await withCheckedContinuation { cont in
            continuation = cont
            showPicker(value: value, min: min, max: max, step: step)
        }
    }
    
    private func showPicker(value: String, min: String, max: String, step: String) {
        guard let geckoView = geckoView,
              let presentingVC = geckoView.nearestViewController() else {
            finishWithResult(nil)
            return
        }
        
        let mode = resolvedPickerMode()
        let initialDate = parseDate(value) ?? Date()
        let minDate = min.isEmpty ? nil : parseDate(min)
        let maxDate = max.isEmpty ? nil : parseDate(max)
        let interval = minuteInterval(for: step)
        
        let vc = DateTimePickerViewController(
            date: initialDate,
            pickerMode: mode,
            minDate: minDate,
            maxDate: maxDate,
            minuteInterval: interval
        )
        vc.modalPresentationStyle = .popover
        
        if let popover = vc.popoverPresentationController {
            popover.sourceView = geckoView
            popover.sourceRect = anchorRect
            popover.permittedArrowDirections = []
            popover.delegate = self
        }
        
        pickerVC = vc
        presentingVC.present(vc, animated: true)
    }
    
    // don't full screen
    nonisolated func adaptivePresentationStyle(
        for controller: UIPresentationController,
        traitCollection: UITraitCollection
    ) -> UIModalPresentationStyle {
        return .none
    }
    
    // dismissal
    nonisolated func popoverPresentationControllerShouldDismissPopover(
        _ popoverPresentationController: UIPopoverPresentationController
    ) -> Bool {
        let vc = popoverPresentationController.presentedViewController as? DateTimePickerViewController
        let date = vc?.selectedDate
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.finishWithResult(date.map { self.formatDate($0) })
        }
        return true
    }
    
    private func finishWithResult(_ result: String?) {
        guard let cont = continuation else { return }
        continuation = nil
        cont.resume(returning: result)
    }
    
    private func resolvedPickerMode() -> UIDatePicker.Mode {
        switch inputMode {
        case "time": return .time
        case "date": return .date
        case "datetime-local": return .dateAndTime
        default: return .date
        }
    }
    
    private func parseDate(_ value: String) -> Date? {
        switch inputMode {
        case "date":
            return Self.utcFormatter("yyyy-MM-dd").date(from: value)
        case "datetime-local":
            if let d = Self.localFormatter("yyyy-MM-dd'T'HH:mm:ss").date(from: value) { return d }
            return Self.localFormatter("yyyy-MM-dd'T'HH:mm").date(from: value)
        case "time":
            if let d = Self.localFormatter("HH:mm:ss").date(from: value) { return d }
            return Self.localFormatter("HH:mm").date(from: value)
        default:
            return nil
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        switch inputMode {
        case "date":
            return Self.utcFormatter("yyyy-MM-dd").string(from: date)
        case "datetime-local":
            return Self.localFormatter("yyyy-MM-dd'T'HH:mm").string(from: date)
        case "time":
            return Self.localFormatter("HH:mm").string(from: date)
        default:
            return ""
        }
    }
    
    private func minuteInterval(for step: String) -> Int {
        guard inputMode == "time" || inputMode == "datetime-local",
              let seconds = Double(step),
              seconds > 0 else { return 1 }
        let minutes = Int(seconds / 60)
        guard minutes > 1 else { return 1 }
        let validIntervals = [2, 3, 4, 5, 6, 10, 12, 15, 20, 30]
        return validIntervals.last(where: { $0 <= minutes }) ?? 1
    }
    
    private static func utcFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        f.timeZone = TimeZone(identifier: "UTC")!
        return f
    }
    
    private static func localFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        f.timeZone = .current
        return f
    }
}

private final class DateTimePickerViewController: UIViewController {
    private let datePicker = UIDatePicker()
    
    init(date: Date, pickerMode: UIDatePicker.Mode, minDate: Date?, maxDate: Date?, minuteInterval: Int) {
        super.init(nibName: nil, bundle: nil)
        datePicker.datePickerMode = pickerMode
        if #available(iOS 13.4, *) {
            datePicker.preferredDatePickerStyle = .wheels
        }
        datePicker.date = date
        if let minDate = minDate { datePicker.minimumDate = minDate }
        if let maxDate = maxDate { datePicker.maximumDate = maxDate }
        if minuteInterval > 1 { datePicker.minuteInterval = minuteInterval }
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        datePicker.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(datePicker)
        NSLayoutConstraint.activate([
            datePicker.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            datePicker.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            datePicker.topAnchor.constraint(equalTo: view.topAnchor),
            datePicker.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        preferredContentSize = CGSize(width: 320, height: 216)
    }
    
    var selectedDate: Date {
        datePicker.date
    }
}
