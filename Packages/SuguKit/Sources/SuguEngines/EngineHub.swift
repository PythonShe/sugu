import Foundation
import os
import SuguAzooKey
import SuguCore
import SuguInput
import SuguLearning
import SuguLM
import SuguRime

/// Owns the language engines for the process and keeps them in step with
/// preferences. Each engine is created when its mode is entered or a field
/// gains focus, ahead of the first key.
@MainActor
public final class EngineHub: EngineSource {
    public let locations: Locations
    public let version: String
    private let store: LearnedStore?
    private var preferences: Preferences
    private let runtime: RimeRuntime
    private var chinese: (any ChineseEngine)?
    private var japanese: AzooKeyEngine?
    /// The Zenzai model the Japanese converter has loaded, once it has.
    /// Until then Japanese converts without it.
    private var zenzaiLoaded: URL?
    private var zenzaiLoading: Task<Void, Never>?
    /// Counts model installs and removals, so a load that began before one
    /// is not adopted.
    private var zenzaiGeneration = 0
    /// Reads AzooKey's dictionary into memory once the Japanese engine is made.
    private var japaneseDictionaryLoading: Task<Void, Never>?
    private var preparing: Task<Void, Never>?
    /// A redeployment waiting for the Chinese composition to end.
    private var pendingRedeploy: Task<Void, Never>?
    private var userWordsRefresh: Task<Void, Never>?
    private var chineseWordsUpdate: Task<Void, Never>?
    private var chineseWordsWrite: Task<ChineseWordsWrite, Never>?
    /// The file changed since the open Chinese session read it.
    private var chineseWordsNeedReload = false
    /// How long learned-word changes settle before librime's copy is
    /// rewritten, so a burst of commits rewrites it once.
    private let chineseWordsDelay: Duration
    private var decoders: (schema: RimeSchema, scheme: PinyinDecoder, fullPinyin: PinyinDecoder?)?
    /// Respells Chinese sentences (ADR 0005), for the schema it decodes
    /// keys of; nil when the model or word list is not bundled.
    private var chineseRespelling: (schema: RimeSchema, respeller: SentenceRespeller, decoder: PinyinDecoder)?
    /// Set when the last Chinese deployment failed, for the settings window.
    public private(set) var chineseError: (any Error)? {
        didSet { if (chineseError == nil) != (oldValue == nil) { onChineseStatusChange?() } }
    }
    public var onChineseStatusChange: (() -> Void)?
    /// After a failed deployment: when that schema may be tried again, and
    /// the wait after another failure. The wait doubles up to ten minutes,
    /// so a broken deployment is not repeated on every keystroke.
    private var retry: (schema: RimeSchema, at: ContinuousClock.Instant, wait: Duration)?
    /// After librime gave no session: when the build may be made again, and
    /// the wait after another failure (`sessionFailed`).
    private var sessionRetry: (at: ContinuousClock.Instant, wait: Duration)?
    public var onEngineReady: ((InputMode) -> Void)?
    /// After a crash loop (`recoverFromCrashLoop`): Chinese without the
    /// grammar model and Japanese without Zenzai, until the run has lasted
    /// `recoveryLength`.
    public private(set) var isRecovering = false
    static let recoveryLength = Duration.seconds(120)
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
        // Chinese words and n-grams are stored in Simplified, the script
        // of librime's dictionary and the respeller (D-094).
        store?.chineseForms = self
        // Brings the file in line with the store from launch.
        updateChineseWords()
    }

    // MARK: EngineSource

    public func engine(for mode: InputMode) -> (any CompositionEngine)? {
        switch mode {
        case .chinese:
            guard runtime.isReady else { warmUp(.chinese); return nil }
            if let chinese {
                guard chinese.openSession() else { sessionFailed(); return nil }
                sessionRetry = nil
                return chinese
            }
            let engine: any ChineseEngine
            if runtime.schema?.keyboard == .zhuyin {
                let zhuyin = ZhuyinEngine(runtime: runtime, script: chineseScript)
                zhuyin.learnedWords = { [weak self] codes in
                    guard let self, let store else { return [] }
                    return store.lookup(codes, mode: .chinese).map { store.text(of: $0, in: self.chineseScript) }
                }
                engine = zhuyin
            } else {
                engine = RimeEngine(runtime: runtime, script: chineseScript)
            }
            attachRespelling(to: engine)
            chinese = engine
            chineseWordsNeedReload = false
            guard engine.openSession() else { sessionFailed(); return nil }
            sessionRetry = nil
            return engine
        case .japanese:
            if let japanese { return japanese }
            let started = ContinuousClock.now
            let engine = AzooKeyEngine(configuration: japaneseConfiguration)
            engine.languageModel = loadLanguageModel(.japanese).map { BlendedLanguageModel(base: $0, personal: personalNGrams(for: .japanese)) }
            Log.engines.notice("Japanese ready in \(ContinuousClock.now - started, privacy: .public)")
            japanese = engine
            if let store { engine.setUserWords(Self.userWords(in: store)) }
            loadJapaneseDictionary(for: engine)
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
            japanese.setUserWords(Self.userWords(in: store))
        }
    }

    private static func userWords(in store: LearnedStore) -> [AzooKeyEngine.UserWord] {
        store.allWords(mode: .japanese).map { .init(reading: $0.reading, text: $0.text, isEstablished: $0.isEstablished) }
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

    public func pinyin(of text: String) -> String? {
        let simplified = converter(for: .simplified)?.convert(text) ?? text
        guard let wordList = try? Data(contentsOf: locations.lexicon.appendingPathComponent(Lexicon.pinyinWordsFile), options: .mappedIfSafe) else { return nil }
        return ChineseReadings.syllables(of: simplified, wordList: wordList)?.joined()
    }

    /// Keys that type Chinese `text` in the scheme in use, or Zhuyin's
    /// codes, for reconverting it; nil when a character is in no listed
    /// word. Reads the word list for this alone.
    public func chineseReading(of text: String) -> String? {
        let simplified = converter(for: .simplified)?.convert(text) ?? text
        guard let wordList = try? Data(contentsOf: locations.lexicon.appendingPathComponent(Lexicon.pinyinWordsFile), options: .mappedIfSafe),
              let syllables = ChineseReadings.syllables(of: simplified, wordList: wordList) else { return nil }
        // The word list has no tones; librime's characters give them.
        if preferences.chineseKeyboard == .zhuyin {
            return (chinese as? ZhuyinEngine)?.codes(typing: text, readAs: syllables)
        }
        let schema = schema
        let decoder = decoders.flatMap { $0.schema == schema ? $0.scheme : nil } ?? Self.makeDecoders(for: schema, locations: locations)?.1
        return decoder?.keys(typing: syllables)
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
                await loadChineseRespelling(for: schema)
                Log.engines.notice("Chinese ready in \(ContinuousClock.now - started, privacy: .public)\(rebuild ? " after a rebuild" : "", privacy: .public)")
                chineseError = nil
                retry = nil
                // Settings that changed while deploying redeploy below; an
                // engine on this schema would lose its session to that.
                if runtime.schema == self.schema {
                    // Opening the session reads the user dictionary; done
                    // here, not on the first keystroke.
                    _ = engine(for: .chinese)
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
            if runtime.schema != self.schema || !runtime.isReady { warmUp(.chinese) }
        }
    }

    /// Loads the Chinese model and word list, and the schema's key decoder,
    /// off the main thread; a new schema needs only its decoder.
    private func loadChineseRespelling(for schema: RimeSchema) async {
        if chineseRespelling?.schema == schema { return }
        let locations = locations
        let respeller: SentenceRespeller
        if let loaded = chineseRespelling?.respeller {
            respeller = loaded
        } else {
            let loaded = await Task.detached(priority: .utility) { () -> (CharacterLanguageModel, PinyinWords)? in
                guard let modelURL = locations.languageModel(.chinese), FileManager.default.fileExists(atPath: modelURL.path) else { return nil }
                do {
                    return (try CharacterLanguageModel(contentsOf: modelURL), try PinyinWords(contentsOf: locations.lexicon.appendingPathComponent(Lexicon.pinyinWordsFile)))
                } catch {
                    Log.engines.error("Chinese language model did not load: \(String(describing: error), privacy: .public)")
                    return nil
                }
            }.value
            guard let (model, words) = loaded else { return }
            respeller = SentenceRespeller(model: BlendedLanguageModel(base: model, personal: personalNGrams(for: .chinese)), words: words)
            if let store { respeller.userWords = Set(store.allWords(mode: .chinese).map(\.text)) }
        }
        let cachedDecoder = decoders.flatMap { $0.schema == schema ? $0.scheme : nil }
        let decoder = if let cachedDecoder { cachedDecoder } else {
            await Task.detached(priority: .utility) { Self.makeDecoders(for: schema, locations: locations)?.1 }.value
        }
        guard let decoder else { chineseRespelling = nil; return }
        chineseRespelling = (schema, respeller, decoder)
        // An engine made while this loaded, once librime was ready.
        if let chinese { attachRespelling(to: chinese) }
    }

    /// Pinyin respells only with the decoder of the schema in use.
    private func attachRespelling(to engine: any ChineseEngine) {
        guard let chineseRespelling else { return }
        let decoder = chineseRespelling.schema == runtime.schema ? chineseRespelling.decoder : nil
        engine.respelling = .init(respeller: chineseRespelling.respeller, decoder: decoder) { [weak self] in self?.converter(for: $0) }
    }

    /// librime deployed but gives no session: the build is taken as broken
    /// and made again from the bundled data, while typed letters wait in
    /// the loading engine rather than vanish. The first time at once, then
    /// after a wait that doubles up to ten minutes, until a session opens.
    private func sessionFailed() {
        chinese = nil
        chineseError = RimeRuntime.Error.sessionUnavailable
        let now = ContinuousClock.now
        if let sessionRetry, now < sessionRetry.at { return }
        let wait = sessionRetry.map { min($0.wait * 2, .seconds(600)) } ?? .seconds(5)
        sessionRetry = (now + wait, wait)
        Log.engines.error("Chinese session did not open; rebuilding, then waiting \(wait, privacy: .public) before another")
        runtime.setNeedsDeployment()
        retry = (schema, now, wait)
        warmUp(.chinese)
    }

    public func isFailing(_ mode: InputMode) -> Bool {
        mode == .chinese && chineseError != nil
    }

    /// Tries a failed Chinese deployment again now, from a fresh build.
    public func retryChinese() {
        if sessionRetry != nil {
            sessionRetry = nil
            runtime.setNeedsDeployment()
        }
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
            // Stored in Simplified, as the respeller and librime's
            // dictionary read; librime's filters give the script in use.
            chineseRespelling?.respeller.userWords = Set(learned.map(\.text))
            // Writes land in order: an older table never replaces a newer one.
            let previous = chineseWordsWrite
            let write = Task.detached(priority: .utility) { () -> ChineseWordsWrite in
                _ = await previous?.value
                guard let decoders = cached ?? Self.makeDecoders(for: schema, locations: locations) else { return ChineseWordsWrite() }
                // The best words first, should there be more than the file holds.
                let now = Date()
                let words = learned.map { ($0.score(at: now), $0) }.sorted { $0.0 > $1.0 }
                    .map { RimeUserDictionary.Word(reading: $0.1.reading, text: $0.1.text, count: $0.1.count) }
                let table = RimeUserDictionary.table(for: words, decoder: decoders.1, fullPinyin: decoders.2, keyboard: schema.keyboard)
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
        redeployChinese()
        if let japanese, previous.kanaInput != preferences.kanaInput || previous.japanesePredictions != preferences.japanesePredictions
            || previous.liveConversion != preferences.liveConversion
            || previous.typoCorrection != preferences.typoCorrection || previous.phoneticRomaji != preferences.phoneticRomaji
            || previous.contextualN != preferences.contextualN
            || previous.zenzaiEnabled != preferences.zenzaiEnabled {
            if !preferences.zenzaiEnabled {
                // The engine frees the model; turning it back on loads afresh.
                zenzaiLoaded = nil
                zenzaiGeneration += 1
            }
            japanese.update(japaneseConfiguration)
            loadZenzai()
        }
        if previous.learnsPhrases != preferences.learnsPhrases {
            japanese?.languageModel?.personal = personalNGrams(for: .japanese)
            chineseRespelling?.respeller.model.personal = personalNGrams(for: .chinese)
        }
    }

    /// The user's n-grams for a mode's model, while they are used.
    private func personalNGrams(for mode: InputMode) -> PersonalNGrams? {
        preferences.learnsPhrases ? store?.personalNGrams(for: mode) : nil
    }

    // MARK: Configuration

    public var isGrammarModelInstalled: Bool { locations.hasGrammarModel }
    public var isZenzaiModelInstalled: Bool { locations.hasZenzaiModel }
    public var isRimeIceInstalled: Bool { locations.hasRimeIce }

    private var schema: RimeSchema {
        RimeSchema(
            keyboard: preferences.chineseKeyboard,
            scheme: preferences.pinyinScheme,
            fuzzy: preferences.fuzzyPinyin,
            grammar: preferences.useGrammarModel && !isRecovering ? locations.grammarModel?.deletingPathExtension().lastPathComponent : nil,
            dictionary: preferences.chineseDictionary == .rimeIce && isRimeIceInstalled ? .rimeIce : .wanxiang
        )
    }

    private var japaneseConfiguration: AzooKeyEngine.Configuration {
        var configuration = AzooKeyEngine.Configuration(workingDirectory: locations.azooKey)
        configuration.kanaInput = preferences.kanaInput
        configuration.predictions = preferences.japanesePredictions
        configuration.liveConversion = preferences.liveConversion
        configuration.typoCorrection = preferences.typoCorrection
        configuration.phoneticRomaji = preferences.phoneticRomaji
        configuration.contextualN = preferences.contextualN
        configuration.zenzaiModel = preferences.zenzaiEnabled && isZenzaiModelInstalled && zenzaiLoaded == locations.zenzaiModel ? locations.zenzaiModel : nil
        try? FileManager.default.createDirectory(at: locations.azooKey, withIntermediateDirectories: true)
        return configuration
    }

    private func loadLanguageModel(_ mode: InputMode) -> CharacterLanguageModel? {
        guard let url = locations.languageModel(mode), FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try CharacterLanguageModel(contentsOf: url)
        } catch {
            Log.engines.error("Language model \(url.lastPathComponent, privacy: .public) did not load: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Reloads what uses a model after it was installed or removed.
    public func modelDidChange(_ item: ModelLibrary.Item) {
        switch item {
        case .grammarModel:
            // A new file has a new name, so a new schema.
            redeployChinese()
        case .rimeIce:
            // An update replaces the tables under the same schema.
            if runtime.schema?.dictionary == .rimeIce { runtime.setNeedsDeployment() }
            redeployChinese()
        case .zenzaiModel:
            // A new or removed model file is loaded afresh.
            zenzaiLoaded = nil
            zenzaiGeneration += 1
            japanese?.update(japaneseConfiguration)
            loadZenzai()
        }
    }

    /// Redeploys Chinese for a changed schema, if it was in use; otherwise
    /// it loads with the new schema on first use. A redeployment ends
    /// librime's sessions, so one asked for during a composition (a
    /// download finishing) waits for it to end.
    private func redeployChinese() {
        guard schema != runtime.schema || !runtime.isReady, runtime.schema != nil || preparing != nil else { return }
        if let chinese, !chinese.state.isEmpty {
            guard pendingRedeploy == nil else { return }
            pendingRedeploy = Task { [weak self] in
                while let chinese = self?.chinese, !chinese.state.isEmpty {
                    try? await Task.sleep(for: .milliseconds(250))
                }
                self?.pendingRedeploy = nil
                self?.redeployChinese()
            }
            return
        }
        chinese = nil
        warmUp(.chinese)
    }

    /// Starts this run as after a crash loop, before any engine loads: the
    /// librime build is made again from the bundled data, and the grammar
    /// model and Zenzai, the likeliest to crash while loading, wait until
    /// the run has lasted `recoveryLength`.
    public func recoverFromCrashLoop() {
        Log.engines.fault("Started several times within a minute; recovering")
        isRecovering = true
        runtime.discardBuild()
        Task { [weak self] in
            try? await Task.sleep(for: Self.recoveryLength)
            guard let self else { return }
            Log.engines.notice("Recovered")
            isRecovering = false
            redeployChinese()
            loadZenzai()
        }
    }

    /// Loads Zenzai off the main thread and hands the converter to the
    /// Japanese engine between compositions (decision D-032).
    private func loadZenzai() {
        guard preferences.zenzaiEnabled, isZenzaiModelInstalled, japanese != nil, !isRecovering,
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

    /// Hands the Japanese engine its dictionary in memory between
    /// compositions; until then it reads the dictionary's files.
    private func loadJapaneseDictionary(for engine: AzooKeyEngine) {
        japaneseDictionaryLoading = Task { [weak self, weak engine] in
            let started = ContinuousClock.now
            let loaded = await AzooKeyEngine.loadMemoryDictionary()
            while let engine, !engine.state.isEmpty {
                try? await Task.sleep(for: .milliseconds(200))
            }
            self?.japaneseDictionaryLoading = nil
            guard let engine else { return }
            engine.adopt(loaded)
            Log.engines.notice("Japanese dictionary in memory in \(ContinuousClock.now - started, privacy: .public)")
        }
    }

    /// Waits until the Japanese dictionary is in memory (for tools).
    public func waitForJapaneseDictionary() async {
        while let task = japaneseDictionaryLoading { await task.value }
    }

    /// Waits until Zenzai is loaded, when it is on (for tools and tests).
    public func waitForZenzai() async {
        while let task = zenzaiLoading { await task.value }
    }
}

extension EngineHub: ChineseForms {
    public func simplified(_ text: String) -> String? {
        converter(for: .simplified)?.convert(text)
    }

    public func text(_ text: String, in script: ChineseScript) -> String? {
        converter(for: script)?.convert(text)
    }
}
