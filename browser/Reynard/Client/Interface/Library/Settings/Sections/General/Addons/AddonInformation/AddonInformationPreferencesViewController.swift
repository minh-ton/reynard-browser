//
//  AddonInformationPreferencesViewController.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import GeckoView
import UIKit

final class AddonInformationPreferencesViewController: SettingsTableViewController {
    private enum Section {
        case description
        case information
        case links
        
        var text: SettingsSectionText {
            switch self {
            case .description:
                return SettingsSectionText()
            case .information:
                return SettingsSectionText(headerTitle: "Information")
            case .links:
                return SettingsSectionText(headerTitle: "Links")
            }
        }
    }
    
    private struct InformationRow {
        let title: String
        let value: String
        let link: String?
    }
    
    private enum DescriptionRow: CaseIterable {
        case description
    }
    
    private let addonID: String
    private var addon: Addon?
    private let reviewCountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
    private let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
    
    private var displayedSections: [Section] {
        var sections: [Section] = []
        
        if addonDescriptionText != nil {
            sections.append(.description)
        }
        
        if !metadataRows.isEmpty {
            sections.append(.information)
        }
        
        if !externalLinkRows.isEmpty {
            sections.append(.links)
        }
        
        return sections
    }
    
    private var addonDescriptionText: String? {
        guard let metaData = addon?.metaData else {
            return nil
        }
        
        let description = metaData.fullDescription ?? metaData.description
        let trimmed = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
    
    private var metadataRows: [InformationRow] {
        guard let addon else {
            return []
        }
        
        let metaData = addon.metaData
        var rows: [InformationRow] = []
        
        if let creatorName = metaData.creatorName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !creatorName.isEmpty {
            rows.append(InformationRow(title: "Author", value: creatorName, link: normalizedURLString(metaData.creatorURL)))
        }
        
        rows.append(InformationRow(title: "Version", value: metaData.version, link: nil))
        
        if let updateDate = updateDateText(metaData.updateDate) {
            rows.append(InformationRow(title: "Last updated", value: updateDate, link: nil))
        }
        
        if let ratingText = ratingText(metaData) {
            rows.append(InformationRow(title: "Rating", value: ratingText, link: normalizedURLString(metaData.reviewURL)))
        }
        
        return rows
    }
    
    private var externalLinkRows: [InformationRow] {
        guard let metaData = addon?.metaData else {
            return []
        }
        
        var rows: [InformationRow] = []
        
        if let homepageURL = normalizedURLString(metaData.homepageURL) {
            rows.append(InformationRow(title: "Homepage", value: homepageURL, link: homepageURL))
        }
        
        if let listingURL = normalizedURLString(metaData.amoListingURL) {
            rows.append(InformationRow(title: "More about this extension", value: listingURL, link: listingURL))
        }
        
        return rows
    }
    
    // MARK: - Lifecycle
    
    init(addonID: String) {
        self.addonID = addonID
        super.init(style: .insetGrouped)
        title = "Details"
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task { [weak self] in
            await self?.refreshAddon()
        }
    }
    
    // MARK: - Table Structure
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        displayedSections.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard displayedSections.indices.contains(section) else {
            return 0
        }
        
        switch displayedSections[section] {
        case .description:
            return addonDescriptionText == nil ? 0 : DescriptionRow.allCases.count
        case .information:
            return metadataRows.count
        case .links:
            return externalLinkRows.count
        }
    }
    
    override func sectionText(for section: Int) -> SettingsSectionText {
        guard displayedSections.indices.contains(section) else {
            return SettingsSectionText()
        }
        return displayedSections[section].text
    }
    
    // MARK: - Cells
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard displayedSections.indices.contains(indexPath.section) else {
            return UITableViewCell()
        }
        
        switch displayedSections[indexPath.section] {
        case .description:
            guard DescriptionRow.allCases.indices.contains(indexPath.row) else {
                return UITableViewCell()
            }
            switch DescriptionRow.allCases[indexPath.row] {
            case .description:
                let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
                cell.selectionStyle = .none
                cell.textLabel?.numberOfLines = 0
                cell.textLabel?.text = addonDescriptionText
                return cell
            }
        case .information:
            guard metadataRows.indices.contains(indexPath.row) else {
                return UITableViewCell()
            }
            let row = metadataRows[indexPath.row]
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = row.title
            cell.detailTextLabel?.text = row.value
            cell.detailTextLabel?.textColor = row.link == nil ? .secondaryLabel : view.tintColor
            cell.accessoryType = row.link == nil ? .none : .disclosureIndicator
            return cell
        case .links:
            guard externalLinkRows.indices.contains(indexPath.row) else {
                return UITableViewCell()
            }
            let row = externalLinkRows[indexPath.row]
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
            cell.textLabel?.text = row.title
            cell.detailTextLabel?.text = row.value
            cell.detailTextLabel?.numberOfLines = 0
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.accessoryType = .disclosureIndicator
            return cell
        }
    }
    
    // MARK: - Table Delegate
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        
        guard displayedSections.indices.contains(indexPath.section) else {
            return
        }
        
        switch displayedSections[indexPath.section] {
        case .description:
            return
        case .information:
            guard metadataRows.indices.contains(indexPath.row),
                  let url = metadataRows[indexPath.row].link else {
                return
            }
            LibrarySharedUtils.openLinkInBrowser(url, from: self)
        case .links:
            guard externalLinkRows.indices.contains(indexPath.row),
                  let url = externalLinkRows[indexPath.row].link else {
                return
            }
            LibrarySharedUtils.openLinkInBrowser(url, from: self)
        }
    }
    
    // MARK: - Add-on Loading
    
    private func refreshAddon() async {
        do {
            let refreshedAddon = try await AddonRuntime.shared.addon(byID: addonID)
            await MainActor.run {
                guard let refreshedAddon else {
                    self.navigationController?.popViewController(animated: true)
                    return
                }
                
                self.addon = refreshedAddon
                self.title = refreshedAddon.metaData.name ?? refreshedAddon.id
                self.tableView.reloadData()
            }
        } catch {
            await MainActor.run {
                AlertPresenter.show(title: "Failed to reload add-on", message: "\(error)")
            }
        }
    }
    
    // MARK: - Formatting
    
    private func normalizedURLString(_ value: String?) -> String? {
        guard let urlString = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !urlString.isEmpty,
              URL(string: urlString) != nil else {
            return nil
        }
        return urlString
    }
    
    private func updateDateText(_ value: String?) -> String? {
        guard let isoDateString = value,
              let date = ISO8601DateFormatter().date(from: isoDateString) else {
            return nil
        }
        
        return displayDateFormatter.string(from: date)
    }
    
    private func ratingText(_ metaData: AddonMetaData) -> String? {
        guard let averageRating = metaData.averageRating else {
            return nil
        }
        
        let roundedRating = String(format: "%.2f", averageRating)
        if let reviewCount = metaData.reviewCount {
            let reviewText = reviewCountFormatter.string(from: NSNumber(value: reviewCount)) ?? "\(reviewCount)"
            return "\(roundedRating) out of 5 • Reviews: \(reviewText)"
        }
        
        return "\(roundedRating) out of 5"
    }
}
