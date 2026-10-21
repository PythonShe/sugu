import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        AppEnvironment.shared.start()
        // Restarted from Settings to change the language.
        if CommandLine.arguments.contains(AppLanguage.showSettingsArgument) {
            AppEnvironment.shared.showSettings(.general)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
