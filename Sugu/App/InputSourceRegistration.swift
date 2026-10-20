import Carbon
import Foundation

/// Registers and enables Sugu's input source for the current user, and on
/// a first installation selects it, so it is in use right away; an upgrade
/// leaves the user's current input source alone. The package's postinstall
/// step runs `Sugu --register` as the console user.
enum InputSourceRegistration {
    static func registerAndEnable() -> Bool {
        let bundleURL = Bundle.main.bundleURL as CFURL
        guard TISRegisterInputSource(bundleURL) == noErr else { return false }
        guard let identifier = Bundle.main.bundleIdentifier else { return false }
        let filter = [kTISPropertyBundleID as String: identifier] as CFDictionary
        guard let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] else { return false }
        let wasEnabled = sources.contains { flag(kTISPropertyInputSourceIsEnabled, of: $0) }
        var enabled = false
        for source in sources where TISEnableInputSource(source) == noErr {
            enabled = true
        }
        // Failing to select still leaves Sugu in the input menu.
        if enabled, !wasEnabled, let source = sources.first(where: { flag(kTISPropertyInputSourceIsSelectCapable, of: $0) }) {
            TISSelectInputSource(source)
        }
        return enabled
    }

    private static func flag(_ property: CFString, of source: TISInputSource) -> Bool {
        guard let value = TISGetInputSourceProperty(source, property) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(value).takeUnretainedValue())
    }
}
