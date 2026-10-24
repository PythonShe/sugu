import AppKit
import SuguCore

/// The menu under Sugu's input source in the menu bar.
@MainActor
final class InputMenu {
    private enum Command: Int {
        case chinese = 1, english = 3
        case reconvert
        case learning
        case learnedWords
        case addWord
        case settings
        case checkForUpdates
        case hiragana, katakana
    }

    /// Tags of the Chinese Characters items, one per script.
    private static let scriptTags = 100
    /// Tags of the Translate and Rewrite Selection items.
    private static let translateTags = 200
    private static let rewriteTags = 300

    private let coordinator: InputCoordinator
    private let preferences: PreferencesStore

    init(coordinator: InputCoordinator, preferences: PreferencesStore) {
        self.coordinator = coordinator
        self.preferences = preferences
    }

    func make() -> NSMenu {
        let menu = NSMenu()
        let enabled = preferences.preferences.enabledModes
        for mode in enabled.filter({ $0 != .english }) + [.english] {
            // The system's input menu drops indentation, so Japanese is listed as its two kana, as Apple's Japanese input does.
            guard mode != .japanese else {
                for katakana in [false, true] {
                    let kana = Self.item(katakana ? String(localized: "Katakana") : String(localized: "Hiragana"), command: katakana ? .katakana : .hiragana)
                    kana.keyEquivalent = katakana ? "k" : "j"
                    kana.keyEquivalentModifierMask = [.control, .shift]
                    kana.state = coordinator.mode == .japanese && coordinator.typesKatakana == katakana ? .on : .off
                    menu.addItem(kana)
                }
                continue
            }
            let item = Self.item(mode.localizedName, command: mode == .chinese ? .chinese : .english)
            item.state = coordinator.mode == mode ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        if enabled.contains(.chinese) { menu.addItem(scriptMenu()) }
        menu.addItem(Self.item(String(localized: "Reconvert Selection"), command: .reconvert))
        if coordinator.canReviseSelection {
            menu.addItem(Self.submenu(String(localized: "Translate Selection"), titles: AssistLanguage.allCases.map(\.title), tags: Self.translateTags))
            menu.addItem(Self.submenu(String(localized: "Rewrite Selection"), titles: RewriteStyle.allCases.map(\.title), tags: Self.rewriteTags))
        }
        menu.addItem(.separator())
        let learning = Self.item(String(localized: "Learn from Typing"), command: .learning)
        learning.state = preferences.preferences.learningEnabled ? .on : .off
        menu.addItem(learning)
        menu.addItem(Self.item(String(localized: "Learned Words…"), command: .learnedWords))
        menu.addItem(Self.item(String(localized: "Add Word…"), command: .addWord))
        menu.addItem(.separator())
        let updater = AppEnvironment.shared.updater
        if updater.isAvailable {
            let title = updater.hasPendingUpdate ? String(localized: "Update Available…") : String(localized: "Check for Updates…")
            menu.addItem(Self.item(title, command: .checkForUpdates))
        }
        menu.addItem(Self.item(String(localized: "Settings…"), command: .settings))
        return menu
    }

    private static func submenu(_ title: String, titles: [String], tags: Int) -> NSMenuItem {
        let submenu = NSMenu()
        for (index, title) in titles.enumerated() {
            let item = NSMenuItem(title: title, action: #selector(SuguInputController.performMenuAction(_:)), keyEquivalent: "")
            item.tag = tags + index
            submenu.addItem(item)
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func scriptMenu() -> NSMenuItem {
        let submenu = NSMenu()
        let current = preferences.preferences.chineseScript
        for (index, script) in ChineseScript.allCases.enumerated() {
            let item = NSMenuItem(title: script.title, action: #selector(SuguInputController.performMenuAction(_:)), keyEquivalent: "")
            item.tag = Self.scriptTags + index
            item.state = script == current ? .on : .off
            submenu.addItem(item)
        }
        let item = NSMenuItem(title: String(localized: "Chinese Characters"), action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    func perform(_ item: NSMenuItem) {
        let languages = AssistLanguage.allCases, styles = RewriteStyle.allCases
        if languages.indices.contains(item.tag - Self.translateTags) {
            coordinator.revise(selectionWith: .translate(to: languages[item.tag - Self.translateTags]))
            return
        }
        if styles.indices.contains(item.tag - Self.rewriteTags) {
            coordinator.revise(selectionWith: .rewrite(styles[item.tag - Self.rewriteTags]))
            return
        }
        let scripts = ChineseScript.allCases
        if scripts.indices.contains(item.tag - Self.scriptTags) {
            let script = scripts[item.tag - Self.scriptTags]
            preferences.update { $0.chineseScript = script }
            return
        }
        switch Command(rawValue: item.tag) {
        case .chinese: coordinator.select(.chinese)
        case .english: coordinator.select(.english)
        case .hiragana: coordinator.setKatakana(false)
        case .katakana: coordinator.setKatakana(true)
        case .reconvert: coordinator.reconvertSelection()
        case .learning: preferences.update { $0.learningEnabled.toggle() }
        case .learnedWords: AppEnvironment.shared.showSettings(.learning)
        case .addWord: coordinator.addWord()
        case .settings: AppEnvironment.shared.showSettings()
        case .checkForUpdates: AppEnvironment.shared.updater.checkForUpdates()
        case nil: break
        }
    }

    private static func item(_ title: String, command: Command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(SuguInputController.performMenuAction(_:)), keyEquivalent: "")
        item.tag = command.rawValue
        return item
    }
}

extension AssistLanguage {
    var title: String {
        switch self {
        case .chinese: String(localized: "Chinese")
        case .japanese: String(localized: "Japanese")
        case .english: String(localized: "English")
        }
    }
}

extension RewriteStyle {
    var title: String {
        switch self {
        case .fixGrammar: String(localized: "Fix Grammar")
        case .formal: String(localized: "More Formal")
        case .casual: String(localized: "More Casual")
        case .shorter: String(localized: "Shorter")
        }
    }
}
