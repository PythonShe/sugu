import Foundation
import SuguLM

/// Builds a character language model (ADR 0005) from a corpus with one
/// sentence per line, leaving out the bench's sentences so the bench
/// measures text the model has not seen.
enum BuildLanguageModel {
    static func run(corpus: URL, output: URL, excluding benches: [URL]) throws {
        let started = Date()
        let excluded = try BenchSentences.keys(in: benches)
        var builder = CharacterLanguageModelBuilder()
        var skipped = 0
        for line in try String(contentsOf: corpus, encoding: .utf8).split(whereSeparator: \.isNewline) {
            let sentence = String(line)
            if excluded.contains(BenchSentences.key(sentence)) { skipped += 1; continue }
            builder.add(sentence)
        }
        let (data, entries) = builder.build()
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: output, options: .atomic)
        let megabytes = String(format: "%.1f", Double(data.count) / 1_048_576)
        let seconds = String(format: "%.1f", Date().timeIntervalSince(started))
        print("language model: \(builder.sentences) sentences (\(skipped) bench sentences left out), \(entries) entries, \(megabytes) MB in \(seconds)s")
    }
}

/// The bench's expected texts, left out of corpora so the bench measures
/// text the models have not seen.
enum BenchSentences {
    static func keys(in benches: [URL]) throws -> Set<String> {
        var keys = Set<String>()
        for bench in benches {
            for line in try String(contentsOf: bench, encoding: .utf8).split(whereSeparator: \.isNewline) where !line.hasPrefix("#") {
                let fields = line.split(separator: "\t")
                if fields.count >= 2 { keys.insert(key(String(fields[1]))) }
            }
        }
        return keys
    }

    /// A sentence without surrounding space or final punctuation.
    static func key(_ sentence: String) -> String {
        var text = sentence.precomposedStringWithCompatibilityMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = text.last, "。！？!?.".contains(last) { text.removeLast() }
        return text
    }
}
