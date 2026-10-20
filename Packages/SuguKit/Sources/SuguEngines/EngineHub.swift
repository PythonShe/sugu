import Foundation
import os
import SuguAzooKey
import SuguCore
import SuguInput
import SuguLearning
import SuguRime

/// Owns the language engines for the process and keeps them in step with
/// preferences. Each engine is created on first use of its mode.
@MainActor
public final class EngineHub: EngineSource {
    public struct Locations: Sendable {
        /// Bundled librime data (read-only).
        public var rimeShared: URL
        /// Per-user librime data: generated schema, grammar model, staging.
        public var rimeUser: URL
        /// AzooKey's working directory.
        public var azooKey: URL
        /// Downloaded models (grammar, Zenzai).
        public var models: URL
        /// Bundled word lists (`Lexicon`), for the pinyin syllables.
        public var lexicon: URL

        public init(rimeShared: URL, rimeUser: URL, azooKey: URL, models: URL, lexicon: URL) {
            self.rimeShared = rimeShared
            self.rimeUser = rimeUser
            self.azooKey = azooKey
            self.models = models
            self.lexicon = lexicon
        }

        /// The grammar model, when downloaded. octagram reads it from the
        /// librime user directory.
        public var grammarModel: URL {
            rimeUser.appendingPathComponent("\(RimeSchema.grammarLanguage).gram")
        }

        public var zenzaiModel: URL {
            models.appendingPathComponent("zenzai.gguf")
        }

        /// The generated rime-ice manifest; its presence marks rime-ice as
        /// installed.
        public var rimeIceManifest: URL {
            rimeUser.appendingPathComponent("\(RimeSchema.rimeIceDictionaryName).dict.yaml")
        }

        public var rimeIceTables: URL {
            rimeUser.appendingPathComponent(RimeSchema.rimeIceFolder, isDirectory: true)
        }

        public var hasGrammarModel: Bool { FileManager.default.fileExists(atPath: grammarModel.path) }
        public var hasZenzaiModel: Bool { FileManager.default.fileExists(atPath: zenzaiModel.path) }
        public var hasRimeIce: Bool { FileManager.default.fileExists(atPath: rimeIceManifest.path) }
    }

    public let locations: Locations
    public let version: String
    private let store: LearnedStore?
    private var preferences: Preferences
    private let runtime: RimeRuntime
    private var chinese: RimeEngine?
    private var japanese: AzooKeyEngine?
    /// The Zenzai model the Japanese converter has loaded, once it has.
    /// Until then Japanese converts without it.
    private var zenzaiLoaded: URL?
    private var zenzaiLoading: Task<Void, Never>?
    /// Counts model installs and removals, so a load that began before one
    /// is not adopted.
    private var zenzaiGeneration = 0
    private var preparing: Task<Void, Never>?
    private var userWordsRefresh: Task<Void, Never>?
    private var chineseWordsUpdate: Task<Void, Never>?
    private var chineseWordsWrite: Task<ChineseWordsWrite, Never>?
    /// The file changed since the open Chinese session read it.
    private var chineseWordsNeedReload = false
    /// How long learned-word changes settle before librime's copy is
    /// rewritten, so a burst of commits rewrites it once.
    private let chineseWordsDelay: Duration
    private var decoders: (schema: RimeSchema, scheme: PinyinDecoder, fullPinyin: PinyinDecoder?)?
    /// Set when the last Chinese deployment failed, for the settings window.
    public private(set) var chineseError: (any Error)? {
        didSet { if (chineseError == nil) != (oldValue == nil) { onChineseStatusChange?() } }
    }
    public var onChineseStatusChange: (() -> Void)?
    /// After a failed deployment: when that schema may be tried again, and
    /// the wait after another failure. The wait doubles up to ten minutes,
    /// so a broken deployment is not repeated on every keystroke.
    private var retry: (schema: RimeSchema, at: ContinuousClock.Instant, wait: Duration)?
    public var onEngineReady: ((InputMode) -> Void)?
    private var chineseScript: ChineseScript
    /// Converters by script, opened on first use and kept, so switching
    /// between apps with different scripts does not reopen them.
    private var scriptConverters: [ChineseScript: ScriptConverter] = [:]

