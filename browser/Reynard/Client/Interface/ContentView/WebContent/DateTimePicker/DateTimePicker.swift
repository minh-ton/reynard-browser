//
//  DateTimePicker.swift
//  Reynard
//
//  Created by Minh Ton on 16/4/26.
//

import UIKit

@MainActor
final class DateTimePicker: NSObject, UIPopoverPresentationControllerDelegate {
    let inputMode: String
    let anchorRect: CGRect
    weak var geckoView: UIView?
    
    private var continuation: CheckedContinuation<String?, Never>?
    private weak var presentedController: UIViewController?
    
    init(inputMode: String, anchorRect: CGRect, geckoView: UIView) {
        self.inputMode = inputMode
        self.anchorRect = anchorRect
        self.geckoView = geckoView
    }
    
    // MARK: - Presentation
    
    func present(value: String, min: String, max: String, step: String) async -> String? {
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            showDatePicker(value: value, min: min, max: max, step: step)
        }
    }
    
    private func showDatePicker(value: String, min: String, max: String, step: String) {
        guard let geckoView = geckoView,
              let presenter = UIApplication.shared.topViewController() else {
            finish(nil)
            return
        }
        
        let mode = resolvedPickerMode()
        let initialDate = parseDate(value) ?? Date()
        let minDate = min.isEmpty ? nil : parseDate(min)
        let maxDate = max.isEmpty ? nil : parseDate(max)
        let interval = minuteInterval(for: step)
        
        let datePickerController = DateTimePickerViewController(
            date: initialDate,
            pickerMode: mode,
            minDate: minDate,
            maxDate: maxDate,
            minuteInterval: interval
        )
        datePickerController.modalPresentationStyle = .popover
        
        if let popover = datePickerController.popoverPresentationController {
            popover.sourceView = geckoView
            popover.sourceRect = anchorRect
            popover.permittedArrowDirections = []
            popover.delegate = self
        }
        
        presenter.present(datePickerController, animated: true)
        presentedController = datePickerController
    }
    
    // MARK: - UIPopoverPresentationControllerDelegate
    
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
        Task { @MainActor [weak self, weak popoverPresentationController] in
            guard let self else { return }
            let datePickerController = popoverPresentationController?.presentedViewController as? DateTimePickerViewController
            let date = datePickerController?.selectedDate
            self.finish(date.map { self.formatDate($0) })
        }
        return true
    }
    
    // MARK: - Completion
    
    private func finish(_ result: String?) {
        guard let continuation else { return }
        presentedController = nil
        self.continuation = nil
        continuation.resume(returning: result)
    }
    
    func cancelAndDismiss() {
        presentedController?.dismiss(animated: false)
        finish(nil)
    }
    
    // MARK: - Parsing & Formatters
    
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
            if let date = Self.localFormatter("yyyy-MM-dd'T'HH:mm:ss").date(from: value) { return date }
            return Self.localFormatter("yyyy-MM-dd'T'HH:mm").date(from: value)
        case "time":
            if let date = Self.localFormatter("HH:mm:ss").date(from: value) { return date }
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
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        formatter.timeZone = TimeZone(identifier: "UTC")!
        return formatter
    }
    
    private static func localFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        formatter.timeZone = .current
        return formatter
    }
}
