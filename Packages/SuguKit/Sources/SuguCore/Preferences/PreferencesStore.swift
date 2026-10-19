import Foundation

/// Reads and writes `Preferences` in user defaults as one JSON value, and
/// tells observers when they change.
@MainActor
public final class PreferencesStore {
    public static let key = "Preferences"
    public static let didChangeNotification = Notification.Name("SuguPreferencesDidChange")

    private let defaults: UserDefaults

    public private(set) var preferences: Preferences

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let stored = try? JSONDecoder().decode(Preferences.self, from: data) {
            preferences = stored
        } else {
            preferences = Preferences()
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