    public init(locations: Locations, preferences: Preferences, store: LearnedStore?, version: String, chineseWordsDelay: Duration = .seconds(2)) {
        self.locations = locations
        self.preferences = preferences
        self.store = store
        self.version = version
        self.chineseWordsDelay = chineseWordsDelay
        self.chineseScript = preferences.chineseScript
        self.runtime = RimeRuntime(directories: .init(shared: locations.rimeShared, user: locations.rimeUser))
        // Brings the file in line with the store from launch.
        updateChineseWords()
    }

    // MARK: EngineSource

    public func engine(for mode: InputMode) -> (any CompositionEngine)? {
        switch mode {
        case .chinese:
            guard runtime.isReady else { warmUp(.chinese); return nil }
            if let chinese { return chinese }
            let engine = RimeEngine(runtime: runtime, script: chineseScript)
            chinese = engine
            chineseWordsNeedReload = false
            return engine
        case .japanese:
            if let japanese { return japanese }
            let started = ContinuousClock.now
            let engine = AzooKeyEngine(configuration: japaneseConfiguration)
            Log.engines.notice("Japanese ready in \(ContinuousClock.now - started, privacy: .public)")
            japanese = engine
            if let store { engine.setUserWords(store.allWords(mode: .japanese).map { ($0.reading, $0.text) }) }
            loadZenzai()
            return engine
        case .english:
            return nil
        }
    }

    /// Refreshes AzooKey's user words once per run-loop turn, however many
    /// changes arrive (a commit both notifies the store and calls this).
    public func learnedWordsDidChange() {
        updateChineseWords()
        guard japanese != nil, userWordsRefresh == nil else { return }
        userWordsRefresh = Task { [weak self] in
            guard let self else { return }
            userWordsRefresh = nil
            guard let japanese, let store else { return }
            japanese.setUserWords(store.allWords(mode: .japanese).map { ($0.reading, $0.text) })
        }
    }

    public func setChineseScript(_ script: ChineseScript) {
        guard script != chineseScript else { return }
        chineseScript = script
        chinese?.setScript(script)
        // Opened at focus rather than on the first keystroke.
        if chinese != nil { _ = converter(for: script) }
    }

    public func chineseText(_ text: String) -> String? {
        converter(for: chineseScript)?.convert(text)
    }

    private func converter(for script: ChineseScript) -> ScriptConverter? {
        if let converter = scriptConverters[script] { return converter }
        let openCC = locations.rimeShared.appendingPathComponent("opencc")
        // Not kept when it fails: the tables appear once librime is set up.
        let converter = ScriptConverter.toScript(script, openCC: openCC)
        scriptConverters[script] = converter
        return converter
    }

    // MARK: Lifecycle

    /// Gets a mode's engine ready before its first key: Chinese deploys in
    /// the background; Japanese is created now, at a mode change or focus
    /// rather than on a keystroke.
    public func prepare(_ mode: InputMode) {
        switch mode {
        case .chinese: warmUp(.chinese)
        case .japanese: _ = engine(for: .japanese)
        case .english: break
        }
    }

    /// Starts loading the engine for a mode in the background, so it is
    /// ready by the first keystroke.
    private func warmUp(_ mode: InputMode) {
        let schema = schema
        guard mode == .chinese, preparing == nil, !runtime.isReady || runtime.schema != schema else { return }
        if let retry, retry.schema == schema, ContinuousClock.now < retry.at { return }
        // A retry rebuilds from the bundled data, in case the build left
        // behind is what fails.
        let rebuild = retry?.schema == schema
        preparing = Task {
            let started = ContinuousClock.now
            do {
                if rebuild { runtime.discardBuild() }
                try await runtime.prepare(schema, version: version)
                Log.engines.notice("Chinese ready in \(ContinuousClock.now - started, privacy: .public)\(rebuild ? " after a rebuild" : "", privacy: .public)")
                chineseError = nil
                retry = nil
                // Settings that changed while deploying redeploy below; an
                // engine on this schema would lose its session to that.
                if runtime.schema == self.schema {
                    // Opening the session reads the user dictionary; done
                    // here, not on the first keystroke.
                    _ = engine(for: .chinese)
                    chinese?.openSession()
                    updateChineseWords(after: .zero)
                    onEngineReady?(.chinese)
                }
            } catch {
                chineseError = error
                let wait = retry.flatMap { $0.schema == schema ? min($0.wait * 2, .seconds(600)) : nil } ?? .seconds(5)
                retry = (schema, ContinuousClock.now + wait, wait)
                Log.engines.error("Chinese deployment failed, retrying after \(wait, privacy: .public): \(String(describing: error), privacy: .public)")
            }
            preparing = nil
            // Settings may have changed while deploying.
            if runtime.schema != self.schema { warmUp(.chinese) }
        }
    }

