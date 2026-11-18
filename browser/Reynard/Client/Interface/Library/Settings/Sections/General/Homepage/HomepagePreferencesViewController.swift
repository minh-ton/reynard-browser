//
//  HomepagePreferencesViewController.swift
//  Reynard
//
//  Created by Minh Ton on 25/6/26.
//

@preconcurrency import PhotosUI
import UIKit

final class HomepagePreferencesViewController: SettingsTableViewController {
    private enum UX {
        static let wallpaperPreviewSize: CGFloat = 36
        static let wallpaperPreviewCornerRadius: CGFloat = 5
    }
    
    private enum Section: CaseIterable {
        case openingScreen
        case includeOnHomepage
        case homepageBanners
        case wallpaper
        
        var text: SettingsSectionText {
            switch self {
            case .openingScreen:
                return SettingsSectionText(headerTitle: NSLocalizedString("On Startup", comment: ""))
            case .includeOnHomepage:
                return SettingsSectionText(headerTitle: NSLocalizedString("Homepage Sections", comment: ""))
            case .homepageBanners:
                return SettingsSectionText(headerTitle: NSLocalizedString("Homepage Banners", comment: ""))
            case .wallpaper:
                return SettingsSectionText(headerTitle: NSLocalizedString("Wallpaper", comment: ""))
            }
        }
    }
    
    private enum HomepageBannerRow: CaseIterable {
        case recommendations
        case newUpdates
    }
    
    private enum WallpaperRow: CaseIterable {
        case showWallpaper
        case chooseWallpaper
    }
    
    private let recommendationsSwitch = UISwitch()
    private let newUpdatesSwitch = UISwitch()
    private let showWallpaperSwitch = UISwitch()
    private let wallpaperPreviewImageView: UIImageView = {
        let imageView = UIImageView(frame: CGRect(
            x: 0,
            y: 0,
            width: UX.wallpaperPreviewSize,
            height: UX.wallpaperPreviewSize
        ))
        imageView.backgroundColor = .secondarySystemFill
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = UX.wallpaperPreviewCornerRadius
        imageView.clipsToBounds = true
        return imageView
    }()
    
    init() {
        super.init(style: .insetGrouped)
        title = NSLocalizedString("Homepage", comment: "")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureSwitches()
        refreshDisplayedState()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshDisplayedState()
        tableView.reloadData()
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard Section.allCases.indices.contains(section) else {
            return 0
        }
        
        switch Section.allCases[section] {
        case .openingScreen:
            return HomepageOpeningScreen.allCases.count
        case .includeOnHomepage:
            return HomepageSectionPreferencesViewController.OverviewRow.allCases.count
        case .homepageBanners:
            return HomepageBannerRow.allCases.count
        case .wallpaper:
            return WallpaperRow.allCases.count
        }
    }
    
