import AppKit
import SuguCore
import UniformTypeIdentifiers

final class AdvancedPane: SettingsPane {
    override func build() {
        let model = model
        let importButton = form.makeButton(String(localized: "Import…")) { [weak self] in self?.importSettings() }
        let exportButton = form.makeButton(String(localized: "Export…")) { [weak self] in self?.exportSettings() }
        form.row(String(localized: "Settings file:"), NSStackView(views: [importButton, exportButton]))
        form.button(String(localized: "Reset…"), label: String(localized: "Default settings:")) { [weak self] in
            self?.confirm(String(localized: "Reset all settings to their defaults?"), action: String(localized: "Reset"), destructive: true) {
                self?.apply(model.defaultSettings)
            }
        }

        form.gap()
        form.button(String(localized: "Show in Finder"), label: String(localized: "Data folder:")) { model.showDataFolder() }
        form.button(String(localized: "Export…"), label: String(localized: "Diagnostics:")) { [weak self] in self?.exportDiagnostics() }

        form.gap()
        let automatic = form.checkbox(String(localized: "Check for updates automatically"), label: String(localized: "Updates:"),
                                      get: { model.checksForUpdatesAutomatically }, set: { model.checksForUpdatesAutomatically = $0 })
        let checkNow = form.button(String(localized: "Check Now")) { model.checkForUpdates() }
        automatic.isEnabled = model.updatesAvailable
        checkNow.isEnabled = model.updatesAvailable

        form.gap()
        let version = NSTextField(labelWithString: model.version)
        version.isSelectable = true
        form.row(String(localized: "Version:"), version)
        let link = form.makeButton("sugu.zheng-she.com") {
            NSWorkspace.shared.open(URL(string: "https://sugu.zheng-she.com")!)
        }
        link.isBordered = false
        link.contentTintColor = .linkColor
        link.setAccessibilityRole(.link)
        form.row(String(localized: "Website:"), link)
        form.button(String(localized: "Show"), label: String(localized: "Acknowledgements:")) { [weak self] in self?.showNotices() }
    }

    private func exportSettings() {
        guard let window = view.window else { return }
        let data: Data
        do {
            data = try model.exportSettings()
        } catch {
            presentError(message: error.localizedDescription)
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = String(localized: "Sugu Settings")
        panel.allowedContentTypes = [.json]
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated {
                do {
                    try data.write(to: url, options: .atomic)
                } catch {
                    self?.presentError(message: error.localizedDescription)
                }
            }
        }
    }

    private func exportDiagnostics() {
        guard let window = view.window else { return }
        let report: String
        do {
            report = try DiagnosticsReport.make(settings: model.exportSettings())
        } catch {
            presentError(message: error.localizedDescription)
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = String(localized: "Sugu Diagnostics")
        panel.allowedContentTypes = [.plainText]
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated {
                do {
                    try report.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    self?.presentError(message: error.localizedDescription)
                }
            }
        }
    }

    private func importSettings() {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                do {
                    self.apply(try self.model.readSettings(from: url))
                } catch {
                    self.presentError(message: String(localized: "The settings file could not be read."))
                }
            }
        }
    }

    /// Applies imported or default settings. A shorter time to forget
    /// unused words deletes words at once, so it asks first, as the
    /// Learning pane does; declined, the current time stays.
    private func apply(_ settings: Preferences) {
        var settings = settings
        let days = settings.learnedWordExpiryDays
        let current = model.preferences.learnedWordExpiryDays
        guard days != current, model.wordsExpiring(olderThan: days) > 0 else {
            model.preferences = settings
            return
        }
        settings.learnedWordExpiryDays = current
        model.preferences = settings
        confirm(String(localized: "Delete learned words not used in the last \(days) days?"), action: String(localized: "Delete"), destructive: true) { [weak self] in
            self?.model.preferences.learnedWordExpiryDays = days
        }
    }

    private func showNotices() {
        guard let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt") else { return }
        NSWorkspace.shared.open(url)
    }
}
