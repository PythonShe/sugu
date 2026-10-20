import AppKit

/// The menu bar Sugu never shows (it runs as an agent), present so its
/// windows take the standard key equivalents: ⌘W closes, and text fields
/// undo, cut, copy, paste and select all, and ⌘M minimizes. No Quit: the system runs the
/// input method, and ⌘Q in Settings would end typing in every app.
@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(submenu(String(localized: "File"), items: [
            item(String(localized: "Close"), #selector(NSWindow.performClose(_:)), "w"),
        ]))
        menu.addItem(submenu(String(localized: "Edit"), items: [
            item(String(localized: "Undo"), Selector(("undo:")), "z"),
            item(String(localized: "Redo"), Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item(String(localized: "Cut"), #selector(NSText.cut(_:)), "x"),
            item(String(localized: "Copy"), #selector(NSText.copy(_:)), "c"),
            item(String(localized: "Paste"), #selector(NSText.paste(_:)), "v"),
            item(String(localized: "Select All"), #selector(NSText.selectAll(_:)), "a"),
        ]))
        let window = submenu(String(localized: "Window"), items: [
            item(String(localized: "Minimize"), #selector(NSWindow.performMiniaturize(_:)), "m"),
        ])
        menu.addItem(window)
        NSApp.windowsMenu = window.submenu
        return menu
    }

    private static func submenu(_ title: String, items: [NSMenuItem]) -> NSMenuItem {
        let submenu = NSMenu(title: title)
        items.forEach(submenu.addItem)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private static func item(_ title: String, _ action: Selector, _ key: String, _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }
}
