import AppKit

/// The settings window: a toolbar of panes, each a grid of native controls.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    enum Pane: Int, CaseIterable {
        case general, chinese, japanese, apps, learning, dictionaries, languageModel, advanced

        /// The panes this Mac shows: language models need macOS 27.
        static var available: [Pane] {
            if #available(macOS 27.0, *) { return allCases }
            return allCases.filter { $0 != .languageModel }
        }
    }

    private let tabs = NSTabViewController()
    private let model: SettingsModel

    init(model: SettingsModel) {
        self.model = model
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
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
        if let pane, let index = tabs.tabViewItems.firstIndex(where: { $0.identifier as? Int == pane.rawValue }) {
            tabs.selectedTabViewItemIndex = index
        }
        model.isVisible = true
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model.isVisible = false
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
