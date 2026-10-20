import AppKit
import Carbon
import InputMethodKit
import SuguCore
import SuguInput

/// Connects IMK clients to the input session: attaches the focused field,
/// routes keys and mode toggles, and keeps the candidate window and mode
/// indicator in step with the session.
@MainActor
final class InputCoordinator {
    private let session: InputSession
    private let preferences: PreferencesStore
    private let candidateWindow: CandidateWindowController
    private let indicator: ModeIndicatorController
    private var client: TextInputClient?
    private var shiftTap = ShiftTapDetector()
    /// The width ⌃. goes back to from half width.
    private var widthBeforeHalf = PunctuationWidth.automatic
    /// The last key event, to drop the duplicates some hosts deliver.
    private var lastKey: (timestamp: TimeInterval, keyCode: UInt16, handled: Bool)?

    init(session: InputSession, preferences: PreferencesStore, candidateWindow: CandidateWindowController, indicator: ModeIndicatorController) {
        self.session = session
        self.preferences = preferences
        self.candidateWindow = candidateWindow
        self.indicator = indicator
        session.onChange = { [unowned self] in render($0.display) }
        session.onModeChange = { [unowned self] mode, byUser in modeDidChange(to: mode, byUser: byUser) }
        candidateWindow.onSelect = { [unowned session] row in session.selectCandidate(onPage: row) }
        candidateWindow.onTurnPage = { [unowned session] delta in session.turnPage(by: delta) }
    }

    var mode: InputMode { session.mode }

    // MARK: Clients

    func activate(client: any IMKTextInput & NSObjectProtocol, controller: IMKInputController) {
        let adapter = attach(client, controller: controller)
        session.isSecureInput = isSecureInputHere()
        session.attach(adapter)
        syncCapsLock()
        AppEnvironment.shared.sync?.pullIfDue()
    }

    func deactivate(client: Any?) {
        guard let current = self.client, current.represents(client) else { return }
        session.detach(current)
        self.client = nil
        candidateWindow.reset()
    }

    func commitComposition(client: Any?) {
        guard let current = self.client, current.represents(client) else { return }
        session.commitComposition()
    }

    @discardableResult
    private func attach(_ client: any IMKTextInput & NSObjectProtocol, controller: IMKInputController) -> TextInputClient {
        if let current = self.client {
            if current.represents(client) { return current }
            // A field left without deactivation gets its composition while
            // its adapter still lives: the session holds it weakly.
            session.detach(current)
        }
        candidateWindow.reset()
        let adapter = TextInputClient(client: client, controller: controller)
        self.client = adapter
        return adapter
    }

    /// Whether secure input may concern the field being typed in. Secure
    /// input is global, so left on by an app in the background, or by the
    /// login window, it would otherwise turn Sugu off in every app. It is
    /// set aside only when the window server names a holder that cannot own
    /// this field: the login window, or another regular app that is neither
    /// the client nor frontmost. A helper process (a browser's web content)
    /// may hold it for the client's field, so anything else stays secure.
    private func isSecureInputHere() -> Bool {
        guard IsSecureEventInputEnabled() else { return false }
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              let holder = (session["kCGSSessionSecureInputPID"] as? NSNumber)?.int32Value,
              let app = NSRunningApplication(processIdentifier: holder) else { return true }
        if app.bundleIdentifier == "com.apple.loginwindow" { return false }
        guard app.activationPolicy == .regular, !app.isActive else { return true }
        return app.bundleIdentifier == client?.bundleIdentifier
    }

    // MARK: Events

    func handle(_ event: NSEvent, client: any IMKTextInput & NSObjectProtocol, controller: IMKInputController) -> Bool {
        let isNewClient = self.client?.represents(client) != true
        let adapter = attach(client, controller: controller)
        // Known before the session attaches, which may read the field.
        session.isSecureInput = isSecureInputHere()
        if isNewClient { session.attach(adapter) }
        switch event.type {
        case .flagsChanged:
            flagsChanged(event)
            return false
        case .keyDown:
            if let lastKey, lastKey.timestamp == event.timestamp, lastKey.keyCode == event.keyCode {
                return lastKey.handled
            }
            shiftTap.interrupt()
            // A click since the last key may have moved the caret.
            if let lastKey, Self.secondsSinceMouse() < ProcessInfo.processInfo.systemUptime - lastKey.timestamp {
                session.caretMayHaveMoved()
            }
            let handled = keyDown(event)
            lastKey = (event.timestamp, event.keyCode, handled)
            return handled
        default:
            return false
        }
    }

