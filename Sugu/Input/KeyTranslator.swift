import AppKit
import Carbon
import SuguCore

/// Turns AppKit key events into Sugu's platform-free key model.
enum KeyTranslator {
    static func keyInput(from event: NSEvent) -> KeyInput {
        KeyInput(
            keyCode: event.keyCode,
            characters: event.characters ?? "",
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifiers: modifiers(from: event.modifierFlags),
            isJISKeyboard: KBGetLayoutType(Int16(LMGetKbdType())) == kKeyboardJIS
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
