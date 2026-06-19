//
//  DateTimePickerViewController.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import UIKit

final class DateTimePickerViewController: UIViewController {
    private enum UX {
        static let contentSize = CGSize(width: 320, height: 216)
    }
    
    private let datePicker = UIDatePicker()
    private let date: Date
    private let pickerMode: UIDatePicker.Mode
    private let minDate: Date?
    private let maxDate: Date?
    private let minuteInterval: Int
    
    var selectedDate: Date {
        datePicker.date
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        configureDatePicker()
        installDatePicker()
    }
    
    init(date: Date, pickerMode: UIDatePicker.Mode, minDate: Date?, maxDate: Date?, minuteInterval: Int) {
        self.date = date
        self.pickerMode = pickerMode
        self.minDate = minDate
        self.maxDate = maxDate
        self.minuteInterval = minuteInterval
        super.init(nibName: nil, bundle: nil)
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
    
    private func configureView() {
        view.backgroundColor = .systemBackground
        preferredContentSize = UX.contentSize
    }
    
    private func configureDatePicker() {
        datePicker.datePickerMode = pickerMode
        if #available(iOS 13.4, *) {
            datePicker.preferredDatePickerStyle = .wheels
        }
        datePicker.date = date
        datePicker.minimumDate = minDate
        datePicker.maximumDate = maxDate
        if minuteInterval > 1 {
            datePicker.minuteInterval = minuteInterval
        }
    }
    
    private func installDatePicker() {
        datePicker.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(datePicker)
        NSLayoutConstraint.activate([
            datePicker.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            datePicker.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            datePicker.topAnchor.constraint(equalTo: view.topAnchor),
            datePicker.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}
