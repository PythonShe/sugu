import AppKit
import SuguCore

/// Briefly shows the new mode next to the caret after a mode change.
@MainActor
final class ModeIndicatorController {
    static let visibleDuration: Duration = .milliseconds(900)

    private let label = NSTextField(labelWithString: "")
    private lazy var panel: FloatingPanel = {
        let content = NSView()
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center
        label.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        content.addSubview(label)
        let panel = FloatingPanel(content: content)
        panel.ignoresMouseEvents = true
        return panel
    }()
    private var dismissal: Task<Void, Never>?

    func show(_ mode: InputMode, keyboard: ChineseKeyboard, near rect: NSRect) {
        label.stringValue = Self.symbol(for: mode, keyboard: keyboard)
        label.setAccessibilityLabel(mode.localizedName)
        let side: CGFloat = 30
        label.sizeToFit()
        label.frame = NSRect(x: 0, y: (side - label.frame.height) / 2, width: side, height: label.frame.height)
        let anchor = rect == .zero ? NSRect(origin: NSEvent.mouseLocation, size: .zero) : rect
        panel.alphaValue = 1
        panel.place(size: NSSize(width: side, height: side), below: anchor)
        panel.orderFrontRegardless()
        if NSWorkspace.shared.isVoiceOverEnabled {
            NSAccessibility.post(element: label, notification: .announcementRequested, userInfo: [
                .announcement: mode.localizedName,
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
