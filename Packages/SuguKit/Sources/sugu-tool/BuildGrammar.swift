import Foundation
import SuguRime

/// Builds the bundled Chinese grammar model (ADR 0005): counts of character
/// collocations in Simplified sentences, in the form librime-octagram's
/// `build_grammar` reads. octagram adds `collocation_penalty` to a match's
/// log value and prefers no match at `non_collocation_penalty`, so values
/// are counts scaled to clear that bar only for collocations seen often.
enum BuildGrammar {
    /// Chosen on `Bench/zh.tsv`: any scale from 30 to 1000 improved it,
    /// 100 to 300 the most.
    static let scale = 100
    static let maximumLength = 6
    static let rearLength = 5

    static func run(corpus: URL, openCC: URL, builder: URL, output: URL, excluding benches: [URL]) throws {
        let started = Date()
        guard let simplified = ScriptConverter(configurations: [openCC.appendingPathComponent("t2s.json")]) else {
            throw BuildError.openCC
        }
        let excluded = try BenchSentences.keys(in: benches)
        var collocations: [String: Int] = [:]
        var rears: [String: Int] = [:]
        var sentences = 0, skipped = 0
        for line in try String(contentsOf: corpus, encoding: .utf8).split(whereSeparator: \.isNewline) {
            let sentence = BenchSentences.key(simplified.convert(String(line)))
            guard !sentence.isEmpty, !sentence.contains(" ") else { continue }
            if excluded.contains(sentence) { skipped += 1; continue }
            sentences += 1
            let characters = Array(sentence)
            for length in 2...maximumLength where length <= characters.count {
                for start in 0...(characters.count - length) {
                    collocations[String(characters[start..<(start + length)]), default: 0] += 1
                }
            }
            for length in 1...rearLength where length <= characters.count {
                rears[String(characters.suffix(length)), default: 0] += 1
            }
        }
        var input = ""
        var entries = 0
        for (key, count) in collocations where count >= 2 {
            input += "\(key) \(count * scale)\n"
            entries += 1
        }
        for (key, count) in rears where count >= 2 {
            input += "\(key)$ \(count * scale)\n"
            entries += 1
        }

        // build_grammar reads stdin and writes <language>.gram where it runs.
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("sugu-grammar-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        let counts = work.appendingPathComponent("counts.txt")
        try input.write(to: counts, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = builder
        process.arguments = [RimeSchema.bundledGrammarLanguage]
        process.currentDirectoryURL = work
        process.standardInput = try FileHandle(forReadingFrom: counts)
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        let built = work.appendingPathComponent("\(RimeSchema.bundledGrammarLanguage).gram")
        guard process.terminationStatus == 0, fm.fileExists(atPath: built.path) else { throw BuildError.builder }
        try? fm.removeItem(at: output)
        try fm.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: built, to: output)
        let size = (try? fm.attributesOfItem(atPath: output.path)[.size] as? Int) ?? 0
        let megabytes = String(format: "%.1f", Double(size) / 1_048_576)
        let seconds = String(format: "%.1f", Date().timeIntervalSince(started))
        print("grammar model: \(sentences) sentences (\(skipped) bench sentences left out), \(entries) entries, \(megabytes) MB in \(seconds)s")
    }

    enum BuildError: Error {
        case openCC, builder
    }
}
