import AppKit
import SuguCore

/// Briefly shows the new mode next to the caret after a mode change, or
/// another setting a key switched.
@MainActor
final class ModeIndicatorController {
    static let visibleDuration: Duration = .milliseconds(900)

    /// The candidate window's text size, which the label follows.
    var textSize: CGFloat = 16

    private let label = NSTextField(labelWithString: "")
    private let content = BorderedView()
    private lazy var panel: FloatingPanel = {
        label.textColor = .labelColor
        label.alignment = .center
        content.addSubview(label)
        let panel = FloatingPanel(content: content)
        panel.ignoresMouseEvents = true
        return panel
    }()
    private var dismissal: Task<Void, Never>?

    func show(_ mode: InputMode, keyboard: ChineseKeyboard, katakana: Bool, near rect: NSRect) {
        if mode == .japanese, katakana {
            show("ア", named: String(localized: "Katakana"), near: rect)
        } else {
            show(Self.symbol(for: mode, keyboard: keyboard), named: mode.localizedName, near: rect)
        }
    }

    func show(_ symbol: String, named name: String, near rect: NSRect) {
        label.stringValue = symbol
        label.setAccessibilityLabel(name)
        label.font = .systemFont(ofSize: (textSize * 0.95).rounded(), weight: .medium)
        let side = (textSize * 1.9).rounded()
        label.sizeToFit()
        label.frame = NSRect(x: 0, y: (side - label.frame.height) / 2, width: side, height: label.frame.height)
        let anchor = rect == .zero ? NSRect(origin: NSEvent.mouseLocation, size: .zero) : rect
        panel.alphaValue = 1
        panel.place(size: NSSize(width: side, height: side), below: anchor)
        content.needsDisplay = true
        panel.orderFrontRegardless()
        if NSWorkspace.shared.isVoiceOverEnabled {
            NSAccessibility.post(element: label, notification: .announcementRequested, userInfo: [
                .announcement: name,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ])
        }
        dismissal?.cancel()
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: Self.visibleDuration)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    /// Hides the label at once.
    func hide() {
        dismissal?.cancel()
        dismissal = nil
        panel.orderOut(nil)
    }

    private func dismiss() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.panel.alphaValue == 0 else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    static func symbol(for mode: InputMode, keyboard: ChineseKeyboard) -> String {
        switch mode {
        case .chinese: keyboard == .zhuyin ? "ㄅ" : "中"
        case .japanese: "あ"
        case .english: "A"
        }
    }
}

extension InputMode {
    var localizedName: String {
        switch self {
        case .chinese: String(localized: "Chinese")
        case .japanese: String(localized: "Japanese")
        case .english: String(localized: "English")
        }
    }
}

/// The label's backing, outlined with Increase Contrast on.
private final class BorderedView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        FloatingPanel.strokeContrastBorder(in: bounds)
    }
}
