import Foundation
import SuguCore
import SuguLM
import SuguRime

/// Builds a character language model (ADR 0005) from a corpus with one
/// sentence per line, leaving out the bench's sentences so the bench
/// measures text the model has not seen. With `openCC`, sentences are
/// converted to simplified Chinese first, the script Sugu's Chinese
/// sentences are respelled in.
enum BuildLanguageModel {
    static func run(corpus: URL, output: URL, excluding benches: [URL], openCC: URL? = nil) throws {
        let started = Date()
        var excluded = Set<String>()
        for bench in benches {
            for line in try String(contentsOf: bench, encoding: .utf8).split(whereSeparator: \.isNewline) where !line.hasPrefix("#") {
                let fields = line.split(separator: "\t")
                if fields.count >= 2 { excluded.insert(key(String(fields[1]))) }
            }
        }
        let simplified = try openCC.map { directory in
            guard let converter = ScriptConverter.toScript(.simplified, openCC: directory) else { throw BuildError.openCC(directory) }
            return converter
        }
        var builder = CharacterLanguageModelBuilder()
        var skipped = 0
        for line in try String(contentsOf: corpus, encoding: .utf8).split(whereSeparator: \.isNewline) {
            let sentence = simplified?.convert(String(line)) ?? String(line)
            if excluded.contains(key(sentence)) { skipped += 1; continue }
            builder.add(sentence)
        }
        let (data, entries) = builder.build()
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: output, options: .atomic)
        let megabytes = String(format: "%.1f", Double(data.count) / 1_048_576)
        let seconds = String(format: "%.1f", Date().timeIntervalSince(started))
        print("language model: \(builder.sentences) sentences (\(skipped) bench sentences left out), \(entries) entries, \(megabytes) MB in \(seconds)s")
    }

    enum BuildError: Error {
        case openCC(URL)
    }

    private static func key(_ sentence: String) -> String {
        var text = sentence.precomposedStringWithCompatibilityMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = text.last, "。！？!?.".contains(last) { text.removeLast() }
        return text
    }
}
