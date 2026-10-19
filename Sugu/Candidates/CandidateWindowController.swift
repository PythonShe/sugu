import AppKit
import SuguCore
import SuguInput

/// Shows the candidate page near the composition, optionally only after a
/// pause in typing, and announces the highlighted candidate to VoiceOver.
@MainActor
final class CandidateWindowController {
    /// Typing pause before the window appears when pause gating is on.
    static let pauseDelay: Duration = .milliseconds(450)

    var onSelect: ((Int) -> Void)?
    var onTurnPage: ((Int) -> Void)?

    private let view = CandidateView()
    private lazy var panel = FloatingPanel(content: view)
    /// The last anchor the host reported correctly, for hosts that report
    /// an empty or off-screen rectangle mid-composition.
    private var lastAnchor: NSRect?
    private var pending: Task<Void, Never>?
    private var announced: String?

    init() {
        view.setAccessibilityLabel(String(localized: "Candidates"))
        view.onSelect = { [unowned self] row in onSelect?(row) }
        view.onTurnPage = { [unowned self] delta in onTurnPage?(delta) }
    }

    var isVisible: Bool { panel.isVisible }

    func show(_ presentation: CandidatePresentation, mode: InputMode, near rect: NSRect, preferences: Preferences) {
        pending?.cancel()
        pending = nil
        let anchor = resolve(rect)
        let style = CandidateView.Style(layout: preferences.candidateLayout, fontSize: preferences.candidateFontSize)
        let gated = preferences.pauseGatedWindow && presentation.highlightedIndex == nil && !panel.isVisible
        if gated {
            pending = Task { [weak self] in
                try? await Task.sleep(for: Self.pauseDelay)
                guard !Task.isCancelled else { return }
                self?.present(presentation, style: style, anchor: anchor)
            }
        } else {
            present(presentation, style: style, anchor: anchor)
        }
    }

    func hide() {
        pending?.cancel()
        pending = nil
        announced = nil
        if panel.isVisible { panel.orderOut(nil) }
    }

    private func present(_ presentation: CandidatePresentation, style: CandidateView.Style, anchor: NSRect) {
        let size = view.update(presentation, style: style)
        panel.place(size: size, below: anchor, leadingInset: 5)
        if !panel.isVisible { panel.orderFrontRegardless() }
        announce(presentation)
    }

    private func resolve(_ rect: NSRect) -> NSRect {
        let onScreen = NSScreen.screens.contains { $0.frame.intersects(rect.insetBy(dx: -1, dy: -1)) }
        if rect != .zero, onScreen {
            lastAnchor = rect
            return rect
        }
        if let lastAnchor { return lastAnchor }
        let mouse = NSEvent.mouseLocation
        return NSRect(x: mouse.x, y: mouse.y, width: 0, height: 0)
    }

    private func announce(_ presentation: CandidatePresentation) {
        guard NSWorkspace.shared.isVoiceOverEnabled else { return }
        let index = presentation.highlightedIndex ?? 0
        guard presentation.candidates.indices.contains(index) else { return }
        let candidate = presentation.candidates[index]
        let text = [presentation.labels[index], candidate.text, candidate.annotation].compactMap { $0 }.joined(separator: " ")
        guard text != announced else { return }
        announced = text
        NSAccessibility.post(element: view, notification: .announcementRequested, userInfo: [
            .announcement: text,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }
}