    override func sectionText(for section: Int) -> SettingsSectionText {
        guard Section.allCases.indices.contains(section) else {
            return SettingsSectionText()
        }
        
        return Section.allCases[section].text
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard Section.allCases.indices.contains(indexPath.section) else {
            return UITableViewCell()
        }
        
        switch Section.allCases[indexPath.section] {
        case .openingScreen:
            guard HomepageOpeningScreen.allCases.indices.contains(indexPath.row) else {
                return UITableViewCell()
            }
            
            let openingScreen = HomepageOpeningScreen.allCases[indexPath.row]
            let cell = SettingsTableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = openingScreen.title
            cell.accessoryType = Prefs.HomepageSettings.openingScreen == openingScreen ? .checkmark : .none
            return cell
        case .includeOnHomepage:
            guard HomepageSectionPreferencesViewController.OverviewRow.allCases.indices.contains(indexPath.row) else {
                return UITableViewCell()
            }
            
            let row = HomepageSectionPreferencesViewController.OverviewRow.allCases[indexPath.row]
            let cell = SettingsTableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = row.title
            cell.detailTextLabel?.text = row.isEnabled ? NSLocalizedString("On", comment: "Enabled state") : NSLocalizedString("Off", comment: "Disabled state")
            cell.accessoryType = .disclosureIndicator
            return cell
        case .homepageBanners:
            guard HomepageBannerRow.allCases.indices.contains(indexPath.row) else {
                return UITableViewCell()
            }
            
            let cell = SettingsTableViewCell(style: .default, reuseIdentifier: nil)
            cell.selectionStyle = .none
            switch HomepageBannerRow.allCases[indexPath.row] {
            case .recommendations:
                cell.textLabel?.text = NSLocalizedString("Recommendations", comment: "")
                cell.accessoryView = recommendationsSwitch
            case .newUpdates:
                cell.textLabel?.text = NSLocalizedString("New Updates", comment: "")
                cell.accessoryView = newUpdatesSwitch
            }
            return cell
        case .wallpaper:
            guard WallpaperRow.allCases.indices.contains(indexPath.row) else {
                return UITableViewCell()
            }
            
            let cell = SettingsTableViewCell(style: .default, reuseIdentifier: nil)
            switch WallpaperRow.allCases[indexPath.row] {
            case .showWallpaper:
                cell.textLabel?.text = NSLocalizedString("Show Wallpaper", comment: "")
                cell.selectionStyle = .none
                cell.accessoryView = showWallpaperSwitch
            case .chooseWallpaper:
                cell.textLabel?.text = NSLocalizedString("Choose Wallpaper…", comment: "")
                cell.textLabel?.textColor = view.tintColor
                wallpaperPreviewImageView.image = HomepageWallpaper.image
                cell.accessoryView = wallpaperPreviewImageView
            }
            return cell
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard Section.allCases.indices.contains(indexPath.section) else {
            return
        }
        
        switch Section.allCases[indexPath.section] {
        case .openingScreen:
            guard HomepageOpeningScreen.allCases.indices.contains(indexPath.row) else {
                return
            }
            
            Prefs.HomepageSettings.openingScreen = HomepageOpeningScreen.allCases[indexPath.row]
            tableView.reloadSections(IndexSet(integer: indexPath.section), with: .none)
        case .includeOnHomepage:
            guard HomepageSectionPreferencesViewController.OverviewRow.allCases.indices.contains(indexPath.row) else {
                return
            }
            
            let viewController = HomepageSectionPreferencesViewController(
                preference: HomepageSectionPreferencesViewController.OverviewRow.allCases[indexPath.row].preference
            )
            navigationController?.pushViewController(viewController, animated: true)
        case .homepageBanners:
            return
        case .wallpaper:
            guard WallpaperRow.allCases.indices.contains(indexPath.row) else {
                return
            }
            
            switch WallpaperRow.allCases[indexPath.row] {
            case .showWallpaper:
                return
            case .chooseWallpaper:
                presentWallpaperPicker()
            }
        }
    }
    
    private func configureSwitches() {
        recommendationsSwitch.addTarget(self, action: #selector(recommendationsSwitchDidChange(_:)), for: .valueChanged)
        newUpdatesSwitch.addTarget(self, action: #selector(newUpdatesSwitchDidChange(_:)), for: .valueChanged)
        showWallpaperSwitch.addTarget(self, action: #selector(showWallpaperSwitchDidChange(_:)), for: .valueChanged)
    }
    
    private func refreshDisplayedState() {
        recommendationsSwitch.isOn = Prefs.HomepageSettings.showsRecommendations
        newUpdatesSwitch.isOn = Prefs.HomepageSettings.showsNewUpdates
        showWallpaperSwitch.isOn = Prefs.HomepageSettings.showsWallpaper
    }
    
    @objc private func recommendationsSwitchDidChange(_ sender: UISwitch) {
        Prefs.HomepageSettings.showsRecommendations = sender.isOn
    }
    
    @objc private func newUpdatesSwitchDidChange(_ sender: UISwitch) {
        Prefs.HomepageSettings.showsNewUpdates = sender.isOn
    }
    
    @objc private func showWallpaperSwitchDidChange(_ sender: UISwitch) {
        Prefs.HomepageSettings.showsWallpaper = sender.isOn
    }
    
    // MARK: - Wallpaper
    
    private func presentWallpaperPicker() {
        if #available(iOS 14.0, *) {
            var configuration = PHPickerConfiguration()
            configuration.filter = .images
            configuration.selectionLimit = 1
            configuration.preferredAssetRepresentationMode = .current
            
            let picker = PHPickerViewController(configuration: configuration)
            picker.delegate = self
            present(picker, animated: true)
            return
        }
        
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = .photoLibrary
        picker.mediaTypes = ["public.image"]
        present(picker, animated: true)
    }
    
    private func saveWallpaper(_ wallpaper: ImageUtils.JPEGImage) {
        do {
            try HomepageWallpaper.save(wallpaper)
        } catch {
            return
        }
        wallpaperPreviewImageView.image = HomepageWallpaper.image
    }
    
    private func prepareWallpaper(from imageData: Data) async {
        guard let screen = view.window?.windowScene?.screen else {
            return
        }
        let maximumPixelSize = Int(max(screen.nativeBounds.width, screen.nativeBounds.height))
        let wallpaper = await Task.detached(priority: .userInitiated) {
            return ImageUtils.prepareJPEGImage(
                from: imageData,
                maximumPixelSize: maximumPixelSize
            )
        }.value
        guard let wallpaper else {
            return
        }
        saveWallpaper(wallpaper)
    }
}

@available(iOS 14.0, *)
extension HomepagePreferencesViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let itemProvider = results.first?.itemProvider,
              itemProvider.hasItemConformingToTypeIdentifier("public.image") else {
            return
        }
        itemProvider.loadDataRepresentation(forTypeIdentifier: "public.image") { [weak self] imageData, _ in
            guard let imageData else {
                return
            }
            Task { @MainActor [weak self] in
                await self?.prepareWallpaper(from: imageData)
            }
        }
    }
}

extension HomepagePreferencesViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    nonisolated func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        Task { @MainActor in
            picker.dismiss(animated: true)
        }
    }
    
    nonisolated func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        let imageURL = info[.imageURL] as? URL
        
        Task { @MainActor [weak self] in
            picker.dismiss(animated: true)
            guard let imageURL,
                  let imageData = await Task.detached(priority: .userInitiated, operation: {
                      return try? Data(contentsOf: imageURL)
                  }).value else {
                return
            }
            await self?.prepareWallpaper(from: imageData)
        }
    }
}
