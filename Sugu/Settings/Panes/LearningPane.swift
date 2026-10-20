import AppKit
import SuguCore
import SuguInput
import SuguLearning

final class LearningPane: SettingsPane, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let wordsEditor = TableEditor(height: 220, width: 460)
    private let appsEditor = TableEditor(height: 96, width: 460)
    private let search = NSSearchField()
    private var words: [LearnedWord] = []
    private var noLearnApps: [String] = []
    private let dates = RelativeDateTimeFormatter()

    override func build() {
        let model = model
        form.checkbox(String(localized: "Learn from typing"),
                      get: { model.preferences.learningEnabled }, set: { model.preferences.learningEnabled = $0 })
        form.popUp(String(localized: "Forget unused words:"), options: [
            (String(localized: "After 30 Days"), 30),
            (String(localized: "After 90 Days"), 90),
            (String(localized: "After 180 Days"), 180),
            (String(localized: "After a Year"), 365),
            (String(localized: "Never"), 0),
        ], get: { model.preferences.learnedWordExpiryDays }, set: { model.preferences.learnedWordExpiryDays = $0 })

        form.gap()
        search.placeholderString = String(localized: "Search")
        search.delegate = self
        search.widthAnchor.constraint(equalToConstant: 460).isActive = true
        let wordsLabel = String(localized: "Words:")
        form.row(wordsLabel, search)

        let table = wordsEditor.table
        wordsEditor.addColumn("text", title: String(localized: "Word"), width: 100, sortKey: "text")
        wordsEditor.addColumn("reading", title: String(localized: "Reading"), width: 90, sortKey: "reading")
        wordsEditor.addColumn("mode", title: String(localized: "Mode"), width: 64, sortKey: "mode")
        wordsEditor.addColumn("count", title: String(localized: "Uses"), width: 36, sortKey: "count")
        wordsEditor.addColumn("lastUsed", title: String(localized: "Last Used"), width: 76, sortKey: "lastUsed")
        wordsEditor.addColumn("pinned", title: String(localized: "Pinned"), width: 40, sortKey: "pinned")
        table.sortDescriptors = [NSSortDescriptor(key: "lastUsed", ascending: false)]
        table.dataSource = self
        table.delegate = self
        wordsEditor.onAdd = { [weak self] in self?.addWord() }
        wordsEditor.onRemove = { [weak self] in self?.deleteSelectedWords() }
        form.row(nil, wordsEditor)
        wordsEditor.setAccessibilityLabel(SettingsForm.name(wordsLabel))

        let forget = form.makeButton(String(localized: "Forget Last Hour…")) { [weak self] in
            self?.confirm(String(localized: "Forget the words learned in the last hour?"), action: String(localized: "Forget"), destructive: true) {
                model.forgetLastHour()
            }
        }
        let deleteAll = form.makeButton(String(localized: "Delete All…")) { [weak self] in
            self?.confirm(String(localized: "Delete all learned and added words?"), action: String(localized: "Delete All"), destructive: true) {
                model.deleteAllWords()
            }
        }
        form.row(nil, NSStackView(views: [forget, deleteAll]))

        form.gap()
        appsEditor.addColumn("app", title: String(localized: "App"), width: 440)
        appsEditor.table.headerView = nil
        appsEditor.table.dataSource = self
        appsEditor.table.delegate = self
        appsEditor.onAdd = { [weak self] in
            AppInfo.choose(in: self?.view.window) { bundleIDs in
                for bundleID in bundleIDs where !model.preferences.noLearnApps.contains(bundleID) {
                    model.preferences.noLearnApps.append(bundleID)
                }
            }
        }
        appsEditor.onRemove = { [weak self] in
            guard let self else { return }
            let selected = appsEditor.table.selectedRowIndexes.compactMap { self.noLearnApps.indices.contains($0) ? self.noLearnApps[$0] : nil }
            model.preferences.noLearnApps.removeAll { selected.contains($0) }
        }
        form.row(String(localized: "Never learn in:"), appsEditor)

        if !model.hasStore {
            wordsEditor.setEnabled(false)
            search.isEnabled = false
            forget.isEnabled = false
            deleteAll.isEnabled = false
        }
        reloadWords()
        reloadApps()
    }

    override func modelDidChange(_ change: SettingsModel.Change) {
        switch change {
        case .words: reloadWords()
        case .preferences where model.preferences.noLearnApps != noLearnApps: reloadApps()
        default: break
        }
    }

    // MARK: Words

    private func reloadWords() {
        let query = search.stringValue.trimmingCharacters(in: .whitespaces)
        var visible = query.isEmpty ? model.words : model.words.filter {
            $0.text.localizedCaseInsensitiveContains(query) || $0.reading.localizedCaseInsensitiveContains(query) || $0.shownReading.contains(query)
        }
        if let sort = wordsEditor.table.sortDescriptors.first, let key = sort.key {
            func less(_ lhs: LearnedWord, _ rhs: LearnedWord) -> Bool {
                switch key {
                case "text": lhs.text.localizedStandardCompare(rhs.text) == .orderedAscending
                case "reading": lhs.reading < rhs.reading
                case "mode": lhs.mode.rawValue < rhs.mode.rawValue
                case "count": lhs.count < rhs.count
                case "pinned": !lhs.pinned && rhs.pinned
                default: lhs.lastUsed < rhs.lastUsed
                }
            }
            visible.sort { sort.ascending ? less($0, $1) : less($1, $0) }
        }
        let selected = Set(wordsEditor.table.selectedRowIndexes.compactMap { words.indices.contains($0) ? words[$0].id : nil })
        words = visible
        wordsEditor.table.reloadData()
        wordsEditor.table.selectRowIndexes(IndexSet(words.indices.filter { selected.contains(words[$0].id) }), byExtendingSelection: false)
        updateButtons()
    }

    func controlTextDidChange(_ notification: Notification) {
        reloadWords()
    }

    private func deleteSelectedWords() {
        let ids = wordsEditor.table.selectedRowIndexes.compactMap { words.indices.contains($0) ? words[$0].id : nil }
        model.delete(Set(ids))
    }

    private func addWord() {
        guard let window = view.window else { return }
        let sheet = AddWordSheet(model: model)
        window.beginSheet(sheet.window)
    }

    // MARK: No-learn apps

    private func reloadApps() {
        noLearnApps = model.preferences.noLearnApps
        appsEditor.table.reloadData()
        updateButtons()
    }

    private func updateButtons() {
        wordsEditor.setRemoveEnabled(!wordsEditor.table.selectedRowIndexes.isEmpty)
        appsEditor.setRemoveEnabled(!appsEditor.table.selectedRowIndexes.isEmpty)
    }

    // MARK: Tables

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === wordsEditor.table ? words.count : noLearnApps.count
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtons()
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        reloadWords()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard tableView === wordsEditor.table else {
            return AppInfo.cell(for: noLearnApps[row], in: tableView)
        }
        let word = words[row]
        switch tableColumn?.identifier.rawValue {
        case "text": return textCell(word.text, in: tableView)
        case "reading": return textCell(word.shownReading, in: tableView, secondary: true)
        case "mode": return textCell(word.mode.localizedName, in: tableView, secondary: true)
        case "count": return textCell(word.count.formatted(), in: tableView, secondary: true)
        case "lastUsed": return textCell(dates.localizedString(for: word.lastUsed, relativeTo: Date()), in: tableView, secondary: true)
        case "pinned":
            let box = NSButton(checkboxWithTitle: "", target: nil, action: nil)
            box.state = word.pinned ? .on : .off
            box.setAccessibilityLabel(String(localized: "Pinned"))
            form.bind(box) { [weak self] control in
                self?.model.setPinned((control as? NSButton)?.state == .on, for: word)
            }
            return box
        default: return nil
        }
    }
}

