import AppKit
import SuguCore

/// The menu under Sugu's input source in the menu bar.
@MainActor
final class InputMenu {
    private enum Command: Int {
        case chinese = 1, japanese, english
        case reconvert
    }

    private let coordinator: InputCoordinator
    private let preferences: PreferencesStore

    init(coordinator: InputCoordinator, preferences: PreferencesStore) {
        self.coordinator = coordinator
        self.preferences = preferences
    }

    func make() -> NSMenu {
        let menu = NSMenu()
        let enabled = preferences.preferences.enabledModes
        for mode in InputMode.allCases where enabled.contains(mode) || mode == .english {
            let item = Self.item(mode.localizedName, command: Self.command(for: mode))
            item.state = coordinator.mode == mode ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(Self.item(String(localized: "Reconvert Selection"), command: .reconvert))
        return menu
    }

    func perform(_ item: NSMenuItem) {
        switch Command(rawValue: item.tag) {
        case .chinese: coordinator.select(.chinese)
        case .japanese: coordinator.select(.japanese)
        case .english: coordinator.select(.english)
        case .reconvert: coordinator.reconvertSelection()
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
