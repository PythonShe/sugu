import AppKit
import InputMethodKit

// IMK connects the system to this server by the connection name in
// Info.plist; it must exist before the run loop starts.
let connectionName = Bundle.main.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String ?? "Sugu_Connection"
let server = IMKServer(name: connectionName, bundleIdentifier: Bundle.main.bundleIdentifier)

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
withExtendedLifetime(server) {
    NSApplication.shared.run()
}
