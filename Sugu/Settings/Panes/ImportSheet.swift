import AppKit
import SuguCore
import SuguDictionaries

/// Sheet for importing dictionaries: files dropped on it or chosen, then
/// what they hold, with how many words are new, before anything is added.
@MainActor
final class ImportSheet: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let window: NSWindow
    private let model: SettingsModel
    private let onImport: (Int) -> Void
    private var previews: [DictionaryPreview] = []
    private var entries: [DictionaryEntry] = []
    private var reading: Task<Void, Never>?

    private let content = FileDropView()
    private let well = FileDropView()
    private let details = SettingsForm()
    private let fileName = NSTextField(labelWithString: "")
    private let format = NSTextField(labelWithString: "")
    private let wordCount = NSTextField(labelWithString: "")
    private let newCount = NSTextField(labelWithString: "")
    private let failure = NSTextField(wrappingLabelWithString: "")
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private var importButton: NSButton!

    /// `onImport` gets how many words were new.
    init(model: SettingsModel, onImport: @escaping (Int) -> Void) {
        self.model = model
        self.onImport = onImport
        window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        super.init()

        let icon = NSImageView(image: NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)!)
        icon.symbolConfiguration = .init(pointSize: 32, weight: .light)
        icon.contentTintColor = .secondaryLabelColor
        let prompt = NSTextField(labelWithString: String(localized: "Drop Dictionary Files Here"))
        prompt.textColor = .secondaryLabelColor
        let wellContent = NSStackView(views: [icon, prompt])
        wellContent.orientation = .vertical
        wellContent.spacing = 8
        wellContent.translatesAutoresizingMaskIntoConstraints = false
        well.isWell = true
        well.addSubview(wellContent)
        well.setAccessibilityElement(true)
        well.setAccessibilityRole(.group)
        well.setAccessibilityLabel(prompt.stringValue)
        NSLayoutConstraint.activate([
            wellContent.centerXAnchor.constraint(equalTo: well.centerXAnchor),
            wellContent.centerYAnchor.constraint(equalTo: well.centerYAnchor),
        ])

        fileName.lineBreakMode = .byTruncatingMiddle
        fileName.widthAnchor.constraint(lessThanOrEqualToConstant: 360).isActive = true
        details.row(String(localized: "File:"), fileName)
        details.row(String(localized: "Format:"), format)
        details.row(String(localized: "Words:"), wordCount)
        details.row(String(localized: "New:"), newCount)
        failure.textColor = .systemRed
        failure.isHidden = true

        for (identifier, title, width) in [("text", String(localized: "Word"), 160.0), ("reading", String(localized: "Reading"), 160.0), ("mode", String(localized: "Mode"), 100.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = width
            table.addTableColumn(column)
        }
        table.usesAlternatingRowBackgroundColors = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.style = .fullWidth
        table.allowsMultipleSelection = false
        table.dataSource = self
        table.delegate = self
        table.setAccessibilityLabel(String(localized: "Words"))
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let choose = details.makeButton(String(localized: "Choose Files…")) { [unowned self] in chooseFiles() }
        let cancel = details.makeButton(String(localized: "Cancel")) { [unowned self] in close() }
        cancel.keyEquivalent = "\u{1b}"
        importButton = details.makeButton(String(localized: "Import")) { [unowned self] in importWords() }
        importButton.keyEquivalent = "\r"
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [choose, spacer, cancel, importButton])

        let stack = NSStackView(views: [details.grid, failure, well, scroll, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        content.onDrop = { [unowned self] in read($0) }
        well.onDrop = content.onDrop
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            scroll.widthAnchor.constraint(equalToConstant: 460),
            scroll.heightAnchor.constraint(equalToConstant: 220),
            well.widthAnchor.constraint(equalToConstant: 460),
            well.heightAnchor.constraint(equalToConstant: 220),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor),
            failure.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        window.contentView = content
        show(nil)
        objc_setAssociatedObject(window, &ImportSheet.key, self, .OBJC_ASSOCIATION_RETAIN)
    }

    private nonisolated(unsafe) static var key = 0

    /// Reads `urls` and shows what they hold, in place of what was shown.
    func read(_ urls: [URL]) {
        reading?.cancel()
        importButton.isEnabled = false
        reading = Task {
            do {
                let previews = try await model.previewDictionaries(urls)
                guard !Task.isCancelled else { return }
                show(previews)
            } catch DictionaryImporter.Error.tooLarge {
                show(failure: String(localized: "The dictionary has too many words to import."))
            } catch {
                guard !Task.isCancelled else { return }
                show(failure: String(localized: "The dictionary could not be read."))
            }
        }
    }

    func show(_ previews: [DictionaryPreview]?) {
        self.previews = previews ?? []
        entries = self.previews.flatMap(\.entries)
        let loaded = !entries.isEmpty
        well.isHidden = loaded
        scroll.isHidden = !loaded
        details.grid.isHidden = !loaded
        failure.isHidden = true
        fileName.stringValue = self.previews.map(\.url.lastPathComponent).joined(separator: ", ")
        let formats = Set(self.previews.map(\.format))
        format.stringValue = formats.count == 1 ? formats.first!.localizedName : String(localized: "Several Formats")
        wordCount.stringValue = entries.count.formatted()
        newCount.stringValue = model.newWordCount(in: self.previews).formatted()
        importButton.isEnabled = loaded
        table.reloadData()
        table.scrollRowToVisible(0)
    }

    private func show(failure message: String) {
        show(nil)
        failure.stringValue = message
        failure.isHidden = false
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            let urls = panel.urls
            MainActor.assumeIsolated { self?.read(urls) }
        }
    }

    private func importWords() {
        guard !previews.isEmpty else { return }
        importButton.isEnabled = false
        let previews = previews
        Task {
            do {
                let added = try await model.importDictionaries(previews)
                onImport(added)
                close()
            } catch {
                show(failure: String(localized: "The dictionary could not be read."))
            }
        }
    }

    private func close() {
        reading?.cancel()
        window.sheetParent?.endSheet(window)
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = entries[row]
        switch tableColumn?.identifier.rawValue {
        case "text": return textCell(entry.text, in: tableView)
        case "reading": return textCell(entry.reading, in: tableView, secondary: true)
        case "mode": return textCell(entry.mode.localizedName, in: tableView, secondary: true)
        default: return nil
        }
    }
}

extension DictionaryFormat {
    var localizedName: String {
        switch self {
        case .sugu: String(localized: "Sugu Dictionary")
        case .textReplacements: String(localized: "Text Replacements")
        case .googleJapaneseInput: String(localized: "Google Japanese Input or Microsoft IME")
        case .atok: "ATOK"
        case .sogouCell: String(localized: "Sogou Cell Dictionary")
        case .sogouText: String(localized: "Sogou Text")
        case .rime: "RIME"
        case .wordList: String(localized: "Word List")
        }
    }
}
