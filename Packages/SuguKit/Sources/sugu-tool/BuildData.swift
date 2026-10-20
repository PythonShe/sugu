import Foundation
import SuguCore
import SuguRime

/// Assembles `Data/`: the shared librime directory with prebuilt tables, and
/// word lists extracted from the dictionary data.
@MainActor
enum BuildData {
    static func run(wanxiang: URL, openCC: URL, output: URL, version: String) async throws {
        let fm = FileManager.default
        let rime = output.appendingPathComponent("Rime")
        try? fm.removeItem(at: rime)
        try RimeSharedData.write(to: rime, wanxiang: wanxiang, openCC: openCC, version: version)

        // Precompile with the same runtime code the app uses.
        let staging = fm.temporaryDirectory.appendingPathComponent("sugu-build-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: staging) }
        let started = Date()
        let runtime = RimeRuntime(directories: .init(shared: rime, user: staging))
        try await runtime.prepare(RimeSchema(), version: version)
        print("compiled dictionary in \(String(format: "%.1f", Date().timeIntervalSince(started)))s")

        let prebuilt = rime.appendingPathComponent("build")
        try fm.createDirectory(at: prebuilt, withIntermediateDirectories: true)
        for suffix in ["table.bin", "reverse.bin", "prism.bin"] {
            let name = "\(RimeSchema.dictionaryName).\(suffix)"
            let source = staging.appendingPathComponent("build/\(name)")
            guard fm.fileExists(atPath: source.path) else { throw BuildError.missing(name) }
            try fm.moveItem(at: source, to: prebuilt.appendingPathComponent(name))
        }
        // Sources are not shipped: librime reuses a prebuilt table when its
        // source is absent.
        try fm.removeItem(at: rime.appendingPathComponent("dicts"))
        try fm.removeItem(at: rime.appendingPathComponent("\(RimeSchema.dictionaryName).dict.yaml"))

        let lexicon = output.appendingPathComponent("Lexicon")
        try fm.createDirectory(at: lexicon, withIntermediateDirectories: true)
        let zi = try String(contentsOf: wanxiang.appendingPathComponent("dicts/zi.dict.yaml"), encoding: .utf8)
        let syllables = Lexicon.syllables(fromRimeDictionary: zi).sorted()
        try (syllables.joined(separator: "\n") + "\n").write(to: lexicon.appendingPathComponent(Lexicon.syllablesFile), atomically: true, encoding: .utf8)
        let english = try String(contentsOf: wanxiang.appendingPathComponent("dicts/en.dict.yaml"), encoding: .utf8)
        let words = Lexicon.englishWords(fromRimeDictionary: english, limit: 30_000)
        try (words.joined(separator: "\n") + "\n").write(to: lexicon.appendingPathComponent(Lexicon.englishWordsFile), atomically: true, encoding: .utf8)
        let jichu = try String(contentsOf: wanxiang.appendingPathComponent("dicts/jichu.dict.yaml"), encoding: .utf8)
        let pinyinWords = Lexicon.pinyinWords(fromRimeDictionaries: [zi, jichu], minimumWeight: 1000)
        try (pinyinWords.joined(separator: "\n") + "\n").write(to: lexicon.appendingPathComponent(Lexicon.pinyinWordsFile), atomically: true, encoding: .utf8)
        print("lexicon: \(syllables.count) syllables, \(words.count) English words, \(pinyinWords.count) pinyin words")
    }

    enum BuildError: Error {
        case missing(String)
    }
}
