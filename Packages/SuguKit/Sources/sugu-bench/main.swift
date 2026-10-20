import Foundation
import SuguCore

// sugu-bench: accuracy and latency of the whole input pipeline on the test
// sets in Bench/. Run in release:
//   swift run -c release sugu-bench --data ../../Data --bench ../../Bench [--json out.json] [--check] [--zenzai model.gguf] [--grammar model.gram]
// --check exits non-zero when a budget in AGENTS.md is exceeded.
let arguments = Array(CommandLine.arguments.dropFirst())

func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

guard let data = option("--data"), let bench = option("--bench") else {
    FileHandle.standardError.write(Data("usage: sugu-bench --data <dir> --bench <dir> [--json <file>] [--check] [--zenzai <model.gguf>] [--grammar <model.gram>]\n".utf8))
    exit(2)
}

let zenzai = option("--zenzai").map { URL(fileURLWithPath: $0) }
let grammar = option("--grammar").map { URL(fileURLWithPath: $0) }
let report = try await Bench.run(data: URL(fileURLWithPath: data), bench: URL(fileURLWithPath: bench), zenzaiModel: zenzai, grammarModel: grammar) { preferences in
    // Variants for comparing configurations.
    if arguments.contains("--no-predictions") { preferences.japanesePredictions = false }
    if arguments.contains("--no-typo-correction") { preferences.typoCorrection = false }
    if arguments.contains("--live-conversion") { preferences.liveConversion = true }
}
print(report.summary)
if let json = option("--json") {
    try report.json().write(to: URL(fileURLWithPath: json))
}
if arguments.contains("--check"), !report.withinBudgets {
    FileHandle.standardError.write(Data("budget exceeded\n".utf8))
    exit(1)
}
