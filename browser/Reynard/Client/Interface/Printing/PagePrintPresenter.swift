//
//  PagePrintPresenter.swift
//  Reynard
//
//  Created by Minh Ton on 22/9/26.
//

import UIKit

@MainActor
enum PagePrintPresenter {
    static func present(pdfFileURL: URL, jobName: String?) async throws {
        defer {
            try? FileManager.default.removeItem(at: pdfFileURL)
        }
        guard UIPrintInteractionController.isPrintingAvailable,
              let presenter = UIApplication.shared.topViewController() else {
            throw PagePrintError.unavailable
        }
        
        let printController = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.outputType = .general
        printInfo.jobName = normalizedJobName(jobName)
        printController.printInfo = printInfo
        printController.printingItem = pdfFileURL
        
        defer {
            printController.printingItem = nil
        }
        
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            let completion: UIPrintInteractionController.CompletionHandler = { _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
            
            if presenter.traitCollection.horizontalSizeClass == .regular {
                let sourceRect = CGRect(
                    x: presenter.view.bounds.midX,
                    y: presenter.view.bounds.midY,
                    width: 0,
                    height: 0
                )
                printController.present(
                    from: sourceRect,
                    in: presenter.view,
                    animated: true,
                    completionHandler: completion
                )
            } else {
                printController.present(animated: true, completionHandler: completion)
            }
        }
    }
    
    private static func normalizedJobName(_ jobName: String?) -> String {
        let trimmedName = jobName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedName.isEmpty ? "Reynard" : trimmedName
    }
}

private enum PagePrintError: Error {
    case unavailable
}
