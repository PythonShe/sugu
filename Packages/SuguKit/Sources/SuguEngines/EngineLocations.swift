import Foundation
import SuguCore
import SuguRime

extension EngineHub {
    /// Where the engines' data lives: bundled, per user, and downloaded.
    public struct Locations: Sendable {
        /// Bundled librime data (read-only).
        public var rimeShared: URL
        /// Per-user librime data: generated schema, grammar model, staging.
        public var rimeUser: URL
        /// AzooKey's working directory.
        public var azooKey: URL
        /// Downloaded Zenzai models; the grammar model goes with librime's
        /// user data.
        public var models: URL
        /// Bundled word lists (`Lexicon`), for the pinyin syllables.
        public var lexicon: URL
        /// Bundled character language models (`LM`, ADR 0005).
        public var languageModels: URL?

        public init(rimeShared: URL, rimeUser: URL, azooKey: URL, models: URL, lexicon: URL, languageModels: URL? = nil) {
            self.rimeShared = rimeShared
            self.rimeUser = rimeUser
            self.azooKey = azooKey
            self.models = models
            self.lexicon = lexicon
            self.languageModels = languageModels
        }

        public func languageModel(_ mode: InputMode) -> URL? {
            languageModels?.appendingPathComponent("\(mode == .japanese ? "ja" : "zh").lm")
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
}
