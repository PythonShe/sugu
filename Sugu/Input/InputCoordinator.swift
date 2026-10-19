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
    /// The last key event, to drop the duplicates some hosts deliver.
    private var lastKey: (timestamp: TimeInterval, keyCode: UInt16, handled: Bool)?

    init(session: InputSession, preferences: PreferencesStore, candidateWindow: CandidateWindowController, indicator: ModeIndicatorController) {
        self.session = session
        self.preferences = preferences
        self.candidateWindow = candidateWindow
        self.indicator = indicator
        session.onChange = { [unowned self] in render($0.display) }
        session.onModeChange = { [unowned self] mode in modeDidChange(to: mode) }
        candidateWindow.onSelect = { [unowned session] row in session.selectCandidate(onPage: row) }
        candidateWindow.onTurnPage = { [unowned session] delta in session.turnPage(by: delta) }
    }

    var mode: InputMode { session.mode }

    // MARK: Clients

    func activate(client: any IMKTextInput & NSObjectProtocol, controller: IMKInputController) {
        let adapter = attach(client, controller: controller)
        session.isSecureInput = IsSecureEventInputEnabled()
        session.attach(adapter)
        syncCapsLock()
        AppEnvironment.shared.sync?.pullIfDue()
    }

    func deactivate(client: Any?) {
        guard let current = self.client, current.represents(client) else { return }
        session.detach(current)
        self.client = nil
        candidateWindow.hide()
    }

    func commitComposition(client: Any?) {
        guard let current = self.client, current.represents(client) else { return }
        session.commitComposition()
    }

    @discardableResult
    private func attach(_ client: any IMKTextInput & NSObjectProtocol, controller: IMKInputController) -> TextInputClient {
        if let current = self.client, current.represents(client) { return current }
        let adapter = TextInputClient(client: client, controller: controller)
        self.client = adapter
        return adapter
    }

    // MARK: Events

    func handle(_ event: NSEvent, client: any IMKTextInput & NSObjectProtocol, controller: IMKInputController) -> Bool {
        if self.client?.represents(client) != true {
            session.attach(attach(client, controller: controller))
        }
        session.isSecureInput = IsSecureEventInputEnabled()
        switch event.type {
        case .flagsChanged:
            flagsChanged(event)
            return false
        case .keyDown:
            if let lastKey, lastKey.timestamp == event.timestamp, lastKey.keyCode == event.keyCode {
                return lastKey.handled
            }
            shiftTap.interrupt()
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
        return session.handle(key)
    }

    private func flagsChanged(_ event: NSEvent) {
        if event.keyCode == VirtualKey.capsLock {
            syncCapsLock()
            return
        }
        if shiftTap.flagsChanged(event), preferences.preferences.englishToggle == .shiftTap {
            session.toggleEnglish()
        }
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
        candidateWindow.show(presentation, mode: display.mode, near: client.compositionRect(), preferences: preferences.preferences)
    }

    private func modeDidChange(to mode: InputMode) {
        guard preferences.preferences.showModeIndicator, let client else { return }
        indicator.show(mode, near: client.compositionRect())
    }

    // MARK: Menu commands

    func select(_ mode: InputMode) {
        session.setMode(mode)
    }

    func reconvertSelection() {
        session.reconvertSelection()
    }

    func preferencesDidChange(_ preferences: Preferences) {
        session.preferences = preferences
        syncCapsLock()
    }
}
