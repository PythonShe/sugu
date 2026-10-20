import Carbon
import Foundation

/// Registers and enables Sugu's input source for the current user, and on
/// a first installation selects it, so it is in use right away; an upgrade
/// leaves the user's current input source alone. The package's postinstall
/// step runs `Sugu --register` as the console user. Where macOS does not
/// let it enable the source, the user adds Sugu in Input Sources.
enum InputSourceRegistration {
    static func registerAndEnable() -> Bool {
        let bundleURL = Bundle.main.bundleURL as CFURL
        guard TISRegisterInputSource(bundleURL) == noErr else { return false }
        let sources = installedSources()
        let wasEnabled = sources.contains { flag(kTISPropertyInputSourceIsEnabled, of: $0) }
        for source in sources {
            TISEnableInputSource(source)
        }
        // Enabling can return noErr and change nothing; only a fresh list
        // says whether Sugu is in the input menu now.
        let current = installedSources()
        guard current.contains(where: { flag(kTISPropertyInputSourceIsEnabled, of: $0) }) else { return false }
        // Failing to select still leaves Sugu in the input menu.
        if !wasEnabled, let source = current.first(where: { flag(kTISPropertyInputSourceIsSelectCapable, of: $0) }) {
            TISSelectInputSource(source)
        }
        return true
    }

    private static func installedSources() -> [TISInputSource] {
        guard let identifier = Bundle.main.bundleIdentifier else { return [] }
        let filter = [kTISPropertyBundleID as String: identifier] as CFDictionary
        return TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] ?? []
    }

    private static func flag(_ property: CFString, of source: TISInputSource) -> Bool {
        guard let value = TISGetInputSourceProperty(source, property) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(value).takeUnretainedValue())
    }
}
