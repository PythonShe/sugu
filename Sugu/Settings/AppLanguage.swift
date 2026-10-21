import AppKit

/// The language of Sugu's own windows and menus: the system's, or one
/// chosen in Settings. macOS reads an app's language once, at launch, from
/// its `AppleLanguages` default, so a change takes effect after a restart.
enum AppLanguage: String, CaseIterable {
    case system = ""
    case english = "en"
    case japanese = "ja"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"

    private static let key = "AppleLanguages"

    /// The choice saved for Sugu alone; the global default does not count.
    static var chosen: AppLanguage {
        get {
            let domain = Bundle.main.bundleIdentifier.flatMap { UserDefaults.standard.persistentDomain(forName: $0) }
            guard let first = (domain?[key] as? [String])?.first else { return .system }
            return AppLanguage(rawValue: first) ?? .system
        }
        set {
            if newValue == .system {
                UserDefaults.standard.removeObject(forKey: key)
            } else {
                UserDefaults.standard.set([newValue.rawValue], forKey: key)
            }
        }
    }

    /// The language each is written in, as language menus show them; the
    /// system's choice is named in the language in use.
    var title: String {
        switch self {
        case .system: String(localized: "System Language")
        case .english: "English"
        case .japanese: "日本語"
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        }
    }

    /// Opens Sugu again on Settings once this process has quit. Input
    /// sources reconnect to the new process as they are used.
    @MainActor
    static func restart() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\" --args \(showSettingsArgument)", Bundle.main.bundlePath]
        do {
            try process.run()
        } catch {
            return
        }
        NSApp.terminate(nil)
    }

    /// Launched with this, Sugu opens Settings on the General pane.
    static let showSettingsArgument = "--show-settings"
}
