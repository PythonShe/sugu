#if DEBUG
import AppKit

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
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for pane in SettingsWindowController.Pane.available {
                let controller = SettingsWindowController.makePane(pane, model: model)
                let view = controller.view
                view.appearance = NSAppearance(named: appearance)
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: view.fittingSize), styleMask: [.titled], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: appearance)
                window.contentView = view
                view.layoutSubtreeIfNeeded()
                let size = view.fittingSize
                window.setContentSize(size)
                view.layoutSubtreeIfNeeded()
                guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                // The view draws no background of its own; the window does.
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
                    NSColor.windowBackgroundColor.setFill()
                    view.bounds.fill()
                }
                NSGraphicsContext.restoreGraphicsState()
                view.cacheDisplay(in: view.bounds, to: rep)
                let name = "\(pane)-\(appearance == .aqua ? "light" : "dark").png"
                try? rep.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent(name))
            }
        }
    }
}
#endif
