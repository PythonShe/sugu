import Foundation
import SuguCore

/// Recognizes a Shift key pressed and released on its own.
public struct ShiftTapDetector: Sendable {
    /// Longer presses are holds, not taps.
    public static let maximumDuration: TimeInterval = 0.5
    private var pressedAt: TimeInterval?

    public init() {}

    /// Feeds a modifier change (a flags-changed event); returns true when it
    /// completes a tap. Caps Lock, numpad and fn state are ignored. A
    /// mouse click or scroll while Shift was down (`secondsSinceMouse`
    /// shorter than the press) makes it a Shift-click, not a tap.
    public mutating func flagsChanged(keyCode: UInt16, modifiers: KeyModifiers, timestamp: TimeInterval,
                                      secondsSinceMouse: TimeInterval = .infinity) -> Bool {
        let down = modifiers.subtracting([.capsLock, .numericPad, .function])
        let isShiftKey = keyCode == VirtualKey.shift || keyCode == VirtualKey.rightShift
        if isShiftKey, down == .shift {
            pressedAt = timestamp
            return false
        }
        defer { pressedAt = nil }
        guard isShiftKey, down.isEmpty, let pressedAt else { return false }
        let held = timestamp - pressedAt
        return held <= Self.maximumDuration && secondsSinceMouse > held
    }

    /// Any other key cancels a pending tap (Shift was used as a modifier).
    public mutating func interrupt() {
        pressedAt = nil
    }
}
