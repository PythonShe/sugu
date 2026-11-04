#if DEBUG
import AppKit
import SuguCore
import SuguDictionaries

/// Renders every settings pane to PNG files without showing a window, in
/// light and dark appearance, for reviewing layout during development, after
/// building the settings window as the menu does. CI runs this, and it fails
/// when a pane is wider than the others, which would reshape the window, or
/// opens with the keyboard in a text field:
///   Sugu.app/Contents/MacOS/Sugu --snapshot-settings <dir>
@MainActor
enum SettingsSnapshot {
    static func run(output: URL) -> Bool {
        var fits = true
        _ = NSApplication.shared
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let model = SettingsModel(environment: .shared)
        // The tab controller builds the window's toolbar from the panes.
        SettingsWindowController(model: model).window?.contentView?.layoutSubtreeIfNeeded()
        let sample = DictionaryPreview(url: URL(fileURLWithPath: "/tmp/words.csv"), format: .wordList, entries: [
            DictionaryEntry(mode: .chinese, reading: "sugu", text: "苏古"),
            DictionaryEntry(mode: .japanese, reading: "とうきょう", text: "東京"),
        ])
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            for pane in SettingsWindowController.Pane.available {
                let view = SettingsWindowController.makePane(pane, model: model).view
                if view.fittingSize.width > SettingsPane.width {
                    print("\(pane) is \(view.fittingSize.width) wide, over \(SettingsPane.width)")
                    fits = false
                }
                if appearance == .aqua, !opensUnfocused(pane, model: model) {
                    print("\(pane) opens with the keyboard in a text field")
                    fits = false
                }
                render(view, appearance: appearance, to: output.appendingPathComponent("\(pane)-\(suffix).png"))
            }
            let sheet = ImportSheet(model: model) { _ in }
            render(sheet.window.contentView!, appearance: appearance, to: output.appendingPathComponent("import-empty-\(suffix).png"))
            let loaded = ImportSheet(model: model) { _ in }
            loaded.show([sample])
            render(loaded.window.contentView!, appearance: appearance, to: output.appendingPathComponent("import-\(suffix).png"))
        }
        return fits
    }

    /// Never through the settings window, whose saved frame and pane are the
    /// installed Sugu's too: a debug build shares its user defaults.
    private static func opensUnfocused(_ pane: SettingsWindowController.Pane, model: SettingsModel) -> Bool {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.contentViewController = SettingsWindowController.makePane(pane, model: model)
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        return !(window.firstResponder is NSText)
    }

    private static func render(_ view: NSView, appearance: NSAppearance.Name, to url: URL) {
        view.appearance = NSAppearance(named: appearance)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: view.fittingSize), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        window.setContentSize(view.fittingSize)
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        // The view draws no background of its own; the window does.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            view.bounds.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
