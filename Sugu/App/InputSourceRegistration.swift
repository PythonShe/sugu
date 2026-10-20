import Carbon
import Foundation

/// Registers and enables Sugu's input source for the current user, so it
/// appears in the input menu right after installation. The package's
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
        return enabled
    }
}
