import AppKit
import SuguCore
import SuguDictionaries
import SuguEngines
import SuguInput
import SuguLearning

/// State behind the settings window. Edits write through to the
/// preferences store; changes from elsewhere (the input menu, sync) flow
/// back in through notifications, and panes refresh on `onChange`.
@MainActor
final class SettingsModel {
    enum Change {
        case preferences, downloads, words, sync, engines
    }

    var preferences: Preferences {
        didSet {
            guard preferences != oldValue else { return }
            let preferences = preferences
            environment.preferences.update { $0 = preferences }
            notify(.preferences)
        }
    }
    private(set) var downloads: [ModelLibrary.Item: ModelLibrary.State] = [:]
    private(set) var words: [LearnedWord] = []
    private(set) var lastSync: Date?
    private(set) var syncFailed = false

    /// Set while the settings window is open. Closed, store changes only
    /// mark the word list stale, so commits do not rebuild it.
    var isVisible = false {
        didSet { if isVisible, wordsStale { reloadWords() } }
    }
    private var wordsStale = false
    private var wordsReload: Task<Void, Never>?

    private let environment: AppEnvironment
    private var observers: [any NSObjectProtocol] = []
    private var listeners: [(Change) -> Void] = []

    /// Registers a listener for changes; panes refresh their controls here.
    func observe(_ listener: @escaping (Change) -> Void) {
        listeners.append(listener)
    }

    private func notify(_ change: Change) {
        for listener in listeners { listener(change) }
    }

    init(environment: AppEnvironment) {
        self.environment = environment
        preferences = environment.preferences.preferences
        reloadDownloads()
        reloadWords()
        reloadSync()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: PreferencesStore.didChangeNotification, object: environment.preferences, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.preferencesChanged() }
        })
        observers.append(center.addObserver(forName: LearnedStore.didChangeNotification, object: environment.store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.storeDidChange() }
        })
        environment.library.onChange = { [weak self] _ in self?.reloadDownloads() }
        environment.sync?.onChange = { [weak self] in self?.reloadSync() }
        environment.engines.onChineseStatusChange = { [weak self] in self?.notify(.engines) }
    }

    private func preferencesChanged() {
        let current = environment.preferences.preferences
        if current != preferences { preferences = current }
    }

    private func reloadDownloads() {
        downloads = Dictionary(uniqueKeysWithValues: ModelLibrary.Item.allCases.map { ($0, environment.library.state(of: $0)) })
        notify(.downloads)
    }

    /// Reloads at most once per run-loop turn, and only while visible.
    private func storeDidChange() {
        guard isVisible else { wordsStale = true; return }
        guard wordsReload == nil else { return }
        wordsReload = Task { [weak self] in
            self?.wordsReload = nil
            self?.reloadWords()
        }
    }

    private func reloadWords() {
        wordsStale = false
        words = environment.store?.allWords() ?? []
        notify(.words)
    }

    private func reloadSync() {
        lastSync = environment.sync?.lastSync
        syncFailed = environment.sync?.lastError != nil
        notify(.sync)
    }

    // MARK: Modes

    func isEnabled(_ mode: InputMode) -> Bool { preferences.enabledModes.contains(mode) }

    /// The modes in the user's order: the first is the one Sugu starts in.
    var orderedModes: [InputMode] {
        preferences.enabledModes + InputMode.allCases.filter { !preferences.enabledModes.contains($0) }
    }

    /// A mode turned back on takes its place for the preferred languages,
    /// as on first launch.
    func setEnabled(_ mode: InputMode, _ enabled: Bool) {
        let modes = Set(preferences.enabledModes.filter { $0 != mode } + (enabled ? [mode] : []) + [.english])
        let order = Preferences(preferredLanguages: Locale.preferredLanguages).enabledModes
        preferences.enabledModes = order.filter(modes.contains)
    }

    // MARK: Engines

    var chineseFailed: Bool { environment.engines.chineseError != nil }
    func retryChinese() { environment.engines.retryChinese() }

    // MARK: Downloads

    func state(of item: ModelLibrary.Item) -> ModelLibrary.State { downloads[item] ?? .notInstalled }
    func isInstalled(_ item: ModelLibrary.Item) -> Bool { state(of: item) == .installed }
    func install(_ item: ModelLibrary.Item) { environment.library.install(item) }
    func cancel(_ item: ModelLibrary.Item) { environment.library.cancel(item) }
    func remove(_ item: ModelLibrary.Item) { environment.library.remove(item) }

    // MARK: Learned words

    var hasStore: Bool { environment.store != nil }

    func setPinned(_ pinned: Bool, for word: LearnedWord) { environment.store?.setPinned(pinned, id: word.id) }
    func delete(_ ids: Set<LearnedWord.ID>) { environment.store?.delete(ids: Array(ids)) }
    func forgetLastHour() { environment.store?.forget() }
    func deleteAllWords() { environment.store?.deleteAll() }

    @discardableResult
    func addWord(reading: String, text: String, mode: InputMode) -> Bool {
        environment.store?.addUserWord(reading: reading, text: text, mode: mode) ?? false
    }

    // MARK: Dictionaries

    /// Imports dictionary files; returns how many words were new.
    func importDictionaries(_ urls: [URL]) throws -> Int {
        guard let store = environment.store else { return 0 }
        var added = 0
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            if DictionaryFormat.detect(url) == .sugu {
                added += try store.merge(SuguDictionaryFile.decode(Data(contentsOf: url)))
            } else {
                added += try store.importUserWords(DictionaryImporter.read(url).map { ($0.reading, $0.text, $0.mode) })
            }
        }
        return added
    }

    func exportDictionary(includeLearned: Bool) -> Data {
        let words = (environment.store?.allWords() ?? []).filter { includeLearned || $0.kind == .user }
        return SuguDictionaryFile.encode(words)
    }

    func setSyncFolder(_ url: URL?) {
        environment.sync?.reset()
        preferences.syncFolderPath = url?.path
        if url != nil { environment.sync?.syncNow() }
        reloadSync()
    }

    func syncNow() { environment.sync?.syncNow() }

    // MARK: Settings files

    func exportSettings() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(preferences)
    }

    func importSettings(from url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        preferences = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: url))
    }

    func resetSettings() { preferences = Preferences() }

    func showDataFolder() {
        let folder = environment.locations.support
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    // MARK: Updates

    var updatesAvailable: Bool { environment.updater.isAvailable }

    var checksForUpdatesAutomatically: Bool {
        get { environment.updater.checksAutomatically }
        set { environment.updater.checksAutomatically = newValue }
    }

    func checkForUpdates() { environment.updater.checkForUpdates() }

    var version: String { "\(Bundle.main.shortVersion) (\(Bundle.main.buildVersion))" }
}
