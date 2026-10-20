import Foundation
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
    public private(set) var chineseError: (any Error)?
    /// The schema whose deployment failed; not retried until settings or
    /// installed data change it, so a broken deploy does not repeat on
    /// every keystroke.
    private var failedSchema: RimeSchema?
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
            let engine = AzooKeyEngine(configuration: japaneseConfiguration)
            japanese = engine
            if let store { engine.setUserWords(store.allWords(mode: .japanese).map { ($0.reading, $0.text) }) }
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

    /// Starts loading the engine for a mode in the background, so it is
    /// ready by the first keystroke.
    public func warmUp(_ mode: InputMode) {
        let schema = schema
        guard mode == .chinese, preparing == nil, schema != failedSchema, !runtime.isReady || runtime.schema != schema else { return }
        preparing = Task {
            do {
                try await runtime.prepare(schema, version: version)
                chineseError = nil
                failedSchema = nil
                updateChineseWords(after: .zero)
            } catch {
                chineseError = error
                failedSchema = schema
            }
            preparing = nil
            // Settings may have changed while deploying.
            if runtime.schema != self.schema { warmUp(.chinese) }
        }
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
            let words = store.allWords(mode: .chinese).map { RimeUserDictionary.Word(reading: $0.reading, text: $0.text, count: $0.count) }
            // Writes land in order: an older table never replaces a newer one.
            let previous = chineseWordsWrite
            let write = Task.detached(priority: .utility) { () -> ChineseWordsWrite in
                _ = await previous?.value
                guard let decoders = cached ?? Self.makeDecoders(for: schema, locations: locations) else { return ChineseWordsWrite() }
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

    /// Waits for a pending rewrite of librime's user dictionary (for tools
    /// and tests).
    public func waitForChineseWords() async {
        while let task = chineseWordsUpdate {
            await task.value
            if chineseWordsUpdate == task { break }
        }
    }

    public func apply(_ preferences: Preferences) {
        let previous = self.preferences
        self.preferences = preferences
        if schema != runtime.schema, runtime.isReady || preparing != nil {
            chinese = nil
            warmUp(.chinese)
        }
        if let japanese, previous.kanaInput != preferences.kanaInput || previous.japanesePredictions != preferences.japanesePredictions
            || previous.typoCorrection != preferences.typoCorrection || previous.zenzaiEnabled != preferences.zenzaiEnabled {
            japanese.update(japaneseConfiguration)
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
        configuration.typoCorrection = preferences.typoCorrection
        configuration.zenzaiModel = preferences.zenzaiEnabled && isZenzaiModelInstalled ? locations.zenzaiModel : nil
        try? FileManager.default.createDirectory(at: locations.azooKey, withIntermediateDirectories: true)
        return configuration
    }

    /// Reloads the Chinese engine after a model was installed or removed.
    public func modelsDidChange() {
        // Only redeploy Chinese if it was in use; otherwise it loads with the
        // new data on first use.
        if schema != runtime.schema, runtime.isReady || preparing != nil { chinese = nil; warmUp(.chinese) }
        japanese?.update(japaneseConfiguration)
    }
}
