import AppKit
import SuguInput

/// The settings window: a toolbar of panes, each a grid of native controls.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    /// The raw values name the panes' toolbar items, which must be strings.
    enum Pane: String, CaseIterable {
        case general, chinese, japanese, apps, learning, dictionaries, languageModel, advanced

        /// The panes this Mac shows: language models need macOS 27.
        static var available: [Pane] {
            if #available(macOS 27.0, *) { return allCases }
            return allCases.filter { $0 != .languageModel }
        }
    }

    private let tabs = SettingsTabs()
    private let model: SettingsModel
    /// Called once the window has closed, to release the controller and
    /// its panes; the pane shown and the frame are kept in user defaults.
    var onClose: (() -> Void)?

    init(model: SettingsModel) {
        self.model = model
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .preference
        super.init(window: window)

        tabs.tabStyle = .toolbar
        tabs.canPropagateSelectedChildViewControllerTitle = true
        for pane in Pane.available {
            let item = NSTabViewItem(viewController: Self.makePane(pane, model: model))
            item.identifier = pane.rawValue
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
            tabs.addTabViewItem(item)
        }
        if let saved = UserDefaults.standard.string(forKey: SettingsTabs.paneKey),
           let index = tabs.tabViewItems.firstIndex(where: { $0.identifier as? String == saved }) {
            tabs.selectedTabViewItemIndex = index
        }
        tabs.remembersPane = true
        window.contentViewController = tabs
        window.center()
        window.setFrameAutosaveName("Settings")
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    static func makePane(_ pane: Pane, model: SettingsModel) -> NSViewController {
        let controller: SettingsPane = switch pane {
        case .general: GeneralPane(model: model)
        case .chinese: ChinesePane(model: model)
        case .japanese: JapanesePane(model: model)
        case .apps: AppsPane(model: model)
        case .learning: LearningPane(model: model)
        case .dictionaries: DictionariesPane(model: model)
        case .languageModel:
            if #available(macOS 27.0, *) { LanguageModelPane(model: model) } else { AdvancedPane(model: model) }
        case .advanced: AdvancedPane(model: model)
        }
        controller.title = pane.title
        return controller
    }

    func show(_ pane: Pane?) {
        if let pane, let index = tabs.tabViewItems.firstIndex(where: { $0.identifier as? String == pane.rawValue }) {
            tabs.selectedTabViewItemIndex = index
        }
        model.isVisible = true
        // The app being typed in never yields activation to an input method,
        // so the window comes forward on its own rather than behind it.
        NSApp.activate()
        window?.orderFrontRegardless()
        window?.makeKey()
    }

    /// Shows the Learning pane with the Add Word sheet, filled from `draft`.
    func addWord(_ draft: WordDraft) {
        show(.learning)
        guard let window, window.attachedSheet == nil else { return }
        window.beginSheet(AddWordSheet(model: model, draft: draft).window)
    }

    func windowWillClose(_ notification: Notification) {
        model.isVisible = false
        // After this callback returns: it runs on the controller.
        Task { [weak self] in self?.onClose?() }
    }
}

/// The panes' tab controller, which reopens on the pane last shown.
private final class SettingsTabs: NSTabViewController {
    static let paneKey = "SettingsPane"
    /// Off while the panes are added, which selects the first.
    var remembersPane = false

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        guard remembersPane, let pane = tabViewItem?.identifier as? String else { return }
        UserDefaults.standard.set(pane, forKey: Self.paneKey)
    }
}

extension SettingsWindowController.Pane {
    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .chinese: String(localized: "Chinese")
        case .japanese: String(localized: "Japanese")
        case .apps: String(localized: "Apps")
        case .learning: String(localized: "Learning")
        case .dictionaries: String(localized: "Dictionaries")
        case .languageModel: String(localized: "Language Model")
        case .advanced: String(localized: "Advanced")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .chinese: "character.textbox.zh"
        case .japanese: "character.textbox.ja"
        case .apps: "square.grid.2x2"
        case .learning: "brain"
        case .dictionaries: "books.vertical"
        case .languageModel: "sparkles"
        case .advanced: "gearshape.2"
        }
    }
}
