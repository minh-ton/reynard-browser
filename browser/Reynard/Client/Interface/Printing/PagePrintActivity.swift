//
//  PagePrintActivity.swift
//  Reynard
//
//  Created by Minh Ton on 22/9/26.
//

import GeckoView
import UIKit

@MainActor
final class PagePrintActivity: UIActivity {
    private let session: GeckoSession
    private let jobName: String?
    
    init(session: GeckoSession, jobName: String?) {
        self.session = session
        self.jobName = jobName
        super.init()
    }
    
    override class var activityCategory: UIActivity.Category { .action }
    override var activityType: UIActivity.ActivityType? {
        UIActivity.ActivityType("com.minh-ton.Reynard.PagePrintActivity")
    }
    override var activityTitle: String? { NSLocalizedString("Print", comment: "") }
    override var activityImage: UIImage? { UIImage(named: "reynard.printer") }
    
    override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        return UIPrintInteractionController.isPrintingAvailable
    }
    
    override func perform() {
        Task { @MainActor in
            do {
                let pdfFileURL = try await PagePrintPreparationAlert.prepare(in: session.engineView?.window) {
                    try await self.session.printToPDF()
                }
                try await PagePrintPresenter.present(pdfFileURL: pdfFileURL, jobName: jobName, in: session.engineView?.window)
                activityDidFinish(true)
            } catch {
                activityDidFinish(false)
            }
        }
    }
}
