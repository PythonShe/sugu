/// Modifier state of a key event, independent of AppKit.
public struct KeyModifiers: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let shift = KeyModifiers(rawValue: 1 << 0)
    public static let control = KeyModifiers(rawValue: 1 << 1)
    public static let option = KeyModifiers(rawValue: 1 << 2)
    public static let command = KeyModifiers(rawValue: 1 << 3)
    public static let capsLock = KeyModifiers(rawValue: 1 << 4)
    public static let numericPad = KeyModifiers(rawValue: 1 << 5)
    public static let function = KeyModifiers(rawValue: 1 << 6)

    /// Modifiers that turn a key into a shortcut rather than text.
    public static let shortcut: KeyModifiers = [.control, .command]
}

/// Physical key codes (macOS virtual key codes) that Sugu treats as commands.
/// Text keys are read from the characters the active layout produces, so
/// composition works on any layout while shortcuts stay physical.
public enum VirtualKey {
    public static let returnKey: UInt16 = 0x24
    public static let tab: UInt16 = 0x30
    public static let space: UInt16 = 0x31
    public static let delete: UInt16 = 0x33
    public static let escape: UInt16 = 0x35
    public static let command: UInt16 = 0x37
    public static let shift: UInt16 = 0x38
    public static let capsLock: UInt16 = 0x39
    public static let rightShift: UInt16 = 0x3C
    public static let keypadEnter: UInt16 = 0x4C
    public static let f6: UInt16 = 0x61
    public static let f7: UInt16 = 0x62
    public static let f8: UInt16 = 0x64
    public static let f9: UInt16 = 0x65
    public static let f10: UInt16 = 0x6D
    public static let eisu: UInt16 = 0x66
    public static let kana: UInt16 = 0x68
    public static let home: UInt16 = 0x73
    public static let pageUp: UInt16 = 0x74
    public static let forwardDelete: UInt16 = 0x75
    public static let end: UInt16 = 0x77
    public static let pageDown: UInt16 = 0x79
    public static let left: UInt16 = 0x7B
    public static let right: UInt16 = 0x7C
    public static let down: UInt16 = 0x7D
    public static let up: UInt16 = 0x7E
}

/// A key press as Sugu sees it: the physical key, the text the active
/// layout produced for it, and the modifier state.
public struct KeyInput: Sendable, Equatable {
    public var keyCode: UInt16
    /// Characters produced by the active layout with modifiers applied.
    public var characters: String
    /// Characters produced by the active layout without modifiers (Shift
    /// still applied by the layout where it changes the character).
    public var charactersIgnoringModifiers: String
    public var modifiers: KeyModifiers
    /// The physical keyboard is JIS, which places kana input's keys
    /// differently from ANSI and ISO keyboards.
    public var isJISKeyboard: Bool

    public init(keyCode: UInt16, characters: String, charactersIgnoringModifiers: String? = nil, modifiers: KeyModifiers = [], isJISKeyboard: Bool = false) {
        self.keyCode = keyCode
        self.characters = characters
        self.charactersIgnoringModifiers = charactersIgnoringModifiers ?? characters
        self.modifiers = modifiers
        self.isJISKeyboard = isJISKeyboard
    }

    /// The single printable character of this key, if it produces one.
    public var printable: Character? {
        guard characters.count == 1, let c = characters.first else { return nil }
        guard let scalar = c.unicodeScalars.first, scalar.value >= 0x20, scalar.value != 0x7F else { return nil }
        // Private-use scalars are function keys (NSF1FunctionKey and friends).
        if (0xF700...0xF8FF).contains(scalar.value) { return nil }
        return c
    }

    public var isShortcut: Bool { !modifiers.isDisjoint(with: .shortcut) }
}
