import AppKit
import SuguCore

/// The menu under Sugu's input source in the menu bar.
@MainActor
final class InputMenu {
    private enum Command: Int {
        case chinese = 1, japanese, english
        case reconvert
        case learning
        case learnedWords
        case settings
        case checkForUpdates
    }

    /// Tags of the Chinese Characters items, one per script.
    private static let scriptTags = 100

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
            let item = Self.item(mode.localizedName, command: Self.command(for: mode))
            item.state = coordinator.mode == mode ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        if enabled.contains(.chinese) { menu.addItem(scriptMenu()) }
        menu.addItem(Self.item(String(localized: "Reconvert Selection"), command: .reconvert))
        menu.addItem(.separator())
        let learning = Self.item(String(localized: "Learn from Typing"), command: .learning)
        learning.state = preferences.preferences.learningEnabled ? .on : .off
        menu.addItem(learning)
        menu.addItem(Self.item(String(localized: "Learned Words…"), command: .learnedWords))
        menu.addItem(.separator())
        if AppEnvironment.shared.updater.isAvailable {
            menu.addItem(Self.item(String(localized: "Check for Updates…"), command: .checkForUpdates))
        }
        menu.addItem(Self.item(String(localized: "Settings…"), command: .settings))
        return menu
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
        let scripts = ChineseScript.allCases
        if scripts.indices.contains(item.tag - Self.scriptTags) {
            let script = scripts[item.tag - Self.scriptTags]
            preferences.update { $0.chineseScript = script }
            return
        }
        switch Command(rawValue: item.tag) {
        case .chinese: coordinator.select(.chinese)
        case .japanese: coordinator.select(.japanese)
        case .english: coordinator.select(.english)
        case .reconvert: coordinator.reconvertSelection()
        case .learning: preferences.update { $0.learningEnabled.toggle() }
        case .learnedWords: AppEnvironment.shared.showSettings(.learning)
        case .settings: AppEnvironment.shared.showSettings()
        case .checkForUpdates: AppEnvironment.shared.updater.checkForUpdates()
        case nil: break
        }
    }

    private static func command(for mode: InputMode) -> Command {
        switch mode {
        case .chinese: .chinese
        case .japanese: .japanese
        case .english: .english
        }
    }

    private static func item(_ title: String, command: Command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(SuguInputController.performMenuAction(_:)), keyEquivalent: "")
        item.tag = command.rawValue
        return item
    }
}
