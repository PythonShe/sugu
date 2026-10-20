import Foundation

/// Reads and writes `Preferences` in user defaults as one JSON value, and
/// tells observers when they change.
@MainActor
public final class PreferencesStore {
    public static let key = "Preferences"
    public static let didChangeNotification = Notification.Name("SuguPreferencesDidChange")

    private let defaults: UserDefaults

    public private(set) var preferences: Preferences

    /// A first launch starts from the defaults for `preferredLanguages` and
    /// keeps them, so a later change of system language does not move them.
    public init(defaults: UserDefaults = .standard, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let stored = try? JSONDecoder().decode(Preferences.self, from: data) {
            preferences = stored
        } else {
            preferences = Preferences(preferredLanguages: preferredLanguages)
            if defaults.data(forKey: Self.key) == nil, let data = try? JSONEncoder().encode(preferences) {
                defaults.set(data, forKey: Self.key)
            }
        }
    }

    public func update(_ change: (inout Preferences) -> Void) {
        var updated = preferences
        change(&updated)
        guard updated != preferences else { return }
        preferences = updated
        if let data = try? JSONEncoder().encode(updated) {
            defaults.set(data, forKey: Self.key)
        }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
