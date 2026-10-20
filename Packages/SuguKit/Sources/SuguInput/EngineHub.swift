import Foundation
import SuguAzooKey
import SuguCore
import SuguLearning
import SuguRime

/// Owns the language engines for the process and keeps them in step with
/// preferences. Each engine is created on first use of its mode.
@MainActor
public final class EngineHub: EngineProvider {
    public struct Locations: Sendable {
        /// Bundled librime data (read-only).
        public var rimeShared: URL
        /// Per-user librime data: generated schema, grammar model, staging.
        public var rimeUser: URL
        /// AzooKey's working directory.
        public var azooKey: URL
        /// Downloaded models (grammar, Zenzai).
        public var models: URL

        public init(rimeShared: URL, rimeUser: URL, azooKey: URL, models: URL) {
            self.rimeShared = rimeShared
            self.rimeUser = rimeUser
            self.azooKey = azooKey
            self.models = models
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

    public init(locations: Locations, preferences: Preferences, store: LearnedStore?, version: String) {
        self.locations = locations
        self.preferences = preferences
        self.store = store
        self.version = version
        self.chineseScript = preferences.chineseScript
        self.runtime = RimeRuntime(directories: .init(shared: locations.rimeShared, user: locations.rimeUser))
    }

    // MARK: EngineProvider

    public func engine(for mode: InputMode) -> (any CompositionEngine)? {
        switch mode {
        case .chinese:
            guard runtime.isReady else { warmUp(.chinese); return nil }
            if let chinese { return chinese }
            let engine = RimeEngine(runtime: runtime, script: chineseScript)
            chinese = engine
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

    public var isGrammarModelInstalled: Bool {
        FileManager.default.fileExists(atPath: locations.grammarModel.path)
    }

    public var isZenzaiModelInstalled: Bool {
        FileManager.default.fileExists(atPath: locations.zenzaiModel.path)
    }

    public var isRimeIceInstalled: Bool {
        FileManager.default.fileExists(atPath: locations.rimeIceManifest.path)
    }

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
