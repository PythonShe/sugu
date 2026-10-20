import Foundation
import Testing
import SuguAzooKey
import SuguCore
import SuguLM
import SuguRime

/// End-to-end checks against the real engines and the data built by
/// `scripts/build-data.sh`. Skipped when `Data/` has not been built.
let engineDataDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Data")
let hasEngineData = FileManager.default.fileExists(atPath: engineDataDirectory.appendingPathComponent("Rime/build/sugu.table.bin").path)

/// A model built from `sentences` alone.
@MainActor
func testLanguageModel(_ sentences: [String], personal: PersonalNGrams? = nil) throws -> BlendedLanguageModel {
    var builder = CharacterLanguageModelBuilder()
    builder.minimumCount = 1
    for sentence in sentences { builder.add(sentence) }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("sugu-engine-lm-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: url) }
    try builder.build().data.write(to: url)
    return BlendedLanguageModel(base: try CharacterLanguageModel(contentsOf: url), personal: personal)
}

/// The bundled model for a mode, from `Data/LM`.
@MainActor
func bundledLanguageModel(_ name: String) throws -> BlendedLanguageModel {
    BlendedLanguageModel(base: try CharacterLanguageModel(contentsOf: engineDataDirectory.appendingPathComponent("LM/\(name).lm")))
}

/// librime keeps process-wide state, so every test shares one runtime.
@MainActor
enum Shared {
    static let user = FileManager.default.temporaryDirectory.appendingPathComponent("sugu-engine-tests-\(getpid())")
    static let runtime = RimeRuntime(directories: .init(shared: engineDataDirectory.appendingPathComponent("Rime"), user: user))
}
