import Foundation
import SuguCore

// sugu-bench: accuracy and latency of the whole input pipeline on the test
// sets in Bench/. Run in release:
//   swift run -c release sugu-bench --data ../../Data --bench ../../Bench [--json out.json] [--check] [--zenzai model.gguf] [--grammar model.gram] [--no-language-model]
// Variants: --no-predictions, --no-typo-correction, --live-conversion, --fuzzy-pinyin,
// --kana-input, --zhuyin, --scheme <PinyinScheme>, --script <ChineseScript>.
// --check exits non-zero when a budget in AGENTS.md is exceeded.
let arguments = Array(CommandLine.arguments.dropFirst())

func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

guard let data = option("--data"), let bench = option("--bench") else {
    FileHandle.standardError.write(Data("usage: sugu-bench --data <dir> --bench <dir> [--json <file>] [--check] [--zenzai <model.gguf>] [--grammar <model.gram>] [--no-language-model]\n".utf8))
    exit(2)
}

// --fuzz <sessions> [--seed <n>] [--fuzz-session <n>] [--fuzz-trace]: random
// key sequences per language, checked after every key, instead of the
// bench. Runs replay with SWIFT_DETERMINISTIC_HASHING=1 in the environment.
let configure: (inout Preferences) -> Void = { preferences in
    // Variants for comparing configurations.
    if arguments.contains("--no-predictions") { preferences.japanesePredictions = false }
    if arguments.contains("--no-typo-correction") { preferences.typoCorrection = false }
    if arguments.contains("--live-conversion") { preferences.liveConversion = true }
    if arguments.contains("--fuzzy-pinyin") { preferences.fuzzyPinyin = Set(FuzzyPinyin.allCases) }
    if arguments.contains("--kana-input") { preferences.kanaInput = true }
    if arguments.contains("--zhuyin") { preferences.chineseKeyboard = .zhuyin }
    if let scheme = option("--scheme").flatMap(PinyinScheme.init(rawValue:)) { preferences.pinyinScheme = scheme }
    if let script = option("--script").flatMap(ChineseScript.init(rawValue:)) { preferences.chineseScript = script }
}
if let count = option("--fuzz").flatMap(Int.init) {
    let seed = option("--seed").flatMap(UInt64.init) ?? 1
    let sessions = option("--fuzz-session").flatMap(Int.init).map { $0..<($0 + 1) } ?? 0..<count
    let failures = try await Fuzz.run(data: URL(fileURLWithPath: data), sessions: sessions, seed: seed, trace: arguments.contains("--fuzz-trace"), configure: configure)
    print("fuzz: \(sessions.count) sessions per language, seed \(seed), \(failures.count) failures")
    failures.forEach { print($0) }
    exit(failures.isEmpty ? 0 : 1)
}

let zenzai = option("--zenzai").map { URL(fileURLWithPath: $0) }
let grammar = option("--grammar").map { URL(fileURLWithPath: $0) }
let report = try await Bench.run(data: URL(fileURLWithPath: data), bench: URL(fileURLWithPath: bench), zenzaiModel: zenzai, grammarModel: grammar,
                                languageModels: !arguments.contains("--no-language-model"), configure: configure)
print(report.summary)
if let json = option("--json") {
    try report.json().write(to: URL(fileURLWithPath: json))
}
if arguments.contains("--check"), !report.withinBudgets {
    FileHandle.standardError.write(Data("budget exceeded\n".utf8))
    exit(1)
}
