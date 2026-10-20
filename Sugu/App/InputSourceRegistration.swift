import Carbon
import Foundation

/// Registers, enables and selects Sugu's input source for the current
/// user, so it is in use right after installation. The package's
/// postinstall step runs `Sugu --register` as the console user.
enum InputSourceRegistration {
    static func registerAndEnable() -> Bool {
        let bundleURL = Bundle.main.bundleURL as CFURL
        guard TISRegisterInputSource(bundleURL) == noErr else { return false }
        guard let identifier = Bundle.main.bundleIdentifier else { return false }
        let filter = [kTISPropertyBundleID as String: identifier] as CFDictionary
        guard let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] else { return false }
        var enabled = false
        for source in sources where TISEnableInputSource(source) == noErr {
            enabled = true
        }
        // Selected only once enabled; failing to select still leaves Sugu
        // in the input menu.
        if enabled, let source = sources.first(where: isSelectable) { TISSelectInputSource(source) }
        return enabled
    }

    private static func isSelectable(_ source: TISInputSource) -> Bool {
        guard let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(value).takeUnretainedValue())
    }
}
