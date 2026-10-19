import AppKit
import SuguCore

/// Turns AppKit key events into Sugu's platform-free key model.
enum KeyTranslator {
    static func keyInput(from event: NSEvent) -> KeyInput {
        KeyInput(
            keyCode: event.keyCode,
            characters: event.characters ?? "",
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifiers: modifiers(from: event.modifierFlags)
        )
    }

    static func modifiers(from flags: NSEvent.ModifierFlags) -> KeyModifiers {
        var modifiers: KeyModifiers = []
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.capsLock) { modifiers.insert(.capsLock) }
        if flags.contains(.numericPad) { modifiers.insert(.numericPad) }
        if flags.contains(.function) { modifiers.insert(.function) }
        return modifiers
    }
}

/// Recognizes a Shift key pressed and released on its own.
struct ShiftTapDetector {
    /// Longer presses are holds, not taps.
    static let maximumDuration: TimeInterval = 0.5
    private var pressedAt: TimeInterval?

    /// Feeds a flags-changed event; returns true when it completes a tap.
    mutating func flagsChanged(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        let isShiftKey = event.keyCode == VirtualKey.shift || event.keyCode == VirtualKey.rightShift
        if isShiftKey, flags == .shift {
            pressedAt = event.timestamp
            return false
        }
        defer { pressedAt = nil }
        guard isShiftKey, flags.isEmpty, let pressedAt else { return false }
        return event.timestamp - pressedAt <= Self.maximumDuration
    }

    /// Any other key cancels a pending tap (Shift was used as a modifier).
    mutating func interrupt() {
        pressedAt = nil
    }
}
