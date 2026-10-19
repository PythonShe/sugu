import Foundation
import SuguCore
import SuguInput

/// The last mode per app, kept in user defaults.
@MainActor
final class DefaultsModeMemory: ModeMemory {
    private static let key = "ModesByApp"
    private let defaults: UserDefaults
    private var modes: [String: String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        modes = defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
    }

    func mode(for bundleIdentifier: String) -> InputMode? {
        modes[bundleIdentifier].flatMap(InputMode.init(rawValue:))
    }

    func remember(_ mode: InputMode, for bundleIdentifier: String) {
        guard modes[bundleIdentifier] != mode.rawValue else { return }
        modes[bundleIdentifier] = mode.rawValue
        defaults.set(modes, forKey: Self.key)
    }
}
