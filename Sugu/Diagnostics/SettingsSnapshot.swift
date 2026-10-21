#if DEBUG
import AppKit
import SuguCore
import SuguDictionaries

/// Renders every settings pane to PNG files without showing a window, in
/// light and dark appearance, for reviewing layout during development, after
/// building the settings window as the menu does (CI runs this):
///   Sugu.app/Contents/MacOS/Sugu --snapshot-settings <dir>
@MainActor
enum SettingsSnapshot {
    static func run(output: URL) {
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
                render(SettingsWindowController.makePane(pane, model: model).view, appearance: appearance, to: output.appendingPathComponent("\(pane)-\(suffix).png"))
            }
            let sheet = ImportSheet(model: model) { _ in }
            render(sheet.window.contentView!, appearance: appearance, to: output.appendingPathComponent("import-empty-\(suffix).png"))
            let loaded = ImportSheet(model: model) { _ in }
            loaded.show([sample])
            render(loaded.window.contentView!, appearance: appearance, to: output.appendingPathComponent("import-\(suffix).png"))
        }
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
