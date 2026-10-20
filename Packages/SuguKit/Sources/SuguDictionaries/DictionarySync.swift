import Foundation
import SuguCore
import SuguLearning

/// Runs dictionary sync through the folder in preferences: pulls other
/// Macs' words on activation (at most every few minutes) and writes this
/// Mac's words shortly after they change. One sync runs at a time; after
/// a failure the next automatic attempt waits longer, up to an hour.
@MainActor
public final class DictionarySync {
    public static let pullInterval: TimeInterval = 300
    public static let maximumBackoff: TimeInterval = 3_600

    private enum Keys {
        static let deviceID = "SyncDeviceID"
        static let watermarks = "SyncWatermarks"
        static let lastSync = "SyncLastDate"
        static let includedLearned = "SyncIncludedLearned"
    }

    private let store: LearnedStore
    private let preferences: PreferencesStore
    private let defaults: UserDefaults
    /// When an automatic pull may run next.
    private var nextPull: Date?
    private var failures = 0
    private var running: Task<Void, Never>?
    /// Bumped by `reset()`, so a sync still finishing for the old folder
    /// leaves no state behind.
    private var generation = 0
    private var pendingExport: Task<Void, Never>?
    private let now: @Sendable () -> Date
    private let exportDelay: Duration
    public private(set) var lastError: (any Error)?
    public var onChange: (() -> Void)?

    public init(
        store: LearnedStore,
        preferences: PreferencesStore,
        defaults: UserDefaults = .standard,
        exportDelay: Duration = .seconds(20),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.preferences = preferences
        self.defaults = defaults
        self.exportDelay = exportDelay
        self.now = now
    }

    public var folder: URL? {
        preferences.preferences.syncFolderPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    public var lastSync: Date? { defaults.object(forKey: Keys.lastSync) as? Date }

    private var deviceID: String {
        if let id = defaults.string(forKey: Keys.deviceID) { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: Keys.deviceID)
        return id
    }

    private func makeFolder() -> SyncFolder? {
        guard let folder else { return nil }
        // Watermarks only cover the words that were being taken; when learned
        // words are switched on, older ones must be read again.
        let includeLearned = preferences.preferences.syncLearnedWords
        if defaults.object(forKey: Keys.includedLearned) as? Bool != includeLearned {
            defaults.removeObject(forKey: Keys.watermarks)
            defaults.set(includeLearned, forKey: Keys.includedLearned)
        }
        let stored = defaults.dictionary(forKey: Keys.watermarks) as? [String: Date] ?? [:]
        return SyncFolder(folder: folder, deviceID: deviceID, store: store, watermarks: stored)
    }

    /// Pulls and pushes now, unless a sync is already running. Returns the
    /// sync's task.
    @discardableResult
    public func syncNow() -> Task<Void, Never>? {
        guard running == nil, let sync = makeFolder() else { return nil }
        let includeLearned = preferences.preferences.syncLearnedWords
        let generation = generation
        running = Task {
            // This Mac's file is written even when reading others failed.
            var pullError: (any Error)?
            do {
                let snapshot = try await sync.read()
                guard generation == self.generation else { return }
                try sync.merge(snapshot, includeLearned: includeLearned)
                defaults.set(sync.watermarks, forKey: Keys.watermarks)
                if let name = snapshot.unreadable.first {
                    pullError = CocoaError(.fileReadNoPermission, userInfo: [NSFilePathErrorKey: name])
                }
            } catch {
                pullError = error
            }
            do {
                try await sync.export(includeLearned: includeLearned)
                guard generation == self.generation else { return }
                pendingExport?.cancel()
                if let pullError { failed(pullError) } else { succeeded() }
            } catch {
                guard generation == self.generation else { return }
                failed(pullError ?? error)
            }
            running = nil
        }
        return running
    }

    /// Called when a field gains focus; pulls when the last pull is old.
    @discardableResult
    public func pullIfDue() -> Task<Void, Never>? {
        guard folder != nil else { return nil }
        if let nextPull, now() < nextPull { return nil }
        return syncNow()
    }

    /// Called when the store changed; writes this Mac's file after a pause.
    @discardableResult
    public func storeDidChange() -> Task<Void, Never>? {
        guard folder != nil else { return nil }
        pendingExport?.cancel()
        let delay = exportDelay
        pendingExport = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, let sync = makeFolder() else { return }
            do {
                try await sync.export(includeLearned: preferences.preferences.syncLearnedWords)
                succeeded()
            } catch {
                failed(error)
            }
        }
        return pendingExport
    }

    /// Forgets which files were already merged, as when the folder changes.
    public func reset() {
        generation += 1
        running = nil
        pendingExport?.cancel()
        defaults.removeObject(forKey: Keys.watermarks)
        defaults.removeObject(forKey: Keys.lastSync)
        nextPull = nil
        failures = 0
        lastError = nil
    }

    private func succeeded() {
        defaults.set(now(), forKey: Keys.lastSync)
        failures = 0
        nextPull = now().addingTimeInterval(Self.pullInterval)
        lastError = nil
        onChange?()
    }

    /// A folder that is gone or unreadable is retried at 5, 10, 20… minutes.
    private func failed(_ error: any Error) {
        failures += 1
        let delay = min(Self.pullInterval * pow(2, Double(failures - 1)), Self.maximumBackoff)
        nextPull = now().addingTimeInterval(delay)
        lastError = error
        onChange?()
    }
}
