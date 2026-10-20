import AppKit
import UniformTypeIdentifiers

final class AdvancedPane: SettingsPane {
    override func build() {
        let model = model
        let importButton = form.makeButton(String(localized: "Import…")) { [weak self] in self?.importSettings() }
        let exportButton = form.makeButton(String(localized: "Export…")) { [weak self] in self?.exportSettings() }
        form.row(String(localized: "Settings file:"), NSStackView(views: [importButton, exportButton]))
        form.button(String(localized: "Reset…"), label: String(localized: "Default settings:")) { [weak self] in
            self?.confirm(String(localized: "Reset all settings to their defaults?"), action: String(localized: "Reset"), destructive: true) {
                model.resetSettings()
            }
        }

        form.gap()
        form.button(String(localized: "Show in Finder"), label: String(localized: "Data folder:")) { model.showDataFolder() }

        form.gap()
        let automatic = form.checkbox(String(localized: "Check for updates automatically"), label: String(localized: "Updates:"),
                                      get: { model.checksForUpdatesAutomatically }, set: { model.checksForUpdatesAutomatically = $0 })
        let checkNow = form.button(String(localized: "Check Now")) { model.checkForUpdates() }
        automatic.isEnabled = model.updatesAvailable
        checkNow.isEnabled = model.updatesAvailable

        form.gap()
        form.row(String(localized: "Version:"), NSTextField(labelWithString: model.version))
        let link = NSTextField(labelWithAttributedString: NSAttributedString(string: "github.com/PythonShe/sugu", attributes: [
            .link: URL(string: "https://github.com/PythonShe/sugu")!,
        ]))
        link.isSelectable = true
        link.allowsEditingTextAttributes = true
        form.row(String(localized: "Source code:"), link)
        form.button(String(localized: "Show…"), label: String(localized: "Acknowledgements:")) { [weak self] in self?.showNotices() }
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
        panel.nameFieldStringValue = String(localized: "Sugu Settings") + ".json"
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

    private func importSettings() {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated {
                do {
                    try self?.model.importSettings(from: url)
                } catch {
                    self?.presentError(message: String(localized: "The settings file could not be read."))
                }
            }
        }
    }

    private func showNotices() {
        guard let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt") else { return }
        NSWorkspace.shared.open(url)
    }
}
