import Foundation
import SuguCore
import SuguRime

// sugu-tool: build-time and diagnostic commands. Never touches the
// installed input method or the user's input sources.
let arguments = Array(CommandLine.arguments.dropFirst())
let usage = """
usage: sugu-tool build-data --wanxiang <dir> --opencc <dir> --cldr <dir> --out <dir> [--version <v>]
       sugu-tool build-lm --corpus <file> --out <file> [--opencc <dir>] [--exclude <bench.tsv>]...
       sugu-tool convert --data <dir> (--chinese | --japanese) [--user <dir>] [--scheme <name>] [--rime-ice] [--grammar] <reading>...
"""

func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

do {
    switch arguments.first {
    case "build-data":
        guard let wanxiang = option("--wanxiang"), let openCC = option("--opencc"), let cldr = option("--cldr"), let out = option("--out") else { fail(usage) }
        try await BuildData.run(
            wanxiang: URL(fileURLWithPath: wanxiang),
            openCC: URL(fileURLWithPath: openCC),
            cldr: URL(fileURLWithPath: cldr),
            output: URL(fileURLWithPath: out),
            version: option("--version") ?? "dev"
        )
    case "build-lm":
        guard let corpus = option("--corpus"), let out = option("--out") else { fail(usage) }
        let excluded = arguments.indices.filter { arguments[$0] == "--exclude" && $0 + 1 < arguments.count }.map { URL(fileURLWithPath: arguments[$0 + 1]) }
        try BuildLanguageModel.run(corpus: URL(fileURLWithPath: corpus), output: URL(fileURLWithPath: out), excluding: excluded,
                                   openCC: option("--opencc").map { URL(fileURLWithPath: $0) })
    case "convert":
        guard let data = option("--data") else { fail(usage) }
        let user = option("--user")
        let readings = arguments.dropFirst().filter { !$0.hasPrefix("--") && $0 != data && $0 != user && $0 != option("--scheme") }
        let schema = RimeSchema(
            scheme: option("--scheme").flatMap(PinyinScheme.init(rawValue:)) ?? .fullPinyin,
            useGrammar: arguments.contains("--grammar"),
            dictionary: arguments.contains("--rime-ice") ? .rimeIce : .wanxiang
        )
        try await Convert.run(
            data: URL(fileURLWithPath: data),
            user: user.map { URL(fileURLWithPath: $0) },
            schema: schema,
            japanese: arguments.contains("--japanese"),
            readings: Array(readings)
        )
    default:
        fail(usage)
    }
} catch {
    fail("error: \(error)")
}
