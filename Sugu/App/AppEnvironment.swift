import AppKit
import os
import SuguCore
import SuguDictionaries
import SuguEngines
import SuguInput
import SuguLearning
import SuguUpdates

/// The process-wide object graph: preferences, the learned store, engines,
/// the input session and the windows around it.
@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    let locations = AppLocations.current
    let preferences = PreferencesStore()
    let store: LearnedStore?
    let engines: EngineHub
    let session: InputSession
    let coordinator: InputCoordinator
    let inputMenu: InputMenu
    let library: ModelLibrary
    let sync: DictionarySync?
    let updater = Updater()
    private var settings: SettingsWindowController?
    private var expiryDays = 0

    /// The learned store, tried three times: a lock held by the copy of
    /// Sugu an update is replacing passes within a second. Without it,
    /// typing works and nothing is learned until the next launch.
    private static func openStore(at url: URL, syllabary: PinyinSyllabary) -> LearnedStore? {
        for attempt in 1...3 {
            do {
                return try LearnedStore(url: url, syllabary: syllabary)
            } catch {
                Log.learning.fault("Learned store unavailable (attempt \(attempt)): \(String(describing: error), privacy: .public)")
                if attempt < 3 { Thread.sleep(forTimeInterval: 0.3) }
            }
        }
        return nil
    }

    private init() {
        let preferences = self.preferences.preferences
        let syllables = Lexicon.load(Lexicon.syllablesFile, in: locations.bundledLexicon)
        store = Self.openStore(at: locations.learnedStore, syllabary: PinyinSyllabary(syllables))
        Log.app.notice("Sugu \(Bundle.main.shortVersion, privacy: .public) started")
        engines = EngineHub(
            locations: locations.engines,
            preferences: preferences,
            store: store,
            version: Bundle.main.shortVersion
        )
        let latin = LatinInference(
            syllables: syllables,
            englishWords: Lexicon.load(Lexicon.englishWordsFile, in: locations.bundledLexicon)
        )
        session = InputSession(preferences: preferences, engines: engines, store: store, modeMemory: DefaultsModeMemory(), latin: latin)
        if #available(macOS 27.0, *) { session.assistant = AppleLanguageAssistant(preferences: self.preferences) }
        coordinator = InputCoordinator(
            session: session,
            preferences: self.preferences,
            candidateWindow: CandidateWindowController(),
            indicator: ModeIndicatorController()
        )
        library = ModelLibrary(engines: engines)
        let preferencesStore = self.preferences
        sync = store.map { DictionarySync(store: $0, preferences: preferencesStore) }
        inputMenu = InputMenu(coordinator: coordinator, preferences: self.preferences)
    }

    func start() {
        NotificationCenter.default.addObserver(forName: PreferencesStore.didChangeNotification, object: preferences, queue: .main) { _ in
            MainActor.assumeIsolated { AppEnvironment.shared.preferencesDidChange() }
        }
        NotificationCenter.default.addObserver(forName: LearnedStore.didChangeNotification, object: store, queue: .main) { _ in
            MainActor.assumeIsolated {
                AppEnvironment.shared.engines.learnedWordsDidChange()
                AppEnvironment.shared.sync?.storeDidChange()
            }
        }
        // The process lives for days: expire again when the date changes.
        NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppEnvironment.shared.expireLearnedWords() }
        }
        expireLearnedWords()
        // Load the engine the session starts in, so the first key is fast.
        engines.prepare(session.mode)
        sync?.pullIfDue()
    }

    func showSettings(_ pane: SettingsWindowController.Pane? = nil) {
        let controller = settings ?? SettingsWindowController(model: SettingsModel(environment: self))
        settings = controller
        controller.show(pane)
    }

    func showAddWord(_ draft: WordDraft) {
        let controller = settings ?? SettingsWindowController(model: SettingsModel(environment: self))
        settings = controller
        controller.addWord(draft)
    }

    private func preferencesDidChange() {
        let current = preferences.preferences
        engines.apply(current)
        coordinator.preferencesDidChange(current)
        sync?.preferencesDidChange()
        if current.learnedWordExpiryDays != expiryDays { expireLearnedWords() }
    }

    private func expireLearnedWords() {
        expiryDays = preferences.preferences.learnedWordExpiryDays
        store?.expire(olderThan: expiryDays)
    }
}