    public func isFailing(_ mode: InputMode) -> Bool {
        mode == .chinese && chineseError != nil
    }

    /// Tries a failed Chinese deployment again now, from a fresh build.
    public func retryChinese() {
        guard let retry else { return }
        self.retry = (retry.schema, ContinuousClock.now, retry.wait)
        warmUp(.chinese)
    }

    /// Waits until the Chinese engine is deployed (for tools and tests).
    public func waitUntilReady() async {
        warmUp(.chinese)
        while let task = preparing { await task.value }
    }

    // MARK: Learned words in librime

    /// Rewrites librime's user dictionary from the store once changes have
    /// settled, off the main thread, and reopens the Chinese session to
    /// read it (decision D-025). The file follows the store whether or not
    /// Chinese is loaded, so cleared or expired words leave it too.
    private func updateChineseWords(after delay: Duration? = nil) {
        guard let store else { return }
        chineseWordsUpdate?.cancel()
        let delay = delay ?? chineseWordsDelay
        chineseWordsUpdate = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled, let self else { return }
            let schema = schema
            let locations = locations
            let cached = decoders.flatMap { $0.schema == schema ? ($0.schema, $0.scheme, $0.fullPinyin) : nil }
            let learned = store.allWords(mode: .chinese)
            // Writes land in order: an older table never replaces a newer one.
            let previous = chineseWordsWrite
            let write = Task.detached(priority: .utility) { () -> ChineseWordsWrite in
                _ = await previous?.value
                guard let decoders = cached ?? Self.makeDecoders(for: schema, locations: locations) else { return ChineseWordsWrite() }
                // The best words first, should there be more than the file holds.
                let now = Date()
                let words = learned.map { ($0.score(at: now), $0) }.sorted { $0.0 > $1.0 }
                    .map { RimeUserDictionary.Word(reading: $0.1.reading, text: $0.1.text, count: $0.1.count) }
                let table = RimeUserDictionary.table(for: words, decoder: decoders.1, fullPinyin: decoders.2)
                return ChineseWordsWrite(decoders: decoders, written: (try? RimeUserDictionary.write(table, in: locations.rimeUser)) ?? false)
            }
            chineseWordsWrite = write
            let result = await write.value
            if let made = result.decoders { decoders = (made.0, made.1, made.2) }
            if result.written { chineseWordsNeedReload = true }
            await reloadChineseWords()
        }
    }

    private struct ChineseWordsWrite: Sendable {
        var decoders: (RimeSchema, PinyinDecoder, PinyinDecoder?)?
        var written = false
    }

    private nonisolated static func makeDecoders(for schema: RimeSchema, locations: Locations) -> (RimeSchema, PinyinDecoder, PinyinDecoder?)? {
        let syllables = Lexicon.load(Lexicon.syllablesFile, in: locations.lexicon)
        guard !syllables.isEmpty, let decoder = PinyinDecoder(schema: schema, syllables: syllables, sharedData: locations.rimeShared) else { return nil }
        // Imported words carry full pinyin whatever the scheme.
        let fullPinyin = schema.scheme == .fullPinyin ? nil : PinyinDecoder(schema: RimeSchema(), syllables: syllables, sharedData: locations.rimeShared)
        return (schema, decoder, fullPinyin)
    }

    /// Reopens the Chinese session between compositions when the file
    /// changed since it was read. A session not open yet reads the new file
    /// when it opens; a cancelled wait leaves the flag for the next update.
    private func reloadChineseWords() async {
        while chineseWordsNeedReload {
            guard let chinese else { chineseWordsNeedReload = false; return }
            if chinese.reloadUserDictionary() { chineseWordsNeedReload = false; return }
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return }
        }
    }

    /// Waits until both engines have the store's latest words (for tools
    /// and tests).
    public func waitForLearnedWords() async {
        while let task = chineseWordsUpdate {
            await task.value
            if chineseWordsUpdate == task { break }
        }
        while let task = userWordsRefresh { await task.value }
    }

    public func apply(_ preferences: Preferences) {
        let previous = self.preferences
        self.preferences = preferences
        if schema != runtime.schema, runtime.isReady || preparing != nil {
            chinese = nil
            warmUp(.chinese)
        }
        if let japanese, previous.kanaInput != preferences.kanaInput || previous.japanesePredictions != preferences.japanesePredictions
            || previous.liveConversion != preferences.liveConversion
            || previous.typoCorrection != preferences.typoCorrection || previous.zenzaiEnabled != preferences.zenzaiEnabled {
            japanese.update(japaneseConfiguration)
            loadZenzai()
        }
    }

    // MARK: Configuration

    public var isGrammarModelInstalled: Bool { locations.hasGrammarModel }
    public var isZenzaiModelInstalled: Bool { locations.hasZenzaiModel }
    public var isRimeIceInstalled: Bool { locations.hasRimeIce }

    private var schema: RimeSchema {
        RimeSchema(
            scheme: preferences.pinyinScheme,
            fuzzy: preferences.fuzzyPinyin,
            useGrammar: preferences.useGrammarModel && isGrammarModelInstalled,
            dictionary: preferences.chineseDictionary == .rimeIce && isRimeIceInstalled ? .rimeIce : .wanxiang
        )
    }

    private var japaneseConfiguration: AzooKeyEngine.Configuration {
        var configuration = AzooKeyEngine.Configuration(workingDirectory: locations.azooKey)
        configuration.kanaInput = preferences.kanaInput
        configuration.predictions = preferences.japanesePredictions
        configuration.liveConversion = preferences.liveConversion
        configuration.typoCorrection = preferences.typoCorrection
        configuration.zenzaiModel = preferences.zenzaiEnabled && isZenzaiModelInstalled && zenzaiLoaded == locations.zenzaiModel ? locations.zenzaiModel : nil
        try? FileManager.default.createDirectory(at: locations.azooKey, withIntermediateDirectories: true)
        return configuration
    }

    /// Reloads the Chinese engine after a model was installed or removed.
    public func modelsDidChange() {
        // Only redeploy Chinese if it was in use; otherwise it loads with the
        // new data on first use.
        if schema != runtime.schema, runtime.isReady || preparing != nil { chinese = nil; warmUp(.chinese) }
        // A new or removed model file is loaded afresh.
        zenzaiLoaded = nil
        zenzaiGeneration += 1
        japanese?.update(japaneseConfiguration)
        loadZenzai()
    }

    /// Loads Zenzai off the main thread and hands the converter to the
    /// Japanese engine between compositions (decision D-032).
    private func loadZenzai() {
        guard preferences.zenzaiEnabled, isZenzaiModelInstalled, japanese != nil,
              zenzaiLoaded != locations.zenzaiModel, zenzaiLoading == nil else { return }
        let model = locations.zenzaiModel
        let workingDirectory = locations.azooKey
        let generation = zenzaiGeneration
        zenzaiLoading = Task { [weak self] in
            let started = ContinuousClock.now
            let loaded = await AzooKeyEngine.loadZenzai(model, workingDirectory: workingDirectory)
            while let japanese = self?.japanese, !japanese.state.isEmpty {
                try? await Task.sleep(for: .milliseconds(200))
            }
            guard let self else { return }
            zenzaiLoading = nil
            guard generation == zenzaiGeneration else { loadZenzai(); return }
            guard let loaded else {
                Log.engines.error("Zenzai model did not load")
                return
            }
            guard let japanese, preferences.zenzaiEnabled else { return }
            japanese.adopt(loaded)
            zenzaiLoaded = loaded.model
            japanese.update(japaneseConfiguration)
            Log.engines.notice("Zenzai ready in \(ContinuousClock.now - started, privacy: .public)")
        }
    }

    /// Waits until Zenzai is loaded, when it is on (for tools and tests).
    public func waitForZenzai() async {
        while let task = zenzaiLoading { await task.value }
    }
}
