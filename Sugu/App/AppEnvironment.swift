import AppKit
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

    private init() {
        let preferences = self.preferences.preferences
        let syllables = Lexicon.load(Lexicon.syllablesFile, in: locations.bundledLexicon)
        store = try? LearnedStore(url: locations.learnedStore, syllabary: PinyinSyllabary(syllables))
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
        let days = preferences.preferences.learnedWordExpiryDays
        if days > 0 { _ = store?.expire(olderThan: days) }
        // Load the engine the session starts in, so the first key is fast.
        engines.prepare(session.mode)
        sync?.pullIfDue()
    }

    func showSettings(_ pane: SettingsWindowController.Pane? = nil) {
        let controller = settings ?? SettingsWindowController(model: SettingsModel(environment: self))
        settings = controller
        controller.show(pane)
    }

    private func preferencesDidChange() {
        let current = preferences.preferences
        engines.apply(current)
        coordinator.preferencesDidChange(current)
    }
}
