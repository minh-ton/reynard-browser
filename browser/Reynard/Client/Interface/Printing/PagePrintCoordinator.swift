//
//  PagePrintCoordinator.swift
//  Reynard
//
//  Created by Minh Ton on 22/9/26.
//

import GeckoView

@MainActor
final class PagePrintCoordinator: PrintDelegate {
    private let jobName: (GeckoSession) -> String?
    
    init(jobName: @escaping (GeckoSession) -> String?) {
        self.jobName = jobName
    }
    
    func onPrint(session: GeckoSession, browsingContextId: Int64?) async throws {
        let pdfFileURL = try await PagePrintPreparationAlert.prepare(in: session.engineView?.window) {
            try await session.printToPDF(browsingContextId: browsingContextId)
        }
        try await PagePrintPresenter.present(
            pdfFileURL: pdfFileURL,
            jobName: jobName(session),
            in: session.engineView?.window
        )
    }
}