    private func keyDown(_ event: NSEvent) -> Bool {
        let key = KeyTranslator.keyInput(from: event)
        if capsLockSelectsEnglish, session.mode == .english, key.modifiers.contains(.capsLock),
           key.modifiers.isDisjoint(with: [.command, .control, .option]), let character = key.printable, character.isLetter {
            // Caps Lock is the English switch here, not a case lock.
            let text = key.modifiers.contains(.shift) ? character.uppercased() : character.lowercased()
            client?.commit(text)
            return true
        }
        if session.mode == .chinese, key.modifiers.contains(.control), key.modifiers.isDisjoint(with: [.command, .option, .shift]),
           key.charactersIgnoringModifiers == "." {
            switchPunctuationWidth()
            return true
        }
        return session.handle(key)
    }

    /// ⌃. switches Chinese punctuation to half width and back, as in Sogou,
    /// Microsoft Pinyin and McBopomofo.
    private func switchPunctuationWidth() {
        let current = preferences.preferences.punctuationWidth
        if current != .half { widthBeforeHalf = current }
        let next = current == .half ? widthBeforeHalf : .half
        preferences.update { $0.punctuationWidth = next }
        guard let client else { return }
        let half = next == .half
        indicator.show(half ? "," : "，", named: half ? String(localized: "Half Width") : String(localized: "Full Width"), near: client.compositionRect())
    }

    private func flagsChanged(_ event: NSEvent) {
        if event.keyCode == VirtualKey.capsLock {
            syncCapsLock()
            return
        }
        let tapped = shiftTap.flagsChanged(keyCode: event.keyCode, modifiers: KeyTranslator.modifiers(from: event.modifierFlags),
                                           timestamp: event.timestamp, secondsSinceMouse: Self.secondsSinceMouse())
        if tapped, preferences.preferences.englishToggle == .shiftTap {
            session.shiftTapped()
        }
    }

    /// Time since the last click, drag or scroll anywhere, from the window
    /// server; IMK sends Sugu no mouse events.
    private static func secondsSinceMouse() -> TimeInterval {
        let types: [CGEventType] = [.leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseDragged, .scrollWheel]
        return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? .infinity
    }

    private var capsLockSelectsEnglish: Bool { preferences.preferences.englishToggle == .capsLock }

    /// With the Caps Lock toggle, the light shows English.
    private func syncCapsLock() {
        guard capsLockSelectsEnglish else { return }
        let isOn = NSEvent.modifierFlags.contains(.capsLock)
        if isOn != (session.mode == .english) { session.toggleEnglish() }
    }

    // MARK: Rendering

    private func render(_ display: SessionDisplay) {
        guard let client, let presentation = display.candidates else {
            candidateWindow.hide()
            return
        }
        candidateWindow.show(presentation, mode: display.mode, near: client.compositionRect(at: display.candidateAnchor), preferences: preferences.preferences)
    }

    /// Shows the new mode at the caret. A switch that came with the focus
    /// shows only where the field reports its caret: an app switch is not
    /// worth a label at the pointer.
    private func modeDidChange(to mode: InputMode, byUser: Bool) {
        guard preferences.preferences.showModeIndicator, let client else { return }
        let caret = client.compositionRect()
        guard byUser || caret != .zero else { return }
        indicator.show(mode, keyboard: preferences.preferences.chineseKeyboard, near: caret)
    }

    // MARK: Menu commands

    func select(_ mode: InputMode) {
        session.setMode(mode)
    }

    func reconvertSelection() {
        session.reconvertSelection()
    }

    var canReviseSelection: Bool { session.canReviseSelection }

    func addWord() {
        AppEnvironment.shared.showAddWord(session.selectedWordDraft())
    }

    func revise(selectionWith task: TextTask) {
        session.revise(selectionWith: task)
    }

    func preferencesDidChange(_ preferences: Preferences) {
        session.preferences = preferences
        syncCapsLock()
    }
}
