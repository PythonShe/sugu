import Foundation
import SuguCore
import SuguDictionaries
import SuguLearning

/// Runs dictionary sync through the folder in preferences: pulls other
/// Macs' words on activation (at most every few minutes) and writes this
/// Mac's words shortly after they change.
@MainActor
final class DictionarySync {
    static let pullInterval: TimeInterval = 300
    static let exportDelay: Duration = .seconds(20)

    private enum Keys {
        static let deviceID = "SyncDeviceID"
        static let watermarks = "SyncWatermarks"
        static let lastSync = "SyncLastDate"
    }

    private let store: LearnedStore
    private let preferences: PreferencesStore
    private let defaults: UserDefaults
    private var lastPull: Date?
    private var pendingExport: Task<Void, Never>?
    private(set) var lastError: (any Error)?
    var onChange: (() -> Void)?

    init(store: LearnedStore, preferences: PreferencesStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.preferences = preferences
        self.defaults = defaults
    }

    var folder: URL? {
        preferences.preferences.syncFolderPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    var lastSync: Date? { defaults.object(forKey: Keys.lastSync) as? Date }

    private var deviceID: String {
        if let id = defaults.string(forKey: Keys.deviceID) { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: Keys.deviceID)
        return id
    }

    private func makeFolder() -> SyncFolder? {
        guard let folder else { return nil }
        let stored = defaults.dictionary(forKey: Keys.watermarks) as? [String: Date] ?? [:]
        return SyncFolder(folder: folder, deviceID: deviceID, store: store, watermarks: stored)
    }

    /// Pulls and pushes now.
    func syncNow() {
        guard let sync = makeFolder() else { return }
        let includeLearned = preferences.preferences.syncLearnedWords
        do {
            try sync.pull(includeLearned: includeLearned)
            defaults.set(sync.watermarks, forKey: Keys.watermarks)
            try sync.export(includeLearned: includeLearned)
            defaults.set(Date(), forKey: Keys.lastSync)
            lastPull = Date()
            lastError = nil
        } catch {
            lastError = error
        }
        onChange?()
    }

    /// Called when a field gains focus; pulls when the last pull is old.
    func pullIfDue() {
        guard folder != nil else { return }
        if let lastPull, Date().timeIntervalSince(lastPull) < Self.pullInterval { return }
        syncNow()
    }

    /// Called when the store changed; writes this Mac's file after a pause.
    func storeDidChange() {
        guard folder != nil else { return }
        pendingExport?.cancel()
        pendingExport = Task { [weak self] in
            try? await Task.sleep(for: Self.exportDelay)
            guard !Task.isCancelled, let self, let sync = makeFolder() else { return }
            do {
                try sync.export(includeLearned: preferences.preferences.syncLearnedWords)
                defaults.set(Date(), forKey: Keys.lastSync)
                lastError = nil
            } catch {
                lastError = error
            }
            onChange?()
        }
    }

    /// Forgets which files were already merged, as when the folder changes.
    func reset() {
        defaults.removeObject(forKey: Keys.watermarks)
        defaults.removeObject(forKey: Keys.lastSync)
        lastPull = nil
    }
}
