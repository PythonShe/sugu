import AppKit
import InputMethodKit

#if DEBUG
if let index = CommandLine.arguments.firstIndex(of: "--snapshot-settings"), index + 1 < CommandLine.arguments.count {
    SettingsSnapshot.run(output: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
    exit(0)
}
#endif

// IMK connects the system to this server by the connection name in
// Info.plist; it must exist before the run loop starts.
let connectionName = Bundle.main.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String ?? "Sugu_Connection"
let server = IMKServer(name: connectionName, bundleIdentifier: Bundle.main.bundleIdentifier)

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
withExtendedLifetime(server) {
    NSApplication.shared.run()
}
