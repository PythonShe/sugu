import AppKit
import SuguCore

final class AppsPane: SettingsPane, NSTableViewDataSource, NSTableViewDelegate {
    private let editor = TableEditor(height: 200, width: 460)
    private var apps: [String] = []
    private let modes: [InputMode?] = [nil, .chinese, .japanese, .english]

    override func build() {
        let model = model
        form.checkbox(String(localized: "Remember the mode for each app"),
                      get: { model.preferences.rememberModePerApp }, set: { model.preferences.rememberModePerApp = $0 })
        form.gap()
        editor.addColumn("app", title: String(localized: "App"), width: 200)
        editor.addColumn("mode", title: String(localized: "Mode"), width: 130)
        editor.addColumn("escape", title: String(localized: "Esc to English"), width: 100)
        editor.table.dataSource = self
        editor.table.delegate = self
        editor.onAdd = { [weak self] in self?.addApps() }
        editor.onRemove = { [weak self] in self?.removeSelected() }
        form.row(String(localized: "App rules:"), editor)
        reload()
    }

    override func modelDidChange(_ change: SettingsModel.Change) {
        if change == .preferences, model.preferences.appRules.keys.sorted() != apps { reload() }
    }

    private func reload() {
        apps = model.preferences.appRules.keys.sorted { AppInfo.name(for: $0).localizedStandardCompare(AppInfo.name(for: $1)) == .orderedAscending }
        editor.table.reloadData()
        editor.setRemoveEnabled(!editor.table.selectedRowIndexes.isEmpty)
    }

    private func addApps() {
        for bundleID in AppInfo.choose() where model.preferences.appRules[bundleID] == nil {
            model.preferences.appRules[bundleID] = AppRule()
        }
        reload()
    }

    private func removeSelected() {
        for row in editor.table.selectedRowIndexes where apps.indices.contains(row) {
            model.preferences.appRules[apps[row]] = nil
        }
        reload()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { apps.count }

    func tableViewSelectionDidChange(_ notification: Notification) {
        editor.setRemoveEnabled(!editor.table.selectedRowIndexes.isEmpty)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let bundleID = apps[row]
        let rule = model.preferences.appRules[bundleID] ?? AppRule()
        switch tableColumn?.identifier.rawValue {
        case "app":
            return AppInfo.cell(for: bundleID, in: tableView)
        case "mode":
            let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
            popUp.controlSize = .small
            popUp.isBordered = false
            popUp.addItems(withTitles: modes.map { $0?.localizedName ?? String(localized: "Automatic") })
            popUp.selectItem(at: modes.firstIndex(of: rule.defaultMode) ?? 0)
            form.bind(popUp) { [weak self] control in
                guard let self, let index = (control as? NSPopUpButton)?.indexOfSelectedItem else { return }
                model.preferences.appRules[bundleID]?.defaultMode = modes[index]
            }
            return popUp
        case "escape":
            let box = NSButton(checkboxWithTitle: "", target: nil, action: nil)
            box.state = rule.escapeSwitchesToEnglish ? .on : .off
            box.setAccessibilityLabel(String(localized: "Esc to English"))
            form.bind(box) { [weak self] control in
                self?.model.preferences.appRules[bundleID]?.escapeSwitchesToEnglish = (control as? NSButton)?.state == .on
            }
            return box
        default:
            return nil
        }
    }
}
