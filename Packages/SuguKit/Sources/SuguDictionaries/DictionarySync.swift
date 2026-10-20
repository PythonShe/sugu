import CryptoKit
import Foundation
import IOKit
import os
import SuguCore
import SuguLearning

/// Runs dictionary sync through the folder in preferences: pulls other
/// Macs' words on activation (at most every few minutes) and writes this
/// Mac's words shortly after they change. One sync runs at a time, and
/// writes land in the order they were made; after a failure the next
/// automatic attempt waits longer, up to an hour.
@MainActor
public final class DictionarySync {
    public static let pullInterval: TimeInterval = 300
    public static let maximumBackoff: TimeInterval = 3_600

    private enum Keys {
        static let deviceID = "SyncDeviceID"
        static let deviceMachine = "SyncDeviceMachine"
        static let lastSync = "SyncLastDate"
    }

    private let store: LearnedStore
    private let preferences: PreferencesStore
    private let defaults: UserDefaults
    /// When an automatic pull may run next.
    private var nextPull: Date?
    private var failures = 0
    private var running: Task<Void, Never>?
    /// Bumped when the folder changes, so a sync still finishing for the
    /// old folder leaves no state behind.
    private var generation = 0
    private var pendingExport: Task<Void, Never>?
    /// The last write of this Mac's file; the next one waits for it.
    private var lastWrite: Task<Void, any Error>?
    /// The sync preferences this sync last acted on.
    private var syncedFolder: String?
    private var syncedLearned: Bool
    private let now: @Sendable () -> Date
    private let exportDelay: Duration
    private let machine: String?
    public private(set) var lastError: (any Error)?
    public var onChange: (() -> Void)?

    /// `machine` tells this Mac from one its settings were copied from;
    /// it defaults to a hash of the hardware UUID.
    public init(
        store: LearnedStore,
        preferences: PreferencesStore,
        defaults: UserDefaults = .standard,
        exportDelay: Duration = .seconds(20),
        machine: String? = DictionarySync.hardwareStamp,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.preferences = preferences
        self.defaults = defaults
        self.exportDelay = exportDelay
        self.machine = machine
        self.now = now
        syncedFolder = preferences.preferences.syncFolderPath
        syncedLearned = preferences.preferences.syncLearnedWords
    }

    public var folder: URL? {
        preferences.preferences.syncFolderPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// When this Mac last read the other Macs' files and wrote its own.
    public var lastSync: Date? { defaults.object(forKey: Keys.lastSync) as? Date }

    /// Names this Mac's file. Random, and made again when the settings
    /// holding it arrive on another Mac (Migration Assistant, a restored
    /// backup), so two Macs never write the same file.
    var deviceID: String {
        if let id = defaults.string(forKey: Keys.deviceID) {
            let recorded = defaults.string(forKey: Keys.deviceMachine)
            if recorded == machine || machine == nil { return id }
            if recorded == nil {
                defaults.set(machine, forKey: Keys.deviceMachine)
                return id
            }
        }
        let id = UUID().uuidString
        defaults.set(id, forKey: Keys.deviceID)
        defaults.set(machine, forKey: Keys.deviceMachine)
        return id
    }

    /// A hash of this Mac's hardware UUID. It stays in this Mac's
    /// preferences and is never written to the sync folder.
    nonisolated public static let hardwareStamp: String? = {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let uuid = IORegistryEntryCreateCFProperty(service, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String else { return nil }
        return SHA256.hash(data: Data("Sugu sync \(uuid)".utf8)).map { String(format: "%02x", $0) }.joined()
    }()

    private func makeFolder() -> SyncFolder? {
        guard let folder else { return nil }
        return SyncFolder(folder: folder, deviceID: deviceID, store: store)
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
                if let name = snapshot.unreadable.first {
                    pullError = CocoaError(.fileReadNoPermission, userInfo: [NSFilePathErrorKey: name])
                }
            } catch {
                pullError = error
            }
            do {
                try await write(sync)
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
    /// Writing alone leaves the next pull where it was.
    @discardableResult
    public func storeDidChange() -> Task<Void, Never>? {
        guard folder != nil else { return nil }
        pendingExport?.cancel()
        let delay = exportDelay
        let generation = generation
        pendingExport = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, let sync = makeFolder() else { return }
            do {
                try await write(sync)
            } catch {
                // A change of folder while writing belongs to another folder now.
                guard generation == self.generation else { return }
                failed(error)
            }
        }
        return pendingExport
    }

    /// Called when preferences change. A new folder starts over; taking
    /// learned words or no longer taking them rewrites this Mac's file.
    public func preferencesDidChange() {
        let current = preferences.preferences
        if current.syncFolderPath != syncedFolder {
            syncedFolder = current.syncFolderPath
            syncedLearned = current.syncLearnedWords
            reset()
            onChange?()
            syncNow()
        } else if current.syncLearnedWords != syncedLearned {
            syncedLearned = current.syncLearnedWords
            storeDidChange()
        }
    }

    /// Writes this Mac's file once the write before it has landed, so an
    /// older snapshot never replaces a newer one.
    private func write(_ sync: SyncFolder) async throws {
        let previous = lastWrite
        let write = Task {
            _ = await previous?.result
            try await sync.export(includeLearned: self.preferences.preferences.syncLearnedWords)
        }
        lastWrite = write
        try await write.value
    }

    private func reset() {
        generation += 1
        running = nil
        pendingExport?.cancel()
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
        Log.sync.error("Sync failed: \(String(describing: error), privacy: .public)")
        failures += 1
        let delay = min(Self.pullInterval * pow(2, Double(failures - 1)), Self.maximumBackoff)
        nextPull = now().addingTimeInterval(delay)
        lastError = error
        onChange?()
    }
}