/// Sheet for adding a word by hand, perhaps filled from a selection.
@MainActor
final class AddWordSheet: NSObject {
    let window: NSWindow
    private let model: SettingsModel
    private let form = SettingsForm()
    private var mode = InputMode.chinese
    private var reading = ""
    private var text = ""
    private var addButton: NSButton!

    init(model: SettingsModel, draft: WordDraft? = nil) {
        self.model = model
        if let draft {
            mode = draft.mode == .japanese ? .japanese : .chinese
            reading = draft.reading
            text = draft.text
        }
        window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        super.init()
        form.segmented(String(localized: "Language:"), options: [
            (String(localized: "Chinese"), InputMode.chinese),
            (String(localized: "Japanese"), InputMode.japanese),
        ], get: { [unowned self] in mode }, set: { [unowned self] in mode = $0 })
        let readingField = form.textField(String(localized: "Reading:"), get: { [unowned self] in reading }, set: { [unowned self] in reading = $0; validate() })
        let textField = form.textField(String(localized: "Word:"), get: { [unowned self] in text }, set: { [unowned self] in text = $0; validate() })
        readingField.delegate = self
        textField.delegate = self

        let cancel = form.makeButton(String(localized: "Cancel")) { [unowned self] in close() }
        cancel.keyEquivalent = "\u{1b}"
        addButton = form.makeButton(String(localized: "Add")) { [unowned self] in add() }
        addButton.keyEquivalent = "\r"
        validate()
        let buttons = NSStackView(views: [cancel, addButton])
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(form.grid)
        content.addSubview(buttons)
        NSLayoutConstraint.activate([
            form.grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            form.grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            form.grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            buttons.topAnchor.constraint(equalTo: form.grid.bottomAnchor, constant: 20),
            buttons.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 20),
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
        ])
        window.contentView = content
        // The field still to fill, the reading when unsure.
        window.initialFirstResponder = reading.isEmpty || text.isEmpty ? readingField : textField
        objc_setAssociatedObject(window, &AddWordSheet.key, self, .OBJC_ASSOCIATION_RETAIN)
    }

    private nonisolated(unsafe) static var key = 0

    private func validate() {
        addButton.isEnabled = !reading.trimmingCharacters(in: .whitespaces).isEmpty && !text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Adds the word and closes, or says it could not be added and stays
    /// open for a correction.
    private func add() {
        guard model.addWord(reading: reading, text: text, mode: mode) else {
            let alert = NSAlert()
            alert.messageText = String(localized: "The word could not be added.")
            alert.alertStyle = .warning
            alert.beginSheetModal(for: window)
            return
        }
        close()
    }

    private func close() {
        window.sheetParent?.endSheet(window)
        // The window kept the sheet alive while it showed.
        objc_setAssociatedObject(window, &Self.key, nil, .OBJC_ASSOCIATION_RETAIN)
    }
}

extension AddWordSheet: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        // Text fields send their action only on Return; track every edit.
        field.sendAction(field.action, to: field.target)
    }
}

extension LearnedWord {
    /// The reading as typed; a Zhuyin word's in Bopomofo, not its codes.
    var shownReading: String {
        guard mode == .chinese, let syllables = Zhuyin.syllables(ofCodes: reading) else { return reading }
        return syllables.map(\.text).joined(separator: " ")
    }
}
