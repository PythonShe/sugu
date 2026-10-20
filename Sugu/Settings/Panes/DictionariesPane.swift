import AppKit
import UniformTypeIdentifiers

final class DictionariesPane: SettingsPane {
    private var includeLearnedInExport = false

    override func build() {
        let model = model
        form.button(String(localized: "Import…"), label: String(localized: "Import:"), action: { [weak self] in self?.importDictionaries() })

        form.gap()
        form.checkbox(String(localized: "Include learned words"), label: String(localized: "Export:"),
                      get: { [unowned self] in includeLearnedInExport }, set: { [unowned self] in includeLearnedInExport = $0 })
        form.button(String(localized: "Export…"), action: { [weak self] in self?.exportDictionary() })

        form.gap()
        let folder = NSTextField(labelWithString: "")
        folder.lineBreakMode = .byTruncatingMiddle
        folder.textColor = .secondaryLabelColor
        let stop = form.makeButton(String(localized: "Stop Syncing")) { model.setSyncFolder(nil) }
        let choose = form.makeButton(String(localized: "Choose…")) { [weak self] in self?.chooseSyncFolder() }
        let folderRow = NSStackView(views: [choose, stop, folder])
        form.row(String(localized: "Sync folder:"), folderRow)
        let learned = form.checkbox(String(localized: "Include learned words"),
                                    get: { model.preferences.syncLearnedWords }, set: { model.preferences.syncLearnedWords = $0 })
        let status = NSTextField(labelWithString: "")
        status.textColor = .secondaryLabelColor
        let syncNow = form.makeButton(String(localized: "Sync Now")) { model.syncNow() }
        form.row(String(localized: "Last synced:"), NSStackView(views: [status, syncNow]))
        let dates = RelativeDateTimeFormatter()
        form.onRefresh {
            let path = model.preferences.syncFolderPath
            folder.stringValue = path.map { FileManager.default.displayName(atPath: $0) } ?? ""
            stop.isHidden = path == nil
            learned.isEnabled = path != nil
            syncNow.isEnabled = path != nil
            if model.syncFailed {
                status.stringValue = String(localized: "Failed")
                status.textColor = .systemRed
            } else {
                status.stringValue = model.lastSync.map { dates.localizedString(for: $0, relativeTo: Date()) } ?? String(localized: "Never")
                status.textColor = .secondaryLabelColor
            }
        }
    }

    private func importDictionaries() {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                do {
                    let added = try self.model.importDictionaries(panel.urls)
                    let alert = NSAlert()
                    alert.messageText = String(localized: "Added \(added) words.")
                    alert.beginSheetModal(for: window)
                } catch {
                    self.presentError(message: String(localized: "The dictionary could not be read."))
                }
            }
        }
    }

    private func exportDictionary() {
        guard let window = view.window else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = String(localized: "Sugu Dictionary") + ".txt"
        panel.allowedContentTypes = [.plainText]
        let data = model.exportDictionary(includeLearned: includeLearnedInExport)
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

    private func chooseSyncFolder() {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { self?.model.setSyncFolder(url) }
        }
    }
}
